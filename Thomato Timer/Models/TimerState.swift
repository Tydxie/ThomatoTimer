//
//  TimerState.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/28.
//

import Foundation
import SwiftUI
import Combine

enum TimerPhase: String, Codable, CaseIterable {
    case warmup
    case work
    case shortBreak
    case longBreak
}

class TimerState: ObservableObject, Codable {
    // Current state
    @Published var currentPhase: TimerPhase = .warmup
    @Published var timeRemaining: TimeInterval = 5 * 60  // Start with 5 minutes (300 seconds)
    var isRunning: Bool = false {
        didSet {
            print("🔄 TimerState.isRunning changed: \(oldValue) → \(isRunning)")
            print("   Call stack: \(Thread.callStackSymbols.prefix(3).joined(separator: "\n   "))")
            objectWillChange.send()  // Manually trigger update
        }
    }
    var isPaused: Bool = false {
        didSet {
            print("🔄 TimerState.isPaused changed: \(oldValue) → \(isPaused)")
            print("   Call stack: \(Thread.callStackSymbols.prefix(3).joined(separator: "\n   "))")
            objectWillChange.send()  // Manually trigger update
        }
    }
    @Published var completedWorkSessions: Int = 0
    
    // 🔥 User settings (persistent via @AppStorage)
    @AppStorage("workDuration") var workDuration: Int = 60
    @AppStorage("shortBreakDuration") var shortBreakDuration: Int = 10
    @AppStorage("longBreakDuration") var longBreakDuration: Int = 20
    @AppStorage("warmupDuration") var warmupDuration: Int = 5
    @AppStorage("sessionsUntilLongBreak") var sessionsUntilLongBreak: Int = 4
    
    // Computed property for checkmarks
    var checkmarks: String {
        guard sessionsUntilLongBreak > 0 else { return "" }
        let count = completedWorkSessions % sessionsUntilLongBreak
        return String(repeating: "✓", count: count)
    }
    
    // MARK: - Codable Support
    
    enum CodingKeys: String, CodingKey {
        case currentPhase
        case timeRemaining
        case isRunning
        case isPaused
        case completedWorkSessions
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentPhase = try container.decode(TimerPhase.self, forKey: .currentPhase)
        timeRemaining = try container.decode(TimeInterval.self, forKey: .timeRemaining)
        isRunning = try container.decode(Bool.self, forKey: .isRunning)
        isPaused = try container.decode(Bool.self, forKey: .isPaused)
        completedWorkSessions = try container.decode(Int.self, forKey: .completedWorkSessions)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(currentPhase, forKey: .currentPhase)
        try container.encode(timeRemaining, forKey: .timeRemaining)
        try container.encode(isRunning, forKey: .isRunning)
        try container.encode(isPaused, forKey: .isPaused)
        try container.encode(completedWorkSessions, forKey: .completedWorkSessions)
    }
    
    init() {
        // @AppStorage properties are automatically loaded
    }
    
    // MARK: - Timer Control
    
    func startWarmup() {
        print("🎬 TimerState.startWarmup() called")
        currentPhase = .warmup
        timeRemaining = TimeInterval(warmupDuration * 60)
        isRunning = true
        isPaused = false
    }
    
    func startNextPhase() {
        print("⏭️ TimerState.startNextPhase() called - current: \(currentPhase)")
        
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
    
    func pause() {
        print("⏸️ TimerState.pause() called")
        print("   Call stack: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n   "))")
        isPaused = true
        isRunning = false
    }
    
    func resume() {
        print("▶️ TimerState.resume() called")
        print("   Call stack: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n   "))")
        isPaused = false
        isRunning = true
    }
    
    func reset() {
        print("🔄 TimerState.reset() called")
        isRunning = false
        isPaused = false
        completedWorkSessions = 0
        
        // 🔥 If warmup is 0, reset to work phase instead
        if warmupDuration == 0 {
            currentPhase = .work
            timeRemaining = TimeInterval(workDuration * 60)
        } else {
            currentPhase = .warmup
            timeRemaining = TimeInterval(warmupDuration * 60)
        }
    }
    
    // MARK: - 🔥 Persistence
    
    func saveToUserDefaults(forceSync: Bool = false) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(self) {
            UserDefaults.standard.set(encoded, forKey: "savedTimerState")
            UserDefaults.standard.set(Date(), forKey: "savedStateTimestamp")
            
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
