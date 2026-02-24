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
    let musicCoordinator = MusicCoordinator()

    @Published var projectManager = ProjectManager.shared

    private var cancellables = Set<AnyCancellable>()

    var spotifyManager: SpotifyManager? {
        get {musicCoordinator.spotifyManager}
        set {musicCoordinator.spotifyManager = newValue}
    }
    var appleMusicManager: AppleMusicManager? {
        get {musicCoordinator.appleMusicManager}
        set {musicCoordinator.appleMusicManager = newValue}
    }
    var selectedService: MusicService {
        get {musicCoordinator.selectedService}
        set {musicCoordinator.selectedService = newValue}
    }

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
            self.musicCoordinator.play(for: next)
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
            musicCoordinator.resume()
        } else if timerState.isRunning {
            engine.pause()
            musicCoordinator.pause()
        } else {
            engine.start()
            musicCoordinator.play(for: timerState.currentPhase)
        }
    }

    func skipToNext() {
        engine.skip()
    }

    func reset() {
        engine.reset()
        musicCoordinator.pause()
    }

    func switchProject(to project: Project?) {
        if timerState.runState == .running {
            engine.pause()
            musicCoordinator.pause()
        }
        projectManager.selectProject(project)
    }


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


    private func playBeep() {
        NSSound(named: "Glass")?.play()
    }
}
