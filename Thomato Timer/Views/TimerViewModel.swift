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
    
    private var timer: AnyCancellable?
    private var startTime: Date?
    
    // ⭐ SPOTIFY INTEGRATION
    var spotifyManager: SpotifyManager?
    
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
        startCountdown()
        
        // ⭐ PLAY WARMUP SONG
        playMusicForCurrentPhase()
    }
    
    func toggleTimer() {
        if timerState.isPaused {
            // Resume
            timerState.resume()
            startCountdown()
            // ⭐ RESUME MUSIC
            playMusicForCurrentPhase()
        } else if timerState.isRunning {
            // Pause
            timerState.pause()
            stopCountdown()
            // ⭐ PAUSE MUSIC
            Task {
                await spotifyManager?.pausePlayback()
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
        timerState.startNextPhase()
        
        if timerState.currentPhase != .warmup {
            startCountdown()
            // ⭐ PLAY MUSIC FOR NEW PHASE
            playMusicForCurrentPhase()
        }
    }
    
    func reset() {
        stopCountdown()
        timerState.reset()
        
        // ⭐ STOP MUSIC
        Task {
            await spotifyManager?.pausePlayback()
        }
    }
    
    // MARK: - Private Timer Logic
    
    private func startCountdown() {
        startTime = Date()
        
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
        
        // Auto-advance to next phase
        timerState.startNextPhase()
        
        // If not reset (still has phases to go), start next countdown
        if timerState.currentPhase != .warmup || timerState.isRunning {
            startCountdown()
            // ⭐ PLAY MUSIC FOR NEW PHASE
            playMusicForCurrentPhase()
        }
    }
    
    private func startNextSession() {
        timerState.startNextPhase()
        timerState.isRunning = true
        timerState.isPaused = false
        startCountdown()
        
        // ⭐ PLAY MUSIC FOR NEW PHASE
        playMusicForCurrentPhase()
    }
    
    // MARK: - Spotify Integration (⭐ NEW)
    
    private func playMusicForCurrentPhase() {
        guard let spotify = spotifyManager, spotify.isAuthenticated else { return }
        
        Task {
            switch timerState.currentPhase {
            case .warmup:
                // Play warmup song if selected
                if let trackId = spotify.selectedWarmupTrackId {
                    print("🎵 Playing warmup track")
                    await spotify.playTrack(trackId: trackId)
                }
                
            case .work:
                // Play work playlist if selected
                if let playlistId = spotify.selectedWorkPlaylistId {
                    print("🎵 Playing work playlist")
                    await spotify.playPlaylist(playlistId: playlistId)
                }
                
            case .shortBreak, .longBreak:
                // Play break playlist if selected, otherwise pause
                if let playlistId = spotify.selectedBreakPlaylistId {
                    print("🎵 Playing break playlist")
                    await spotify.playPlaylist(playlistId: playlistId)
                } else {
                    print("⏸️ Pausing for break")
                    await spotify.pausePlayback()
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
