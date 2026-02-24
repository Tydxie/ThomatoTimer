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
    var timerState = TimerState()
    @Published var projectManager = ProjectManager.shared

    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var sessionStartTime: Date?
    private var accumulatedPausedTime: TimeInterval = 0
    private var lastPauseTime: Date?

    var spotifyManager: SpotifyManager?
    var appleMusicManager: AppleMusicManager?
    var selectedService: MusicService = .none

    init() {
        timerState.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }

    var currentPhaseDuration: TimeInterval {
        switch timerState.currentPhase {
        case .warmup:   return TimeInterval(timerState.warmupDuration * 60)
        case .work:     return TimeInterval(timerState.workDuration * 60)
        case .shortBreak: return TimeInterval(timerState.shortBreakDuration * 60)
        case .longBreak:  return TimeInterval(timerState.longBreakDuration * 60)
        }
    }


    func startWarmup() {
        timerState.startWarmup()
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        startCountdown()
        playMusicForCurrentPhase()
    }

    func toggleTimer() {
        if timerState.isPaused {
            if let pauseStart = lastPauseTime {
                accumulatedPausedTime += Date().timeIntervalSince(pauseStart)
                lastPauseTime = nil
            }
            timerState.resume()
            startCountdown()
            resumeMusic()
        } else if timerState.isRunning {
            lastPauseTime = Date()
            timerState.pause()
            stopCountdown()
            pauseMusic()
        } else {
            if timerState.currentPhase == .warmup {
                if timerState.warmupDuration > 0 {
                    startWarmup()
                } else {
                    timerState.currentPhase = .work
                    timerState.timeRemaining = TimeInterval(timerState.workDuration * 60)
                    timerState.runState = .running
                    sessionStartTime = Date()
                    accumulatedPausedTime = 0
                    startCountdown()
                    playMusicForCurrentPhase()
                }
            } else if timerState.currentPhase == .work && timerState.completedWorkSessions == 0 {
                timerState.runState = .running
                sessionStartTime = Date()
                accumulatedPausedTime = 0
                startCountdown()
                playMusicForCurrentPhase()
            } else {
                startNextSession()
            }
        }
    }

    func skipToNext() {
        stopCountdown()
        playBeep()
        logElapsedTime()
        timerState.startNextPhase()
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        lastPauseTime = nil
        startCountdown()
        playMusicForCurrentPhase()
    }

    func reset() {
        if timerState.runState != .idle {
            logElapsedTime()
        }
        stopCountdown()
        timerState.reset()
        sessionStartTime = nil
        accumulatedPausedTime = 0
        lastPauseTime = nil
        pauseMusic()
    }

    func switchProject(to project: Project?) {
        if timerState.runState != .idle {
            logElapsedTime()
        }
        if timerState.runState == .running {
            lastPauseTime = Date()
            timerState.pause()
            stopCountdown()
            pauseMusic()
        }
        projectManager.selectProject(project)
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        if timerState.isPaused {
            lastPauseTime = Date()
        }
    }


    private func startCountdown() {
        timer?.cancel()
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func stopCountdown() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard timerState.runState == .running else {
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
        logElapsedTime()
        timerState.startNextPhase()
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        lastPauseTime = nil
        NotificationManager.shared.sendPhaseCompleteNotification(
            phase: completedPhase,
            nextPhase: timerState.currentPhase
        )
        startCountdown()
        playMusicForCurrentPhase()
    }

    private func startNextSession() {
        timerState.startNextPhase()
        timerState.runState = .running
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        startCountdown()
        playMusicForCurrentPhase()
    }


    private func logElapsedTime() {
        guard timerState.currentPhase != .warmup else { return }
        guard let startTime = sessionStartTime else { return }

        var totalPausedTime = accumulatedPausedTime
        if timerState.isPaused, let pauseStart = lastPauseTime {
            totalPausedTime += Date().timeIntervalSince(pauseStart)
        }

        let elapsed = Date().timeIntervalSince(startTime) - totalPausedTime
        let minutes = Int(round(elapsed / 60.0))
        guard minutes >= 1 else { return }

        switch timerState.currentPhase {
        case .work:
            StatisticsManager.shared.logSession(type: .work, durationMinutes: minutes, projectId: projectManager.currentProjectId)
        case .shortBreak:
            StatisticsManager.shared.logSession(type: .shortBreak, durationMinutes: minutes, projectId: projectManager.currentProjectId)
        case .longBreak:
            StatisticsManager.shared.logSession(type: .longBreak, durationMinutes: minutes, projectId: projectManager.currentProjectId)
        case .warmup:
            break
        }
    }


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
        case .spotify:  playSpotifyMusic()
        case .appleMusic: playAppleMusic()
        case .none: break
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

    // MARK: - Display

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
}
