//
//  TimerState.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/28.
//

import Foundation

enum TimerPhase {
    case warmup
    case work
    case shortBreak
    case longBreak
}

struct TimerState {
    // Current state
    var currentPhase: TimerPhase = .warmup
    var timeRemaining: TimeInterval = 0
    var isRunning: Bool = false
    var isPaused: Bool = false
    var completedWorkSessions: Int = 0
    
    // User settings (customizable durations in minutes)
    var workDuration: Int = 60
    var shortBreakDuration: Int = 10
    var longBreakDuration: Int = 20
    var warmupDuration: Int = 5  // 5 or 10 minutes
    
    // Constants
    let sessionsUntilLongBreak: Int = 4
    let totalSessionsBeforeReset: Int = 8
    
    // Computed property for checkmarks
    var checkmarks: String {
        String(repeating: "✓", count: completedWorkSessions % sessionsUntilLongBreak)
    }
    
    mutating func startWarmup() {
        currentPhase = .warmup
        timeRemaining = TimeInterval(warmupDuration * 60)
        isRunning = true
        isPaused = false
    }
    
    mutating func startNextPhase() {
        if currentPhase == .warmup {
            // After warmup, start first work session
            currentPhase = .work
            timeRemaining = TimeInterval(workDuration * 60)
            return
        }
        
        if currentPhase == .work {
            completedWorkSessions += 1
            
            // Check if we've completed 8 sessions (4 full cycles)
            if completedWorkSessions >= totalSessionsBeforeReset {
                reset()
                return
            }
            
            // Decide break type
            if completedWorkSessions % sessionsUntilLongBreak == 0 {
                currentPhase = .longBreak
                timeRemaining = TimeInterval(longBreakDuration * 60)
            } else {
                currentPhase = .shortBreak
                timeRemaining = TimeInterval(shortBreakDuration * 60)
            }
        } else {
            // After any break, go back to work
            currentPhase = .work
            timeRemaining = TimeInterval(workDuration * 60)
        }
    }
    
    mutating func pause() {
        isPaused = true
        isRunning = false
    }
    
    mutating func resume() {
        isPaused = false
        isRunning = true
    }
    
    mutating func reset() {
        isRunning = false
        isPaused = false
        timeRemaining = 0
        currentPhase = .warmup
        completedWorkSessions = 0
    }
}
