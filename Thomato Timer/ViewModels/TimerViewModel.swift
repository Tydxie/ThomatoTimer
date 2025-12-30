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
    var timerState = TimerState()
    @Published var projectManager = ProjectManager.shared
    
    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var sessionStartTime: Date?
    private var accumulatedPausedTime: TimeInterval = 0
    private var lastPauseTime: Date?
    
    // For iOS background handling
    private var backgroundTime: Date?
    
    // 🔥 NEW: Prevent restore loops
    private var isUpdatingLiveActivity = false
    private var isPausingFromApp = false
    
    // 🔥 NEW: Debounce foreground transitions
    private var lastForegroundTime: Date?
    private let foregroundDebounceInterval: TimeInterval = 2.0
    
    // Music managers
    var spotifyManager: SpotifyManager?
    var appleMusicManager: AppleMusicManager?
    var selectedService: MusicService = .none
    
    // 🔥 Live Activity
    #if os(iOS)
    private var currentActivity: Activity<TimerAttributes>?
    #endif
    
    init() {
        timerState.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }
    
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
        print("🎯 toggleTimer() called - Current state: isRunning=\(timerState.isRunning), isPaused=\(timerState.isPaused)")
        
        if timerState.isPaused {
            print("  → Branch: RESUME")
            // Resume
            CrashLogger.shared.logEvent("Resuming timer - Phase: \(timerState.currentPhase)")
            if let pauseStart = lastPauseTime {
                accumulatedPausedTime += Date().timeIntervalSince(pauseStart)
                lastPauseTime = nil
            }
            timerState.resume()
            startCountdown()
            
            // 🔥 Resume music playback (continues from where it was paused)
            switch selectedService {
            case .spotify:
                if let spotify = spotifyManager, spotify.isAuthenticated {
                    Task {
                        await spotify.resumePlayback()
                    }
                }
            case .appleMusic:
                if let appleMusic = appleMusicManager, appleMusic.isAuthorized {
                    appleMusic.play()
                }
            case .none:
                break
            }
            
            #if os(iOS)
            timerState.saveToUserDefaults()
            scheduleTimerCompletionNotification()
            Task {
                await MainActor.run {
                    self.updateLiveActivity()
                }
            }
            print("▶️ RESUMED - isPaused: \(timerState.isPaused), isRunning: \(timerState.isRunning)")
            #endif
        } else if timerState.isRunning {
            print("  → Branch: PAUSE")
            // Pause
            CrashLogger.shared.logEvent("Pausing timer - Phase: \(timerState.currentPhase), TimeRemaining: \(Int(timerState.timeRemaining))s")
            
            #if os(iOS)
            isPausingFromApp = true
            #endif
            
            lastPauseTime = Date()
            timerState.pause()
            stopCountdown()
            pauseMusic()
            
            #if os(iOS)
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            timerState.saveToUserDefaults()
            Task {
                await MainActor.run {
                    self.updateLiveActivity()
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    self.isPausingFromApp = false
                }
            }
            print("🔴 PAUSED - isPaused: \(timerState.isPaused), isRunning: \(timerState.isRunning)")
            #endif
        } else {
            print("  → Branch: START")
            // Start
            CrashLogger.shared.logEvent("Starting timer - Phase: \(timerState.currentPhase)")
            
            if timerState.currentPhase == .warmup {
                if timerState.warmupDuration > 0 {
                    startWarmup()
                } else {
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
        logElapsedTime()
        
        timerState.startNextPhase()
        
        CrashLogger.shared.logEvent("🔄 SKIPPED TO - Phase: \(timerState.currentPhase), Sessions: \(timerState.completedWorkSessions)")
        
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
            Task {
                await MainActor.run {
                    self.updateLiveActivity()
                }
            }
            #endif
        }
    }
    
    func reset() {
        CrashLogger.shared.logEvent("Resetting timer")
        if timerState.isRunning || timerState.isPaused {
            logElapsedTime()
        }
        
        stopCountdown()
        timerState.reset()
        
        sessionStartTime = nil
        accumulatedPausedTime = 0
        lastPauseTime = nil
        backgroundTime = nil
        
        pauseMusic()
        
        #if os(iOS)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        TimerState.clearSavedState()
        SharedTimerState.clear()
        Task {
            await MainActor.run {
                self.endLiveActivity()
            }
        }
        #endif
    }
    
    // MARK: - iOS Background Handling
    
    private func scheduleTimerCompletionNotification() {
        #if os(iOS)
        guard timerState.isRunning else { return }
        
        guard timerState.timeRemaining > 0 else {
            print("⚠️ Cannot schedule notification - timeRemaining is \(timerState.timeRemaining)")
            return
        }
        
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
        
        // 🔥 DEBOUNCE: Ignore rapid successive calls
        let now = Date()
        if let lastCall = lastForegroundTime, now.timeIntervalSince(lastCall) < foregroundDebounceInterval {
            print("⏸️ Ignoring foreground transition - called \(now.timeIntervalSince(lastCall))s ago (debouncing)")
            return
        }
        lastForegroundTime = now
        
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // Only restore if we actually have background time (means we were backgrounded)
        guard let bgTime = backgroundTime else {
            print("⚠️ No backgroundTime - was not backgrounded, skipping restore")
            return
        }
        
        // Clear it immediately to prevent double-processing
        backgroundTime = nil
        
        let timeInBackground = Date().timeIntervalSince(bgTime)
        CrashLogger.shared.logEvent("📊 Was in background for: \(Int(timeInBackground))s")
        
        // Restore state from Live Activity
        restoreFromLiveActivityOrShared()
        
        // 🔥 FIX: Check if phases completed during background
        // The restore already handles this, so just resume if needed
        if timerState.timeRemaining > 0 && timerState.isRunning && !timerState.isPaused {
            CrashLogger.shared.logEvent("▶️ Resuming countdown after background")
            startCountdown()
            playMusicForCurrentPhase()
            scheduleTimerCompletionNotification()
        } else if timerState.isRunning && timerState.timeRemaining > 0 {
            // Timer is running but we need to start countdown
            CrashLogger.shared.logEvent("▶️ Restarting countdown after background")
            startCountdown()
            playMusicForCurrentPhase()
            scheduleTimerCompletionNotification()
        }
        #endif
    }
    
    // MARK: - State Restoration
    
    func restoreStateIfNeeded() {
        #if os(iOS)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        CrashLogger.shared.logEvent("🔔 Cancelled all old notifications during restore")
        
        let hasLiveActivity = Activity<TimerAttributes>.activities.first != nil
        
        restoreFromLiveActivityOrShared()
        
        if hasLiveActivity && timerState.isRunning && !timerState.isPaused && timerState.timeRemaining > 0 {
            print("✅ Live Activity exists - auto-resuming timer")
            startCountdown()
            playMusicForCurrentPhase()
            scheduleTimerCompletionNotification()
        } else {
            print("⚠️ No Live Activity or timer not running - NOT auto-starting")
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
        print("▶️ startCountdown() called")
        
        // 🔥 ALWAYS cancel any existing timer first
        timer?.cancel()
        timer = nil
        
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
        print("▶️ New timer created")
    }
    
    private func stopCountdown() {
        print("🛑 stopCountdown() called - timer=\(timer != nil ? "EXISTS" : "nil")")
        timer?.cancel()
        timer = nil
        print("🛑 stopCountdown() completed - timer=\(timer != nil ? "EXISTS" : "nil")")
    }
    
    private func tick() {
        print("⏱️ tick() fired - isRunning=\(timerState.isRunning), isPaused=\(timerState.isPaused)")
        
        guard timerState.isRunning, !timerState.isPaused else {
            print("⏹️ tick() stopped - isRunning=\(timerState.isRunning), isPaused=\(timerState.isPaused)")
            stopCountdown()
            return
        }
        
        guard timerState.timeRemaining > 0 else {
            handleTimerComplete()
            return
        }
        
        timerState.timeRemaining -= 1
        
        #if os(iOS)
        if Int(timerState.timeRemaining) % 10 == 0 {
            print("⏰ tick() - 10s interval update")
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
        guard !isUpdatingLiveActivity else {
            print("⏸️ Skipping restore - we're currently updating the Live Activity")
            return
        }
        
        guard !isPausingFromApp else {
            print("⏸️ Skipping restore - we just paused from the app")
            return
        }
        
        if let activity = Activity<TimerAttributes>.activities.first {
            let state = activity.content.state
            let timeSinceUpdate = Date().timeIntervalSince(state.lastUpdateTime)
            
            print("🔄 Restoring from Live Activity - Phase: \(state.phase), Time since update: \(Int(timeSinceUpdate))s")
            
            var actualRemaining = state.timeRemaining
            if state.isRunning && !state.isPaused {
                actualRemaining -= timeSinceUpdate
            }
            
            timerState.currentPhase = state.phase
            timerState.completedWorkSessions = state.completedSessions
            
            // 🔥 FIX: Check if timer completed while backgrounded
            // If time ran out, phase completed (can't happen if paused)
            if actualRemaining <= 0 {
                print("⏰ Timer completed during background - transitioning to next phase")
                
                // Log the completed session
                let completedPhase = state.phase
                timerState.currentPhase = completedPhase
                timerState.timeRemaining = 0
                logElapsedTime()
                
                // Transition to next phase
                timerState.startNextPhase()
                
                print("✅ Auto-transitioned: \(completedPhase) → \(timerState.currentPhase)")
                CrashLogger.shared.logEvent("Auto-transitioned: \(completedPhase) → \(timerState.currentPhase)")
                
                // Keep running
                timerState.isRunning = true
                timerState.isPaused = false
                
                sessionStartTime = Date()
                accumulatedPausedTime = 0
                
                // 🔥 CRITICAL: Save and update so foreground transition can resume
                timerState.saveToUserDefaults()
                saveToSharedState()
                updateLiveActivity()
                
                currentActivity = activity
                return
            }
            
            timerState.timeRemaining = max(0, actualRemaining)
            timerState.isPaused = state.isPaused
            timerState.isRunning = state.isRunning
            
            if timerState.timeRemaining <= 0 {
                timerState.isRunning = false
                timerState.isPaused = false
                print("⚠️ Timer at 0 but not running - resetting")
                currentActivity = activity
                return
            }
            
            sessionStartTime = Date()
            accumulatedPausedTime = 0
            
            print("✅ Restored from Live Activity - Phase: \(timerState.currentPhase), Remaining: \(Int(timerState.timeRemaining))s, isPaused: \(timerState.isPaused)")
            
            currentActivity = activity
            return
        }
        
        if let sharedState = SharedTimerState.load() {
            let timeSinceUpdate = Date().timeIntervalSince(sharedState.lastUpdateTime)
            
            print("🔄 Restoring from Shared State - Phase: \(sharedState.phase), Time since update: \(Int(timeSinceUpdate))s")
            
            var actualRemaining = sharedState.timeRemaining
            if sharedState.isRunning && !sharedState.isPaused {
                actualRemaining -= timeSinceUpdate
            }
            
            timerState.currentPhase = sharedState.phase
            timerState.completedWorkSessions = sharedState.completedSessions
            timerState.workDuration = sharedState.workDuration
            timerState.shortBreakDuration = sharedState.shortBreakDuration
            timerState.longBreakDuration = sharedState.longBreakDuration
            timerState.sessionsUntilLongBreak = sharedState.sessionsUntilLongBreak
            
            // 🔥 FIX: Check if timer completed while backgrounded
            // If time ran out, phase completed (can't happen if paused)
            if actualRemaining <= 0 {
                print("⏰ Timer completed during background - transitioning to next phase")
                
                // Log the completed session
                let completedPhase = sharedState.phase
                timerState.currentPhase = completedPhase
                timerState.timeRemaining = 0
                logElapsedTime()
                
                // Transition to next phase
                timerState.startNextPhase()
                
                print("✅ Auto-transitioned: \(completedPhase) → \(timerState.currentPhase)")
                CrashLogger.shared.logEvent("Auto-transitioned: \(completedPhase) → \(timerState.currentPhase)")
                
                // Keep running
                timerState.isRunning = true
                timerState.isPaused = false
                
                sessionStartTime = Date()
                accumulatedPausedTime = 0
                
                if sharedState.isRunning {
                    startLiveActivity()
                }
                return
            }
            
            timerState.timeRemaining = max(0, actualRemaining)
            timerState.isPaused = sharedState.isPaused
            timerState.isRunning = sharedState.isRunning
            
            if timerState.timeRemaining <= 0 {
                timerState.isRunning = false
                timerState.isPaused = false
                print("⚠️ Timer at 0 but not running - resetting")
                return
            }
            
            sessionStartTime = Date()
            accumulatedPausedTime = 0
            
            print("✅ Restored from Shared State - Phase: \(timerState.currentPhase), Remaining: \(Int(timerState.timeRemaining))s, isPaused: \(timerState.isPaused)")
            
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
        
        if currentActivity != nil {
            print("⚠️ Live Activity already exists, updating instead")
            updateLiveActivity()
            return
        }
        
        Task {
            for activity in Activity<TimerAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
                print("🧹 Cleaned up orphaned Live Activity")
            }
            
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
        
        print("🔄 updateLiveActivity() called")
        print("   📊 App State: isRunning=\(timerState.isRunning), isPaused=\(timerState.isPaused), time=\(Int(timerState.timeRemaining))s")
        
        isUpdatingLiveActivity = true
        
        let contentState = TimerAttributes.ContentState(
            phase: timerState.currentPhase,
            timeRemaining: timerState.timeRemaining,
            isRunning: timerState.isRunning,
            isPaused: timerState.isPaused,
            completedSessions: timerState.completedWorkSessions,
            lastUpdateTime: Date()
        )
        
        print("   📤 Sending to Live Activity: isRunning=\(contentState.isRunning), isPaused=\(contentState.isPaused)")
        
        Task {
            await activity.update(.init(state: contentState, staleDate: nil))
            await MainActor.run {
                self.saveToSharedState()
            }
            print("   ✅ Live Activity updated successfully")
            
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            if let currentActivity = Activity<TimerAttributes>.activities.first {
                let state = currentActivity.content.state
                print("   🔍 Verified Live Activity State: isRunning=\(state.isRunning), isPaused=\(state.isPaused)")
            }
            
            await MainActor.run {
                self.isUpdatingLiveActivity = false
            }
        }
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
        print("⚠️ Widget intent observers DISABLED to prevent pause bug")
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
