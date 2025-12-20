//
//  TimerState.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/28.
//

import Foundation

enum TimerPhase: String, Codable {
    case warmup
    case work
    case shortBreak
    case longBreak
}

struct TimerState: Codable {
    // Current state
    var currentPhase: TimerPhase = .warmup
    var timeRemaining: TimeInterval = 5 * 60  // Start with 5 minutes (300 seconds)
    var isRunning: Bool = false
    var isPaused: Bool = false
    var completedWorkSessions: Int = 0
    
    // User settings (customizable durations in minutes)
    var workDuration: Int = 60
    var shortBreakDuration: Int = 10
    var longBreakDuration: Int = 20
    
    // 🔥 UPDATED: Warmup can now be 0 (no warmup)
    var warmupDuration: Int = 5 {
        didSet {
            // Only update if we're in warmup phase and timer hasn't started
            if currentPhase == .warmup && !isRunning && !isPaused && warmupDuration > 0 {
                timeRemaining = TimeInterval(warmupDuration * 60)
            }
        }
    }
    
    // User setting: how many work sessions before a long break
    var sessionsUntilLongBreak: Int = 4
    
    // Computed property for checkmarks
    var checkmarks: String {
        // Avoid division by zero if user somehow sets 0
        guard sessionsUntilLongBreak > 0 else { return "" }
        let count = completedWorkSessions % sessionsUntilLongBreak
        return String(repeating: "✓", count: count)
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
            isRunning = true
            isPaused = false
            return
        }
        
        if currentPhase == .work {
            completedWorkSessions += 1
            
            // Decide break type based on sessionsUntilLongBreak
            if sessionsUntilLongBreak > 0,
               completedWorkSessions % sessionsUntilLongBreak == 0 {
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
        
        isRunning = true
        isPaused = false
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
        completedWorkSessions = 0
        
        // 🔥 NEW: If warmup is 0, reset to work phase instead
        if warmupDuration == 0 {
            currentPhase = .work
            timeRemaining = TimeInterval(workDuration * 60)
        } else {
            currentPhase = .warmup
            timeRemaining = TimeInterval(warmupDuration * 60)
        }
    }
    
    // MARK: - 🔥 Persistence (Optimized)
    
    func saveToUserDefaults(forceSync: Bool = false) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(self) {
            UserDefaults.standard.set(encoded, forKey: "savedTimerState")
            UserDefaults.standard.set(Date(), forKey: "savedStateTimestamp")
            
            // 🔥 Only force sync when explicitly needed (critical moments)
            if forceSync {
                UserDefaults.standard.synchronize()
            }
            
            print("💾 Timer state saved\(forceSync ? " (forced sync)" : "")")
        }
    }
    
    static func loadFromUserDefaults() -> (state: TimerState, timestamp: Date)? {
        guard let data = UserDefaults.standard.data(forKey: "savedTimerState"),
              let timestamp = UserDefaults.standard.object(forKey: "savedStateTimestamp") as? Date,
              let state = try? JSONDecoder().decode(TimerState.self, from: data) else {
            return nil
        }
        return (state, timestamp)
    }
    
    static func clearSavedState() {
        UserDefaults.standard.removeObject(forKey: "savedTimerState")
        UserDefaults.standard.removeObject(forKey: "savedStateTimestamp")
        print("🗑️ Saved timer state cleared")
    }
}
