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
#endif

class TimerViewModel: ObservableObject {
    @Published var timerState = TimerState()
    @Published var projectManager = ProjectManager.shared
    
    private var timer: AnyCancellable?
    private var sessionStartTime: Date?
    private var accumulatedPausedTime: TimeInterval = 0
    private var lastPauseTime: Date?
    
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
        } else if timerState.isRunning {
            // Pause
            lastPauseTime = Date()
            timerState.pause()
            stopCountdown()
            // Pause music
            Task {
                await spotifyManager?.pausePlayback()
                appleMusicManager?.pause()
            }
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
        
        // If skipping a work/break session, log the actual time worked so far
        let currentPhase = timerState.currentPhase
        if currentPhase != .warmup {
            var actualDurationMinutes: Int
            if let startTime = sessionStartTime {
                let elapsedTime = Date().timeIntervalSince(startTime) - accumulatedPausedTime
                actualDurationMinutes = max(1, Int(round(elapsedTime / 60.0)))
                print("⏭️ Skipped - logging actual time worked: \(actualDurationMinutes) min")
                
                let currentProjectId = projectManager.currentProjectId
                
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
        }
        
        timerState.startNextPhase()
        
        // Reset session tracking for next phase
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        lastPauseTime = nil
        
        if timerState.currentPhase != .warmup {
            startCountdown()
            playMusicForCurrentPhase()
        }
    }
    
    func reset() {
        stopCountdown()
        timerState.reset()
        sessionStartTime = nil
        accumulatedPausedTime = 0
        lastPauseTime = nil
        
        // Stop music
        Task {
            await spotifyManager?.pausePlayback()
            appleMusicManager?.pause()
        }
    }
    
    // MARK: - Project Switching
    
    func switchProject(to project: Project?) {
        // Pause timer if running
        if timerState.isRunning {
            lastPauseTime = Date()
            timerState.pause()
            stopCountdown()
            
            // Pause music
            Task {
                await spotifyManager?.pausePlayback()
                appleMusicManager?.pause()
            }
        }
        
        // Switch project
        projectManager.selectProject(project)
        print("🔄 Switched to project: \(project?.displayName ?? "Freestyle")")
    }
    
    // MARK: - Private Timer Logic
    
    private func startCountdown() {
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
        
        // Calculate actual elapsed time (not configured duration)
        var actualDurationMinutes: Int
        if let startTime = sessionStartTime {
            let elapsedTime = Date().timeIntervalSince(startTime) - accumulatedPausedTime
            actualDurationMinutes = max(1, Int(round(elapsedTime / 60.0)))
            print("⏱️ Actual time worked: \(actualDurationMinutes) min (elapsed: \(Int(elapsedTime))s, paused: \(Int(accumulatedPausedTime))s)")
        } else {
            // Fallback to configured duration if no start time tracked
            actualDurationMinutes = Int(currentPhaseDuration / 60)
            print("⚠️ No session start time, using configured duration: \(actualDurationMinutes) min")
        }
        
        let currentProjectId = projectManager.currentProjectId
        
        // Log completed session to statistics
        switch completedPhase {
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
            break // Don't log warmup
        }
        
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
    }
    
    // MARK: - Music Integration
    
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
            case .warmup:
                if let trackId = spotify.selectedWarmupTrackId {
                    print("🎵 Playing Spotify warmup track")
                    await spotify.playTrack(trackId: trackId)
                }
            case .work:
                if let playlistId = spotify.selectedWorkPlaylistId {
                    print("🎵 Playing Spotify work playlist")
                    await spotify.playPlaylist(playlistId: playlistId)
                }
            case .shortBreak, .longBreak:
                if let playlistId = spotify.selectedBreakPlaylistId {
                    print("🎵 Playing Spotify break playlist")
                    await spotify.playPlaylist(playlistId: playlistId)
                } else {
                    await spotify.pausePlayback()
                }
            }
        }
    }
    
    private func playAppleMusic() {
        guard let appleMusic = appleMusicManager, appleMusic.isAuthorized else { return }
        
        Task {
            switch timerState.currentPhase {
            case .warmup:
                if let songId = appleMusic.selectedWarmupSongId {
                    print("🎵 Playing Apple Music warmup song")
                    await appleMusic.playSong(id: songId)
                }
            case .work:
                if let playlistId = appleMusic.selectedWorkPlaylistId {
                    print("🎵 Playing Apple Music work playlist")
                    await appleMusic.playPlaylist(id: playlistId)
                }
            case .shortBreak, .longBreak:
                if let playlistId = appleMusic.selectedBreakPlaylistId {
                    print("🎵 Playing Apple Music break playlist")
                    await appleMusic.playPlaylist(id: playlistId)
                } else {
                    appleMusic.pause()
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
