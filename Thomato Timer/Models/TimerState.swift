//
//  TimerState.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/28.
//  Refactored: 2025/12/30
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

enum TimerRunState: String, Codable {
    case idle
    case running
    case paused
}

class TimerState: ObservableObject, Codable {
    @Published var currentPhase: TimerPhase = .warmup
    @Published var timeRemaining: TimeInterval = 5 * 60
    
    @Published var runState: TimerRunState = .idle {
        didSet {
            print("TimerState.runState changed: \(oldValue) -> \(runState)")
            print("   Call stack: \(Thread.callStackSymbols.prefix(3).joined(separator: "\n   "))")
            objectWillChange.send()
        }
    }
    
    @Published var completedWorkSessions: Int = 0
    
    var isRunning: Bool {
        runState == .running
    }
    
    var isPaused: Bool {
        runState == .paused
    }
    
    var isIdle: Bool {
        runState == .idle
    }
    
    @AppStorage("workDuration") var workDuration: Int = 60
    @AppStorage("shortBreakDuration") var shortBreakDuration: Int = 10
    @AppStorage("longBreakDuration") var longBreakDuration: Int = 20
    @AppStorage("warmupDuration") var warmupDuration: Int = 5
    @AppStorage("sessionsUntilLongBreak") var sessionsUntilLongBreak: Int = 4
    
    var checkmarks: String {
        guard sessionsUntilLongBreak > 0 else { return "" }
        let count = completedWorkSessions % sessionsUntilLongBreak
        return String(repeating: "✓", count: count)
    }
    
    // MARK: - Codable Support
    
    enum CodingKeys: String, CodingKey {
        case currentPhase
        case timeRemaining
        case runState
        case completedWorkSessions
        case isRunning
        case isPaused
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentPhase = try container.decode(TimerPhase.self, forKey: .currentPhase)
        timeRemaining = try container.decode(TimeInterval.self, forKey: .timeRemaining)
        completedWorkSessions = try container.decode(Int.self, forKey: .completedWorkSessions)
        
        if let state = try? container.decode(TimerRunState.self, forKey: .runState) {
            runState = state
            print("Loaded new runState format: \(state)")
        } else {
            let wasRunning = try container.decodeIfPresent(Bool.self, forKey: .isRunning) ?? false
            let wasPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
            
            if wasPaused {
                runState = .paused
            } else if wasRunning {
                runState = .running
            } else {
                runState = .idle
            }
            print("Migrated legacy format: isRunning=\(wasRunning), isPaused=\(wasPaused) -> runState=\(runState)")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(currentPhase, forKey: .currentPhase)
        try container.encode(timeRemaining, forKey: .timeRemaining)
        try container.encode(runState, forKey: .runState)
        try container.encode(completedWorkSessions, forKey: .completedWorkSessions)
        try container.encode(isRunning, forKey: .isRunning)
        try container.encode(isPaused, forKey: .isPaused)
    }
    
    init() {
    }
    
    // MARK: - Timer Control
    
    func startWarmup() {
        print("TimerState.startWarmup() called")
        currentPhase = .warmup
        timeRemaining = TimeInterval(warmupDuration * 60)
        runState = .running
    }
    
    func startNextPhase() {
        print("TimerState.startNextPhase() called - current: \(currentPhase)")
        
        if currentPhase == .warmup {
            currentPhase = .work
            timeRemaining = TimeInterval(workDuration * 60)
            runState = .running
            return
        }
        
        if currentPhase == .work {
            completedWorkSessions += 1
            
            if sessionsUntilLongBreak > 0,
               completedWorkSessions % sessionsUntilLongBreak == 0 {
                currentPhase = .longBreak
                timeRemaining = TimeInterval(longBreakDuration * 60)
            } else {
                currentPhase = .shortBreak
                timeRemaining = TimeInterval(shortBreakDuration * 60)
            }
        } else {
            currentPhase = .work
            timeRemaining = TimeInterval(workDuration * 60)
        }
        
        runState = .running
    }
    
    func pause() {
        print("TimerState.pause() called")
        print("   Call stack: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n   "))")
        runState = .paused
    }
    
    func resume() {
        print("TimerState.resume() called")
        print("   Call stack: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n   "))")
        runState = .running
    }
    
    func reset() {
        print("TimerState.reset() called")
        runState = .idle
        completedWorkSessions = 0
        
        if warmupDuration == 0 {
            currentPhase = .work
            timeRemaining = TimeInterval(workDuration * 60)
        } else {
            currentPhase = .warmup
            timeRemaining = TimeInterval(warmupDuration * 60)
        }
    }
    
    // MARK: - Persistence
    
    func saveToUserDefaults(forceSync: Bool = false) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(self) {
            UserDefaults.standard.set(encoded, forKey: "savedTimerState")
            UserDefaults.standard.set(Date(), forKey: "savedStateTimestamp")
            
            if forceSync {
                UserDefaults.standard.synchronize()
            }
            
            print("Timer state saved\(forceSync ? " (forced sync)" : "") - runState: \(runState)")
        }
    }
    
    static func loadFromUserDefaults() -> (state: TimerState, timestamp: Date)? {
        guard let data = UserDefaults.standard.data(forKey: "savedTimerState"),
              let timestamp = UserDefaults.standard.object(forKey: "savedStateTimestamp") as? Date,
              let state = try? JSONDecoder().decode(TimerState.self, from: data) else {
            return nil
        }
        print("Loaded timer state - runState: \(state.runState)")
        return (state, timestamp)
    }
    
    static func clearSavedState() {
        UserDefaults.standard.removeObject(forKey: "savedTimerState")
        UserDefaults.standard.removeObject(forKey: "savedStateTimestamp")
        print("Saved timer state cleared")
    }
}
