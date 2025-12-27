//
//  TimerViewModel.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/24.
//

import Foundation
import Combine
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import AudioToolbox
import UserNotifications
import ActivityKit
#endif

class TimerViewModel: ObservableObject {
    @Published var timerState = TimerState()
    @Published var projectManager = ProjectManager.shared
    
    private var timer: AnyCancellable?
    private var sessionStartTime: Date?
    private var accumulatedPausedTime: TimeInterval = 0
    private var lastPauseTime: Date?
    
    // For iOS background handling
    private var backgroundTime: Date?
    
    // Music managers
    var spotifyManager: SpotifyManager?
    var appleMusicManager: AppleMusicManager?
    var selectedService: MusicService = .none
    
    // 🔥 Live Activity
    #if os(iOS)
    private var currentActivity: Activity<TimerAttributes>?
    #endif
    
    var currentPhaseDuration: TimeInterval {
        switch timerState.currentPhase {
        case .warmup:
            return TimeInterval(timerState.warmupDuration * 60)
        case .work:
            return TimeInterval(timerState.workDuration * 60)
        case .shortBreak:
            return TimeInterval(timerState.shortBreakDuration * 60)
        case .longBreak:
            return TimeInterval(timerState.longBreakDuration * 60)
        }
    }
    
    // MARK: - Timer Controls
    
    func startWarmup() {
        CrashLogger.shared.logEvent("Starting warmup")
        timerState.startWarmup()
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        startCountdown()
        playMusicForCurrentPhase()
        
        #if os(iOS)
        timerState.saveToUserDefaults()
        scheduleTimerCompletionNotification()
        startLiveActivity()
        #endif
    }
    
    func toggleTimer() {
        if timerState.isPaused {
            // Resume
            CrashLogger.shared.logEvent("Resuming timer - Phase: \(timerState.currentPhase)")
            if let pauseStart = lastPauseTime {
                accumulatedPausedTime += Date().timeIntervalSince(pauseStart)
                lastPauseTime = nil
            }
            timerState.resume()
            startCountdown()
            playMusicForCurrentPhase()
            
            #if os(iOS)
            timerState.saveToUserDefaults()
            scheduleTimerCompletionNotification()
            updateLiveActivity()
            #endif
        } else if timerState.isRunning {
            // Pause
            CrashLogger.shared.logEvent("Pausing timer - Phase: \(timerState.currentPhase), TimeRemaining: \(Int(timerState.timeRemaining))s")
            lastPauseTime = Date()
            timerState.pause()
            stopCountdown()
            pauseMusic()
            
            #if os(iOS)
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            timerState.saveToUserDefaults()
            updateLiveActivity()
            #endif
        } else {
            // Start (not running, not paused)
            CrashLogger.shared.logEvent("Starting timer - Phase: \(timerState.currentPhase)")
            
            if timerState.currentPhase == .warmup {
                if timerState.warmupDuration > 0 {
                    startWarmup()
                } else {
                    // No warmup configured - skip to work
                    timerState.currentPhase = .work
                    timerState.timeRemaining = TimeInterval(timerState.workDuration * 60)
                    timerState.isRunning = true
                    timerState.isPaused = false
                    sessionStartTime = Date()
                    accumulatedPausedTime = 0
                    startCountdown()
                    playMusicForCurrentPhase()
                    #if os(iOS)
                    timerState.saveToUserDefaults()
                    scheduleTimerCompletionNotification()
                    startLiveActivity()
                    #endif
                }
            } else if timerState.currentPhase == .work && timerState.completedWorkSessions == 0 {
                // Starting first work session (warmup was disabled)
                timerState.isRunning = true
                timerState.isPaused = false
                sessionStartTime = Date()
                accumulatedPausedTime = 0
                startCountdown()
                playMusicForCurrentPhase()
                #if os(iOS)
                timerState.saveToUserDefaults()
                scheduleTimerCompletionNotification()
                startLiveActivity()
                #endif
            } else {
                // Continue from wherever we were (after a break, etc.)
                startNextSession()
            }
        }
    }
    
    func skipToNext() {
        CrashLogger.shared.logEvent("Skipping to next phase - Current: \(timerState.currentPhase)")
        
        #if os(iOS)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        CrashLogger.shared.logEvent("🔔 Cancelled notifications on skip")
        #endif
        
        stopCountdown()
        playBeep()
        
        // Log elapsed time before skipping
        logElapsedTime()
        
        timerState.startNextPhase()
        
        CrashLogger.shared.logEvent("🔄 SKIPPED TO - Phase: \(timerState.currentPhase), Sessions: \(timerState.completedWorkSessions)")
        
        // Reset session tracking for next phase
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        lastPauseTime = nil
        
        #if os(iOS)
        timerState.saveToUserDefaults()
        #endif
        
        if timerState.currentPhase != .warmup {
            startCountdown()
            playMusicForCurrentPhase()
            
            #if os(iOS)
            scheduleTimerCompletionNotification()
            CrashLogger.shared.logEvent("🔔 Scheduled new notification after skip")
            updateLiveActivity()
            #endif
        }
    }
    
    func reset() {
        CrashLogger.shared.logEvent("Resetting timer")
        // Log elapsed time before resetting (if timer was active)
        if timerState.isRunning || timerState.isPaused {
            logElapsedTime()
        }
        
        // Stop timer first
        stopCountdown()
        
        // Reset state (will automatically handle warmup=0 case)
        timerState.reset()
        
        sessionStartTime = nil
        accumulatedPausedTime = 0
        lastPauseTime = nil
        backgroundTime = nil
        
        // Stop music (safely)
        pauseMusic()
        
        #if os(iOS)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        TimerState.clearSavedState()
        SharedTimerState.clear()
        endLiveActivity()
        #endif
    }
    
    // MARK: - iOS Background Handling
    
    /// Schedule notification for when timer completes
    private func scheduleTimerCompletionNotification() {
        #if os(iOS)
        guard timerState.isRunning else { return }
        
        // 🔥 FIX: Don't schedule if time remaining is invalid
        guard timerState.timeRemaining > 0 else {
            print("⚠️ Cannot schedule notification - timeRemaining is \(timerState.timeRemaining)")
            return
        }
        
        // Cancel any existing notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        let content = UNMutableNotificationContent()
        content.sound = .default
        
        switch timerState.currentPhase {
        case .warmup:
            content.title = "Warmup Complete"
            content.body = "Time to start working!"
        case .work:
            content.title = "Work Session Complete"
            content.body = "Great job! Time for a break."
        case .shortBreak:
            content.title = "Break Complete"
            content.body = "Ready to get back to work?"
        case .longBreak:
            content.title = "Long Break Complete"
            content.body = "Feeling refreshed? Let's continue!"
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: timerState.timeRemaining,
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "timer_completion",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule notification: \(error)")
                CrashLogger.shared.logEvent("Failed to schedule notification: \(error.localizedDescription)")
            } else {
                print("✅ Notification scheduled for \(self.timerState.timeRemaining)s")
            }
        }
        #endif
    }
    
    func handleBackgroundTransition() {
        #if os(iOS)
        CrashLogger.shared.logEvent("📱 BACKGROUND TRANSITION CALLED")
        
        if backgroundTime != nil {
            CrashLogger.shared.logEvent("⚠️ Already backgrounded, ignoring duplicate call")
            return
        }
        
        guard timerState.isRunning else {
            CrashLogger.shared.logEvent("⏹️ Timer not running, ignoring background")
            return
        }
        
        CrashLogger.shared.logEvent("💾 SAVING - Phase: \(timerState.currentPhase), TimeRemaining: \(Int(timerState.timeRemaining))s, Session: \(timerState.completedWorkSessions)")
        backgroundTime = Date()
        
        timerState.saveToUserDefaults(forceSync: true)
        saveToSharedState()
        
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        scheduleTimerCompletionNotification()
        
        stopCountdown()
        
        CrashLogger.shared.logEvent("✅ Background transition complete. backgroundTime set to: \(backgroundTime!)")
        print("📱 App backgrounded at \(Date()) - timer will continue tracking")
        #endif
    }
    
    func handleForegroundTransition() {
        #if os(iOS)
        CrashLogger.shared.logEvent("📱 FOREGROUND TRANSITION CALLED")
        
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // 🔥 First restore from Live Activity if it exists
        restoreFromLiveActivityOrShared()
        
        // 🔥 FIX: Always validate state, even without backgroundTime
        if timerState.timeRemaining > 0 && timerState.isRunning && !timerState.isPaused {
            CrashLogger.shared.logEvent("▶️ Resuming countdown")
            startCountdown()
            playMusicForCurrentPhase()
            scheduleTimerCompletionNotification()
        }
        
        // Now handle backgroundTime if it exists
        guard let bgTime = backgroundTime else {
            CrashLogger.shared.logEvent("⚠️ No backgroundTime recorded - either never backgrounded or state lost")
            return  // This is OK now - state was already restored above
        }
        
        backgroundTime = nil
        
        let timeInBackground = Date().timeIntervalSince(bgTime)
        CrashLogger.shared.logEvent("📊 Was in background for: \(Int(timeInBackground))s")
        #endif
    }
    
    // MARK: - State Restoration
    
    func restoreStateIfNeeded() {
        #if os(iOS)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        CrashLogger.shared.logEvent("🔔 Cancelled all old notifications during restore")
        
        // 🔥 Restore from Live Activity or shared state
        restoreFromLiveActivityOrShared()
        
        if timerState.isRunning && !timerState.isPaused && timerState.timeRemaining > 0 {
            startCountdown()
            playMusicForCurrentPhase()
            scheduleTimerCompletionNotification()
        }
        #endif
    }
    
    // MARK: - Project Switching
    
    func switchProject(to project: Project?) {
        CrashLogger.shared.logEvent("Switching project to: \(project?.displayName ?? "Freestyle")")
        if timerState.isRunning || timerState.isPaused {
            logElapsedTime()
        }
        
        if timerState.isRunning {
            lastPauseTime = Date()
            timerState.pause()
            stopCountdown()
            pauseMusic()
        }
        
        projectManager.selectProject(project)
        print("🔄 Switched to project: \(project?.displayName ?? "Freestyle")")
        
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        if timerState.isPaused {
            lastPauseTime = Date()
        }
    }
    
    // MARK: - Private Timer Logic
    
    private func startCountdown() {
        timer?.cancel()
        timer = nil
        
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }
    
    private func stopCountdown() {
        timer?.cancel()
        timer = nil
    }
    
    private func tick() {
        guard timerState.isRunning, !timerState.isPaused else {
            stopCountdown()
            return
        }
        
        guard timerState.timeRemaining > 0 else {
            handleTimerComplete()
            return
        }
        
        timerState.timeRemaining -= 1
        
        #if os(iOS)
        // Update Live Activity every 10 seconds
        if Int(timerState.timeRemaining) % 10 == 0 {
            updateLiveActivity()
        }
        
        if Int(timerState.timeRemaining) % 30 == 0 {
            timerState.saveToUserDefaults()
            saveToSharedState()
            CrashLogger.shared.logEvent("💾 Auto-save (every 30s) - Phase: \(timerState.currentPhase), Remaining: \(Int(timerState.timeRemaining))s")
        }
        #endif
    }
    
    private func handleTimerComplete() {
        CrashLogger.shared.logEvent("Timer completed - Phase: \(timerState.currentPhase), Sessions: \(timerState.completedWorkSessions)")
        
        #if os(iOS)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        CrashLogger.shared.logEvent("🔔 Cancelled all notifications on phase complete")
        #endif
        
        stopCountdown()
        playBeep()
        
        let completedPhase = timerState.currentPhase
        
        logElapsedTime()
        
        timerState.startNextPhase()
        
        CrashLogger.shared.logEvent("🔄 PHASE TRANSITION - From: \(completedPhase) → To: \(timerState.currentPhase), Sessions: \(timerState.completedWorkSessions)")
        
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        lastPauseTime = nil
        
        #if os(iOS)
        CrashLogger.shared.logEvent("💾 SAVING STATE after phase transition")
        timerState.saveToUserDefaults(forceSync: true)
        saveToSharedState()
        #endif
        
        NotificationManager.shared.sendPhaseCompleteNotification(
            phase: completedPhase,
            nextPhase: timerState.currentPhase
        )
        
        CrashLogger.shared.logEvent("Starting next phase: \(timerState.currentPhase)")
        
        if timerState.currentPhase != .warmup || timerState.isRunning {
            startCountdown()
            playMusicForCurrentPhase()
            
            #if os(iOS)
            scheduleTimerCompletionNotification()
            CrashLogger.shared.logEvent("🔔 Scheduled new notification for phase: \(timerState.currentPhase)")
            updateLiveActivity()
            #endif
        }
    }
    
    private func startNextSession() {
        timerState.startNextPhase()
        timerState.isRunning = true
        timerState.isPaused = false
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        startCountdown()
        playMusicForCurrentPhase()
        
        #if os(iOS)
        timerState.saveToUserDefaults()
        scheduleTimerCompletionNotification()
        updateLiveActivity()
        #endif
    }
    
    // MARK: - Session Logging
    
    private func logElapsedTime() {
        let currentPhase = timerState.currentPhase
        
        guard currentPhase != .warmup else { return }
        
        guard let startTime = sessionStartTime else {
            print("⚠️ No session start time, cannot log elapsed time")
            return
        }
        
        var totalPausedTime = accumulatedPausedTime
        if timerState.isPaused, let pauseStart = lastPauseTime {
            totalPausedTime += Date().timeIntervalSince(pauseStart)
        }
        
        let elapsedTime = Date().timeIntervalSince(startTime) - totalPausedTime
        let actualDurationMinutes = Int(round(elapsedTime / 60.0))
        
        guard actualDurationMinutes >= 1 else {
            print("⏱️ Less than 1 minute elapsed (\(Int(elapsedTime))s), not logging")
            return
        }
        
        let currentProjectId = projectManager.currentProjectId
        let projectName = projectManager.currentProject?.displayName ?? "Freestyle"
        
        print("📊 Logging \(actualDurationMinutes) min of \(currentPhase) to \(projectName)")
        CrashLogger.shared.logEvent("Logged \(actualDurationMinutes)min of \(currentPhase) to \(projectName)")
        
        switch currentPhase {
        case .work:
            StatisticsManager.shared.logSession(
                type: .work,
                durationMinutes: actualDurationMinutes,
                projectId: currentProjectId
            )
        case .shortBreak:
            StatisticsManager.shared.logSession(
                type: .shortBreak,
                durationMinutes: actualDurationMinutes,
                projectId: currentProjectId
            )
        case .longBreak:
            StatisticsManager.shared.logSession(
                type: .longBreak,
                durationMinutes: actualDurationMinutes,
                projectId: currentProjectId
            )
        case .warmup:
            break
        }
    }
    
    // MARK: - Music Integration
    
    private func pauseMusic() {
        switch selectedService {
        case .spotify:
            if let spotify = spotifyManager, spotify.isAuthenticated {
                Task {
                    await spotify.pausePlayback()
                }
            }
        case .appleMusic:
            if let appleMusic = appleMusicManager, appleMusic.isAuthorized {
                appleMusic.pause()
            }
        case .none:
            break
        }
    }
    
    private func playMusicForCurrentPhase() {
        switch selectedService {
        case .spotify:
            playSpotifyMusic()
        case .appleMusic:
            playAppleMusic()
        case .none:
            break
        }
    }
    
    private func playSpotifyMusic() {
        guard let spotify = spotifyManager, spotify.isAuthenticated else {
            CrashLogger.shared.logEvent("🎵 Spotify not authenticated, skipping music")
            return
        }
        
        let currentPhase = timerState.currentPhase
        CrashLogger.shared.logEvent("🎵 SPOTIFY START - Phase: \(currentPhase)")
        
        #if os(macOS)
        Task.detached {
            await self.executeSpotifyPlayback(for: currentPhase, spotify: spotify)
        }
        #else
        Task {
            await executeSpotifyPlayback(for: currentPhase, spotify: spotify)
        }
        #endif
    }
    
    private func executeSpotifyPlayback(for phase: TimerPhase, spotify: SpotifyManager) async {
        switch phase {
        case .warmup, .shortBreak, .longBreak:
            if let playlistId = spotify.selectedBreakPlaylistId {
                CrashLogger.shared.logEvent("🎵 SPOTIFY - Playing BREAK playlist ID: \(playlistId)")
                print("🎵 Playing BREAK playlist: \(playlistId)")
                await spotify.playPlaylist(playlistId: playlistId)
                CrashLogger.shared.logEvent("🎵 SPOTIFY - Break playlist command sent")
            } else {
                CrashLogger.shared.logEvent("🎵 SPOTIFY - No break playlist, pausing")
                await spotify.pausePlayback()
            }
        case .work:
            if let playlistId = spotify.selectedWorkPlaylistId {
                CrashLogger.shared.logEvent("🎵 SPOTIFY - Playing WORK playlist ID: \(playlistId)")
                print("🎵 Playing WORK playlist: \(playlistId)")
                await spotify.playPlaylist(playlistId: playlistId)
                CrashLogger.shared.logEvent("🎵 SPOTIFY - Work playlist command sent")
            } else {
                CrashLogger.shared.logEvent("🎵 SPOTIFY - No work playlist, pausing")
                await spotify.pausePlayback()
            }
        }
    }
    
    private func playAppleMusic() {
        guard let appleMusic = appleMusicManager, appleMusic.isAuthorized else {
            CrashLogger.shared.logEvent("🎵 Apple Music not authorized, skipping music")
            return
        }
        
        let currentPhase = timerState.currentPhase
        CrashLogger.shared.logEvent("🎵 APPLE MUSIC START - Phase: \(currentPhase)")
        
        #if os(macOS)
        Task.detached {
            await self.executeAppleMusicPlayback(for: currentPhase, appleMusic: appleMusic)
        }
        #else
        Task {
            await executeAppleMusicPlayback(for: currentPhase, appleMusic: appleMusic)
        }
        #endif
    }
    
    private func executeAppleMusicPlayback(for phase: TimerPhase, appleMusic: AppleMusicManager) async {
        switch phase {
        case .warmup, .shortBreak, .longBreak:
            if let playlistId = appleMusic.selectedBreakPlaylistId {
                CrashLogger.shared.logEvent("🎵 APPLE MUSIC - Playing BREAK playlist ID: \(playlistId)")
                print("🎵 Playing BREAK playlist: \(playlistId)")
                await appleMusic.playPlaylist(id: playlistId)
                CrashLogger.shared.logEvent("🎵 APPLE MUSIC - Break playlist command sent")
            } else {
                CrashLogger.shared.logEvent("🎵 APPLE MUSIC - No break playlist, pausing")
                appleMusic.pause()
            }
        case .work:
            if let playlistId = appleMusic.selectedWorkPlaylistId {
                CrashLogger.shared.logEvent("🎵 APPLE MUSIC - Playing WORK playlist ID: \(playlistId)")
                print("🎵 Playing WORK playlist: \(playlistId)")
                await appleMusic.playPlaylist(id: playlistId)
                CrashLogger.shared.logEvent("🎵 APPLE MUSIC - Work playlist command sent")
            } else {
                CrashLogger.shared.logEvent("🎵 APPLE MUSIC - No work playlist, pausing")
                appleMusic.pause()
            }
        }
    }
    
    // MARK: - Live Activity Management
    
    #if os(iOS)
    
    // MARK: - Shared State Management
    
    private func saveToSharedState() {
        let sharedState = SharedTimerState(
            phase: timerState.currentPhase,
            timeRemaining: timerState.timeRemaining,
            isRunning: timerState.isRunning,
            isPaused: timerState.isPaused,
            completedSessions: timerState.completedWorkSessions,
            lastUpdateTime: Date(),
            workDuration: timerState.workDuration,
            shortBreakDuration: timerState.shortBreakDuration,
            longBreakDuration: timerState.longBreakDuration,
            sessionsUntilLongBreak: timerState.sessionsUntilLongBreak
        )
        SharedTimerState.save(sharedState)
    }
    
    func restoreFromLiveActivityOrShared() {
        // Priority 1: Try to restore from Live Activity (most up-to-date)
        if let activity = Activity<TimerAttributes>.activities.first {
            let state = activity.content.state
            let timeSinceUpdate = Date().timeIntervalSince(state.lastUpdateTime)
            
            print("🔄 Restoring from Live Activity - Phase: \(state.phase), Time since update: \(Int(timeSinceUpdate))s")
            
            // Calculate actual remaining time
            var actualRemaining = state.timeRemaining
            if state.isRunning && !state.isPaused {
                actualRemaining -= timeSinceUpdate
            }
            
            // Update timer state
            timerState.currentPhase = state.phase
            timerState.timeRemaining = max(0, actualRemaining)
            timerState.isRunning = state.isRunning
            timerState.isPaused = state.isPaused
            timerState.completedWorkSessions = state.completedSessions
            
            // 🔥 FIX: If time ran out, reset to not running
            if timerState.timeRemaining <= 0 {
                timerState.isRunning = false
                timerState.isPaused = false
                print("⚠️ Timer completed while app was closed - resetting")
                // Keep existing Live Activity reference but don't start countdown
                currentActivity = activity
                return
            }
            
            sessionStartTime = Date()
            accumulatedPausedTime = 0
            
            print("✅ Restored from Live Activity - Phase: \(timerState.currentPhase), Remaining: \(Int(timerState.timeRemaining))s, isPaused: \(timerState.isPaused)")
            
            // Keep existing Live Activity
            currentActivity = activity
            return
        }
        
        // Priority 2: Restore from shared state
        if let sharedState = SharedTimerState.load() {
            let timeSinceUpdate = Date().timeIntervalSince(sharedState.lastUpdateTime)
            
            print("🔄 Restoring from Shared State - Phase: \(sharedState.phase), Time since update: \(Int(timeSinceUpdate))s")
            
            // Calculate actual remaining time
            var actualRemaining = sharedState.timeRemaining
            if sharedState.isRunning && !sharedState.isPaused {
                actualRemaining -= timeSinceUpdate
            }
            
            // Update timer state
            timerState.currentPhase = sharedState.phase
            timerState.timeRemaining = max(0, actualRemaining)
            timerState.isRunning = sharedState.isRunning
            timerState.isPaused = sharedState.isPaused
            timerState.completedWorkSessions = sharedState.completedSessions
            timerState.workDuration = sharedState.workDuration
            timerState.shortBreakDuration = sharedState.shortBreakDuration
            timerState.longBreakDuration = sharedState.longBreakDuration
            timerState.sessionsUntilLongBreak = sharedState.sessionsUntilLongBreak
            
            // 🔥 FIX: If time ran out, reset to not running
            if timerState.timeRemaining <= 0 {
                timerState.isRunning = false
                timerState.isPaused = false
                print("⚠️ Timer completed while app was closed - resetting")
                return
            }
            
            sessionStartTime = Date()
            accumulatedPausedTime = 0
            
            print("✅ Restored from Shared State - Phase: \(timerState.currentPhase), Remaining: \(Int(timerState.timeRemaining))s, isPaused: \(timerState.isPaused)")
            
            // Recreate Live Activity from shared state
            if sharedState.isRunning {
                startLiveActivity()
            }
            return
        }
        
        print("⚠️ No state to restore from")
    }
    
    func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚠️ Live Activities not enabled")
            return
        }
        
        // 🔥 If activity already exists, just update it
        if currentActivity != nil {
            print("⚠️ Live Activity already exists, updating instead")
            updateLiveActivity()
            return
        }
        
        // Clean up any orphaned activities
        Task {
            for activity in Activity<TimerAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
                print("🧹 Cleaned up orphaned Live Activity")
            }
            
            // Now create new one
            await MainActor.run {
                createNewLiveActivity()
            }
        }
    }
    
    private func createNewLiveActivity() {
        let attributes = TimerAttributes(
            workDuration: timerState.workDuration,
            breakDuration: timerState.shortBreakDuration,
            projectName: projectManager.currentProject?.displayName
        )
        
        let contentState = TimerAttributes.ContentState(
            phase: timerState.currentPhase,
            timeRemaining: timerState.timeRemaining,
            isRunning: timerState.isRunning,
            isPaused: timerState.isPaused,
            completedSessions: timerState.completedWorkSessions,
            lastUpdateTime: Date()
        )
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil)
            )
            print("✅ Live Activity started - Phase: \(timerState.currentPhase)")
            saveToSharedState()
        } catch {
            print("❌ Failed to start Live Activity: \(error)")
        }
    }
    
    func updateLiveActivity() {
        guard let activity = currentActivity else {
            print("⚠️ No active Live Activity to update")
            return
        }
        
        let contentState = TimerAttributes.ContentState(
            phase: timerState.currentPhase,
            timeRemaining: timerState.timeRemaining,
            isRunning: timerState.isRunning,
            isPaused: timerState.isPaused,
            completedSessions: timerState.completedWorkSessions,
            lastUpdateTime: Date()
        )
        
        Task {
            await activity.update(.init(state: contentState, staleDate: nil))
            print("✅ Live Activity updated - Phase: \(timerState.currentPhase), Time: \(Int(timerState.timeRemaining))s, isPaused: \(timerState.isPaused)")
        }
        
        // 🔥 Also save to shared state
        saveToSharedState()
    }
    
    func endLiveActivity() {
        guard let activity = currentActivity else { return }
        
        let activityToEnd = activity
        currentActivity = nil
        
        Task {
            await activityToEnd.end(nil, dismissalPolicy: .immediate)
            print("✅ Live Activity ended")
        }
    }
    
    func setupWidgetIntentObservers() {
        NotificationCenter.default.addObserver(
            forName: .toggleTimerFromWidget,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📲 App received toggle from widget, syncing state")
            self?.restoreFromLiveActivityOrShared()
        }
        
        NotificationCenter.default.addObserver(
            forName: .skipTimerFromWidget,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("📲 App received skip from widget, syncing state")
            self?.restoreFromLiveActivityOrShared()
        }
    }
    #endif
    
    // MARK: - Audio
    
    private func playBeep() {
        #if os(macOS)
        NSSound(named: "Glass")?.play()
        #elseif os(iOS)
        AudioServicesPlaySystemSound(1054)
        #endif
    }
    
    // MARK: - Computed Properties
    
    var displayTime: String {
        let minutes = Int(timerState.timeRemaining) / 60
        let seconds = Int(timerState.timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var phaseTitle: String {
        switch timerState.currentPhase {
        case .warmup:
            return "Starting Soon"
        case .work:
            return "Work"
        case .shortBreak:
            return "Short Break"
        case .longBreak:
            return "Long Break"
        }
    }
    
    var buttonTitle: String {
        if timerState.isPaused {
            return "Resume"
        } else if timerState.isRunning {
            return "Pause"
        } else {
            return "Start"
        }
    }
}
