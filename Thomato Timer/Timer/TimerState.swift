//
//  TimerState.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/28.
//

import Foundation
import Combine
import SwiftUI


class TimerState: ObservableObject {
    @Published var currentPhase: TimerPhase = .warmup
    @Published var timeRemaining: TimeInterval = 5 * 60
    @Published var runState: TimerRunState = .idle
    @Published var completedWorkSessions: Int = 0
    
    @AppStorage("workDuration") var workDuration: Int = 25
    @AppStorage("shortBreakDuration") var shortBreakDuration: Int = 5
    @AppStorage("longBreakDuration") var longBreakDuration: Int = 20
    @AppStorage("warmupDuration") var warmupDuration: Int = 5
    @AppStorage("sessionsUntilLongBreak") var sessionsUntilLongBreak: Int = 4
    
    var isRunning: Bool { runState == .running }
    var isPaused: Bool  { runState == .paused }
    var isIdle: Bool    { runState == .idle }
    
    var checkmarks: String {
        guard sessionsUntilLongBreak > 0 else { return "" }
        let count = completedWorkSessions % sessionsUntilLongBreak
        return String(repeating: "✓", count: count)
    }
    
    // MARK: - State Transitions
    
    func startWarmup() {
        currentPhase = .warmup
        timeRemaining = TimeInterval(warmupDuration * 60)
        runState = .running
    }
    
    func startNextPhase() {
        if currentPhase == .work {
            completedWorkSessions += 1
        }
        currentPhase = currentPhase.next(
            sessionsCompleted: completedWorkSessions,
            sessionsUntilLong: sessionsUntilLongBreak
        )
        timeRemaining = duration(for: currentPhase)
        runState = .running
    }
    
    func pause() {
        guard runState == .running else { return }
        runState = .paused
    }
    
    func resume() {
        guard runState == .paused else { return }
        runState = .running
    }
    
    func reset() {
        runState = .idle
        completedWorkSessions = 0
        currentPhase = warmupDuration > 0 ? .warmup : .work
        timeRemaining = warmupDuration > 0
        ? TimeInterval(warmupDuration * 60)
        : TimeInterval(workDuration * 60)
    }
    
    private func duration(for phase: TimerPhase) -> TimeInterval {
        switch phase {
        case .warmup:      return TimeInterval(warmupDuration * 60)
        case .work:        return TimeInterval(workDuration * 60)
        case .shortBreak:  return TimeInterval(shortBreakDuration * 60)
        case .longBreak:   return TimeInterval(longBreakDuration * 60)
        }
    }
}
