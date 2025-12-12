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
        timerState.startWarmup()
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        startCountdown()
        playMusicForCurrentPhase()
        
        #if os(iOS)
        scheduleTimerCompletionNotification()
        #endif
    }
    
    func toggleTimer() {
        if timerState.isPaused {
            // Resume
            if let pauseStart = lastPauseTime {
                accumulatedPausedTime += Date().timeIntervalSince(pauseStart)
                lastPauseTime = nil
            }
            timerState.resume()
            startCountdown()
            playMusicForCurrentPhase()
            
            #if os(iOS)
            scheduleTimerCompletionNotification()
            #endif
        } else if timerState.isRunning {
            // Pause
            lastPauseTime = Date()
            timerState.pause()
            stopCountdown()
            pauseMusic()
            
            #if os(iOS)
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            #endif
        } else {
            // Start (warmup or first session)
            if timerState.currentPhase == .warmup {
                startWarmup()
            } else {
                startNextSession()
            }
        }
    }
    
    func skipToNext() {
        stopCountdown()
        playBeep()
        
        // Log elapsed time before skipping
        logElapsedTime()
        
        timerState.startNextPhase()
        
        // Reset session tracking for next phase
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        lastPauseTime = nil
        
        if timerState.currentPhase != .warmup {
            startCountdown()
            playMusicForCurrentPhase()
            
            #if os(iOS)
            scheduleTimerCompletionNotification()
            #endif
        }
    }
    
    func reset() {
        // Log elapsed time before resetting (if timer was active)
        if timerState.isRunning || timerState.isPaused {
            logElapsedTime()
        }
        
        // Stop timer first
        stopCountdown()
        
        // Reset state
        timerState.reset()
        sessionStartTime = nil
        accumulatedPausedTime = 0
        lastPauseTime = nil
        backgroundTime = nil
        
        // Stop music (safely)
        pauseMusic()
        
        #if os(iOS)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
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
            } else {
                print("✅ Notification scheduled for \(self.timerState.timeRemaining)s")
            }
        }
        #endif
    }
    
    func handleBackgroundTransition() {
        #if os(iOS)
        guard timerState.isRunning else { return }
        backgroundTime = Date()
        
        // Schedule notification for timer completion
        scheduleTimerCompletionNotification()
        
        stopCountdown()
        print("📱 App backgrounded - timer will continue tracking")
        #endif
    }
    
    func handleForegroundTransition() {
        #if os(iOS)
        // Cancel pending notifications since app is active
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        guard let bgTime = backgroundTime else {
            return
        }
        
        // Calculate time spent in background
        let timeInBackground = Date().timeIntervalSince(bgTime)
        backgroundTime = nil
        
        print("📱 App foregrounded - was in background for \(Int(timeInBackground))s")
        
        guard timerState.isRunning else { return }
        
        // Subtract background time from remaining
        var remainingTime = timerState.timeRemaining - timeInBackground
        
        // Handle multiple phase completions if user was away for a long time
        while remainingTime <= 0 && timerState.isRunning {
            print("⏰ Timer completed while in background")
            
            let completedPhase = timerState.currentPhase
            
            // Log elapsed time for the completed phase
            logElapsedTime()
            
            // Move to next phase
            timerState.startNextPhase()
            
            // Reset session tracking
            sessionStartTime = Date()
            accumulatedPausedTime = 0
            
            // Add remaining negative time to next phase
            remainingTime += timerState.timeRemaining
            
            // Send notification for completed phase
            NotificationManager.shared.sendPhaseCompleteNotification(
                phase: completedPhase,
                nextPhase: timerState.currentPhase
            )
        }
        
        // Update final remaining time
        timerState.timeRemaining = max(0, remainingTime)
        
        if timerState.timeRemaining > 0 && timerState.isRunning {
            // Resume countdown
            startCountdown()
            playMusicForCurrentPhase()
        }
        #endif
    }
    
    // MARK: - Project Switching
    
    func switchProject(to project: Project?) {
        // Log elapsed time to current project before switching
        if timerState.isRunning || timerState.isPaused {
            logElapsedTime()
        }
        
        // Pause timer if running
        if timerState.isRunning {
            lastPauseTime = Date()
            timerState.pause()
            stopCountdown()
            pauseMusic()
        }
        
        // Switch project
        projectManager.selectProject(project)
        print("🔄 Switched to project: \(project?.displayName ?? "Freestyle")")
        
        // Reset session tracking for new project
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        if timerState.isPaused {
            lastPauseTime = Date()
        }
    }
    
    // MARK: - Private Timer Logic
    
    private func startCountdown() {
        // Cancel any existing timer first
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
        // Guard against timer firing after reset/stop
        guard timerState.isRunning, !timerState.isPaused else {
            stopCountdown()
            return
        }
        
        guard timerState.timeRemaining > 0 else {
            handleTimerComplete()
            return
        }
        
        timerState.timeRemaining -= 1
    }
    
    private func handleTimerComplete() {
        stopCountdown()
        playBeep()
        
        let completedPhase = timerState.currentPhase
        
        // Log elapsed time
        logElapsedTime()
        
        timerState.startNextPhase()
        
        // Reset session tracking for next phase
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        lastPauseTime = nil
        
        NotificationManager.shared.sendPhaseCompleteNotification(
            phase: completedPhase,
            nextPhase: timerState.currentPhase
        )
        
        if timerState.currentPhase != .warmup || timerState.isRunning {
            startCountdown()
            playMusicForCurrentPhase()
            
            #if os(iOS)
            scheduleTimerCompletionNotification()
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
        scheduleTimerCompletionNotification()
        #endif
    }
    
    // MARK: - Session Logging
    
    /// Logs elapsed time for the current phase to statistics
    private func logElapsedTime() {
        let currentPhase = timerState.currentPhase
        
        // Don't log warmup
        guard currentPhase != .warmup else { return }
        
        // Need a valid session start time
        guard let startTime = sessionStartTime else {
            print("⚠️ No session start time, cannot log elapsed time")
            return
        }
        
        // Account for current pause if paused
        var totalPausedTime = accumulatedPausedTime
        if timerState.isPaused, let pauseStart = lastPauseTime {
            totalPausedTime += Date().timeIntervalSince(pauseStart)
        }
        
        let elapsedTime = Date().timeIntervalSince(startTime) - totalPausedTime
        let actualDurationMinutes = Int(round(elapsedTime / 60.0))
        
        // Only log if at least 1 minute
        guard actualDurationMinutes >= 1 else {
            print("⏱️ Less than 1 minute elapsed (\(Int(elapsedTime))s), not logging")
            return
        }
        
        let currentProjectId = projectManager.currentProjectId
        let projectName = projectManager.currentProject?.displayName ?? "Freestyle"
        
        print("📊 Logging \(actualDurationMinutes) min of \(currentPhase) to \(projectName)")
        
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
        // Handle different music services
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
        guard let spotify = spotifyManager, spotify.isAuthenticated else { return }
        
        Task {
            switch timerState.currentPhase {
            case .warmup, .shortBreak, .longBreak:
                if let playlistId = spotify.selectedBreakPlaylistId {
                    print("🎵 Playing Spotify warmup/break playlist")
                    await spotify.playPlaylist(playlistId: playlistId)
                } else {
                    await spotify.pausePlayback()
                }
            case .work:
                if let playlistId = spotify.selectedWorkPlaylistId {
                    print("🎵 Playing Spotify work playlist")
                    await spotify.playPlaylist(playlistId: playlistId)
                }
            }
        }
    }
    
    private func playAppleMusic() {
        guard let appleMusic = appleMusicManager, appleMusic.isAuthorized else { return }
        
        Task {
            switch timerState.currentPhase {
            case .warmup, .shortBreak, .longBreak:
                if let playlistId = appleMusic.selectedBreakPlaylistId {
                    print("🎵 Playing Apple Music warmup/break playlist")
                    await appleMusic.playPlaylist(id: playlistId)
                } else {
                    appleMusic.pause()
                }
            case .work:
                if let playlistId = appleMusic.selectedWorkPlaylistId {
                    print("🎵 Playing Apple Music work playlist")
                    await appleMusic.playPlaylist(id: playlistId)
                }
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
