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
                    #endif
                }
            } else if timerState.currentPhase == .work && timerState.completedWorkSessions == 0 {
                // 🔥 FIX: Starting first work session (warmup was disabled)
                // Don't call startNextSession() - just start the timer
                timerState.isRunning = true
                timerState.isPaused = false
                sessionStartTime = Date()
                accumulatedPausedTime = 0
                startCountdown()
                playMusicForCurrentPhase()
                #if os(iOS)
                timerState.saveToUserDefaults()
                scheduleTimerCompletionNotification()
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
        #endif
    }
    
    // MARK: - iOS Background Handling
    
    /// Schedule notification for when timer completes
    private func scheduleTimerCompletionNotification() {
        #if os(iOS)
        guard timerState.isRunning else { return }
        
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
        
        guard let bgTime = backgroundTime else {
            CrashLogger.shared.logEvent("⚠️ No backgroundTime recorded - either never backgrounded or state lost")
            return
        }
        
        backgroundTime = nil
        
        let timeInBackground = Date().timeIntervalSince(bgTime)
        
        let oldTimeRemaining = timerState.timeRemaining
        let wasRunning = timerState.isRunning
        let wasPaused = timerState.isPaused
        
        CrashLogger.shared.logEvent("📊 FOREGROUND STATE - Phase: \(timerState.currentPhase), isRunning: \(wasRunning), isPaused: \(wasPaused)")
        CrashLogger.shared.logEvent("📊 TIME CALC - Was in BG: \(Int(timeInBackground))s, TimeRemaining BEFORE: \(Int(oldTimeRemaining))s")
        
        print("📱 App foregrounded - was in background for \(Int(timeInBackground))s")
        
        guard timerState.isRunning else {
            CrashLogger.shared.logEvent("⏹️ Timer not running, not adjusting time")
            return
        }
        
        var remainingTime = timerState.timeRemaining - timeInBackground
        
        CrashLogger.shared.logEvent("🧮 MATH - \(Int(oldTimeRemaining))s - \(Int(timeInBackground))s = \(Int(remainingTime))s")
        
        var completionCount = 0
        while remainingTime <= 0 && timerState.isRunning {
            completionCount += 1
            print("⏰ Timer completed while in background (completion #\(completionCount))")
            CrashLogger.shared.logEvent("⏭️ Timer completed in background - Phase: \(timerState.currentPhase)")
            
            let completedPhase = timerState.currentPhase
            
            logElapsedTime()
            
            timerState.startNextPhase()
            
            sessionStartTime = Date()
            accumulatedPausedTime = 0
            
            remainingTime += timerState.timeRemaining
            
            NotificationManager.shared.sendPhaseCompleteNotification(
                phase: completedPhase,
                nextPhase: timerState.currentPhase
            )
        }
        
        if completionCount > 0 {
            CrashLogger.shared.logEvent("🔄 Processed \(completionCount) phase completions")
        }
        
        timerState.timeRemaining = max(0, remainingTime)
        CrashLogger.shared.logEvent("✅ FINAL - Phase: \(timerState.currentPhase), TimeRemaining: \(Int(timerState.timeRemaining))s")
        
        if timerState.timeRemaining > 0 && timerState.isRunning {
            CrashLogger.shared.logEvent("▶️ Resuming countdown with startCountdown()")
            startCountdown()
            CrashLogger.shared.logEvent("✅ Countdown resumed")
        } else {
            CrashLogger.shared.logEvent("⏹️ NOT resuming - timeRemaining: \(Int(timerState.timeRemaining))s, isRunning: \(timerState.isRunning)")
        }
        #endif
    }
    
    // MARK: - State Restoration
    
    func restoreStateIfNeeded() {
        #if os(iOS)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        CrashLogger.shared.logEvent("🔔 Cancelled all old notifications during restore")
        
        let timestamp = Date()
        CrashLogger.shared.logEvent("🔍 RESTORE CHECK at \(timestamp)")
        
        guard let saved = TimerState.loadFromUserDefaults() else {
            CrashLogger.shared.logEvent("❌ NO SAVED STATE - Nothing to restore")
            return
        }
        
        CrashLogger.shared.logEvent("✅ FOUND SAVED STATE - Phase: \(saved.state.currentPhase), isRunning: \(saved.state.isRunning), isPaused: \(saved.state.isPaused), sessions: \(saved.state.completedWorkSessions), timeRemaining: \(Int(saved.state.timeRemaining))s")
        
        guard saved.state.isRunning else {
            CrashLogger.shared.logEvent("⏹️ RESTORE SKIPPED - Timer was NOT running")
            TimerState.clearSavedState()
            return
        }
        
        let timeSinceSave = Date().timeIntervalSince(saved.timestamp)
        CrashLogger.shared.logEvent("🔄 RESTORING STATE - Phase: \(saved.state.currentPhase), Was saved \(Int(timeSinceSave))s ago, Had \(Int(saved.state.timeRemaining))s remaining")
        
        CrashLogger.shared.logEvent("BEFORE RESTORE - Phase: \(timerState.currentPhase), isRunning: \(timerState.isRunning), sessions: \(timerState.completedWorkSessions)")
        
        timerState = saved.state
        
        CrashLogger.shared.logEvent("AFTER RESTORE - Phase: \(timerState.currentPhase), isRunning: \(timerState.isRunning), sessions: \(timerState.completedWorkSessions)")
        
        var newTimeRemaining = saved.state.timeRemaining - timeSinceSave
        
        CrashLogger.shared.logEvent("🧮 MATH - Original: \(Int(saved.state.timeRemaining))s - Elapsed: \(Int(timeSinceSave))s = New: \(Int(newTimeRemaining))s")
        
        var phaseCompletions = 0
        while newTimeRemaining <= 0 && timerState.isRunning {
            phaseCompletions += 1
            CrashLogger.shared.logEvent("⏭️ Phase completed while app was killed - Phase: \(timerState.currentPhase)")
            timerState.startNextPhase()
            newTimeRemaining += timerState.timeRemaining
        }
        
        if phaseCompletions > 0 {
            CrashLogger.shared.logEvent("🔄 Processed \(phaseCompletions) phase completions during restoration")
        }
        
        timerState.timeRemaining = max(0, newTimeRemaining)
        CrashLogger.shared.logEvent("✅ RESTORED - New phase: \(timerState.currentPhase), TimeRemaining: \(Int(timerState.timeRemaining))s, Sessions: \(timerState.completedWorkSessions)")
        
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        startCountdown()
        playMusicForCurrentPhase()
        
        scheduleTimerCompletionNotification()
        CrashLogger.shared.logEvent("🔔 Scheduled notification for restored phase: \(timerState.currentPhase)")
        
        TimerState.clearSavedState()
        CrashLogger.shared.logEvent("🗑️ Saved state cleared")
        
        CrashLogger.shared.logEvent("FINAL STATE - Phase: \(timerState.currentPhase), isRunning: \(timerState.isRunning), timeRemaining: \(Int(timerState.timeRemaining))s, sessions: \(timerState.completedWorkSessions)")
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
        if Int(timerState.timeRemaining) % 30 == 0 {
            timerState.saveToUserDefaults()
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
                // 🔥 FIX: No work playlist selected - pause music from break
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
                // 🔥 FIX: No work playlist selected - pause music from break
                CrashLogger.shared.logEvent("🎵 APPLE MUSIC - No work playlist, pausing")
                appleMusic.pause()
            }
        }
    }
    
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
