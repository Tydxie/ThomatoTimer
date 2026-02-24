//
//  TimerEngine.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2026/02/24.
//

import Foundation
import Combine

class TimerEngine {
    
    let timerState: TimerState
    var onPhaseComplete: ((TimerPhase, TimerPhase) -> Void)?
    
    private var timer: AnyCancellable?
    private var sessionStartTime: Date?
    private var accumulatedPausedTime: TimeInterval = 0
    private var lastPauseTime: Date?
    
    init(timerState: TimerState) {
        self.timerState = timerState
    }
    
    // MARK: - Public Interface
    
    func start() {
        guard timerState.runState == .idle else { return }
        if timerState.currentPhase == .warmup && timerState.warmupDuration > 0 {
            timerState.startWarmup()
        } else {
            timerState.currentPhase = .work
            timerState.timeRemaining = TimeInterval(timerState.workDuration * 60)
            timerState.runState = .running
        }
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        startCountdown()
    }
    
    func pause() {
        guard timerState.runState == .running else { return }
        lastPauseTime = Date()
        timerState.pause()
        stopCountdown()
    }
    
    func resume() {
        guard timerState.runState == .paused else { return }
        if let pauseStart = lastPauseTime {
            accumulatedPausedTime += Date().timeIntervalSince(pauseStart)
            lastPauseTime = nil
        }
        timerState.resume()
        startCountdown()
    }
    
    func skip() {
        stopCountdown()
        let completedPhase = timerState.currentPhase
        logElapsedTime()
        timerState.startNextPhase()
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        lastPauseTime = nil
        startCountdown()
        onPhaseComplete?(completedPhase, timerState.currentPhase)
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
    }
    
    // MARK: - Private
    
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
        let completedPhase = timerState.currentPhase
        logElapsedTime()
        timerState.startNextPhase()
        sessionStartTime = Date()
        accumulatedPausedTime = 0
        lastPauseTime = nil
        startCountdown()
        onPhaseComplete?(completedPhase, timerState.currentPhase)
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
        
        let projectId = ProjectManager.shared.currentProjectId
        
        switch timerState.currentPhase {
        case .work:
            StatisticsManager.shared.logSession(type: .work, durationMinutes: minutes, projectId: projectId)
        case .shortBreak:
            StatisticsManager.shared.logSession(type: .shortBreak, durationMinutes: minutes, projectId: projectId)
        case .longBreak:
            StatisticsManager.shared.logSession(type: .longBreak, durationMinutes: minutes, projectId: projectId)
        case .warmup:
            break
        }
    }
}
