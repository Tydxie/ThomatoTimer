//
//  TimerViewModel.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/24.
//

import Foundation
import Combine
import AppKit

class TimerViewModel: ObservableObject {
    let timerState: TimerState
    let engine: TimerEngine

    @Published var projectManager = ProjectManager.shared

    private var cancellables = Set<AnyCancellable>()

    var spotifyManager: SpotifyManager?
    var appleMusicManager: AppleMusicManager?
    var selectedService: MusicService = .none

    init() {
        let state = TimerState()
        let engine = TimerEngine(timerState: state)
        self.timerState = state
        self.engine = engine

        state.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)

        engine.onPhaseComplete = { [weak self] completed, next in
            guard let self else { return }
            self.playBeep()
            self.playMusicForCurrentPhase()
            NotificationManager.shared.sendPhaseCompleteNotification(
                phase: completed,
                nextPhase: next
            )
        }
    }

    // MARK: - Timer Controls

    func toggleTimer() {
        if timerState.isPaused {
            engine.resume()
            resumeMusic()
        } else if timerState.isRunning {
            engine.pause()
            pauseMusic()
        } else {
            engine.start()
            playMusicForCurrentPhase()
        }
    }

    func skipToNext() {
        engine.skip()
    }

    func reset() {
        engine.reset()
        pauseMusic()
    }

    func switchProject(to project: Project?) {
        if timerState.runState == .running {
            engine.pause()
            pauseMusic()
        }
        projectManager.selectProject(project)
    }

    // MARK: - Display

    var currentPhaseDuration: TimeInterval {
        switch timerState.currentPhase {
        case .warmup:      return TimeInterval(timerState.warmupDuration * 60)
        case .work:        return TimeInterval(timerState.workDuration * 60)
        case .shortBreak:  return TimeInterval(timerState.shortBreakDuration * 60)
        case .longBreak:   return TimeInterval(timerState.longBreakDuration * 60)
        }
    }

    var displayTime: String {
        let minutes = Int(timerState.timeRemaining) / 60
        let seconds = Int(timerState.timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var phaseTitle: String {
        switch timerState.currentPhase {
        case .warmup:      return "Starting Soon"
        case .work:        return "Work"
        case .shortBreak:  return "Short Break"
        case .longBreak:   return "Long Break"
        }
    }

    var buttonTitle: String {
        if timerState.isPaused  { return "Resume" }
        if timerState.isRunning { return "Pause" }
        return "Start"
    }

    // MARK: - Music

    private func resumeMusic() {
        switch selectedService {
        case .spotify:
            if let spotify = spotifyManager, spotify.isAuthenticated {
                Task { await spotify.resumePlayback() }
            }
        case .appleMusic:
            if let appleMusic = appleMusicManager, appleMusic.isAuthorized {
                appleMusic.play()
            }
        case .none:
            break
        }
    }

    private func pauseMusic() {
        switch selectedService {
        case .spotify:
            if let spotify = spotifyManager, spotify.isAuthenticated {
                Task { await spotify.pausePlayback() }
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
        case .spotify:    playSpotifyMusic()
        case .appleMusic: playAppleMusic()
        case .none:       break
        }
    }

    private func playSpotifyMusic() {
        guard let spotify = spotifyManager, spotify.isAuthenticated else { return }
        let phase = timerState.currentPhase
        Task.detached { await self.executeSpotifyPlayback(for: phase, spotify: spotify) }
    }

    private func executeSpotifyPlayback(for phase: TimerPhase, spotify: SpotifyManager) async {
        switch phase {
        case .warmup, .shortBreak, .longBreak:
            if let id = spotify.selectedBreakPlaylistId {
                await spotify.playPlaylist(playlistId: id)
            } else {
                await spotify.pausePlayback()
            }
        case .work:
            if let id = spotify.selectedWorkPlaylistId {
                await spotify.playPlaylist(playlistId: id)
            } else {
                await spotify.pausePlayback()
            }
        }
    }

    private func playAppleMusic() {
        guard let appleMusic = appleMusicManager, appleMusic.isAuthorized else { return }
        let phase = timerState.currentPhase
        Task.detached { await self.executeAppleMusicPlayback(for: phase, appleMusic: appleMusic) }
    }

    private func executeAppleMusicPlayback(for phase: TimerPhase, appleMusic: AppleMusicManager) async {
        switch phase {
        case .warmup, .shortBreak, .longBreak:
            if let id = appleMusic.selectedBreakPlaylistId {
                await appleMusic.playPlaylist(id: id)
            } else {
                appleMusic.pause()
            }
        case .work:
            if let id = appleMusic.selectedWorkPlaylistId {
                await appleMusic.playPlaylist(id: id)
            } else {
                appleMusic.pause()
            }
        }
    }

    // MARK: - Audio

    private func playBeep() {
        NSSound(named: "Glass")?.play()
    }
}
