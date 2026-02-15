//
//  SharedTimerState.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/12/21.
//  Refactored: 2025/12/30 - Single enum state system
//

import Foundation

struct SharedTimerState: Codable {
    var phase: TimerPhase
    var timeRemaining: TimeInterval
    var runState: TimerRunState
    var completedSessions: Int
    var lastUpdateTime: Date
    var workDuration: Int
    var shortBreakDuration: Int
    var longBreakDuration: Int
    var sessionsUntilLongBreak: Int
    
    var isRunning: Bool {
        runState == .running
    }
    
    var isPaused: Bool {
        runState == .paused
    }
    
    var isIdle: Bool {
        runState == .idle
    }
    
    static let appGroupID = "group.com.thomasxie.thomato"
    
    // MARK: - Codable Support with Backward Compatibility
    
    enum CodingKeys: String, CodingKey {
        case phase
        case timeRemaining
        case runState
        case completedSessions
        case lastUpdateTime
        case workDuration
        case shortBreakDuration
        case longBreakDuration
        case sessionsUntilLongBreak
        case isRunning
        case isPaused
    }
    
    init(phase: TimerPhase,
         timeRemaining: TimeInterval,
         runState: TimerRunState,
         completedSessions: Int,
         lastUpdateTime: Date,
         workDuration: Int,
         shortBreakDuration: Int,
         longBreakDuration: Int,
         sessionsUntilLongBreak: Int) {
        self.phase = phase
        self.timeRemaining = timeRemaining
        self.runState = runState
        self.completedSessions = completedSessions
        self.lastUpdateTime = lastUpdateTime
        self.workDuration = workDuration
        self.shortBreakDuration = shortBreakDuration
        self.longBreakDuration = longBreakDuration
        self.sessionsUntilLongBreak = sessionsUntilLongBreak
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phase = try container.decode(TimerPhase.self, forKey: .phase)
        timeRemaining = try container.decode(TimeInterval.self, forKey: .timeRemaining)
        completedSessions = try container.decode(Int.self, forKey: .completedSessions)
        lastUpdateTime = try container.decode(Date.self, forKey: .lastUpdateTime)
        workDuration = try container.decode(Int.self, forKey: .workDuration)
        shortBreakDuration = try container.decode(Int.self, forKey: .shortBreakDuration)
        longBreakDuration = try container.decode(Int.self, forKey: .longBreakDuration)
        sessionsUntilLongBreak = try container.decode(Int.self, forKey: .sessionsUntilLongBreak)
        
        if let state = try? container.decode(TimerRunState.self, forKey: .runState) {
            runState = state
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
            print("SharedState migrated legacy format -> runState=\(runState)")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(phase, forKey: .phase)
        try container.encode(timeRemaining, forKey: .timeRemaining)
        try container.encode(runState, forKey: .runState)
        try container.encode(completedSessions, forKey: .completedSessions)
        try container.encode(lastUpdateTime, forKey: .lastUpdateTime)
        try container.encode(workDuration, forKey: .workDuration)
        try container.encode(shortBreakDuration, forKey: .shortBreakDuration)
        try container.encode(longBreakDuration, forKey: .longBreakDuration)
        try container.encode(sessionsUntilLongBreak, forKey: .sessionsUntilLongBreak)
        try container.encode(isRunning, forKey: .isRunning)
        try container.encode(isPaused, forKey: .isPaused)
    }
    
    // MARK: - Persistence
    
    static func save(_ state: SharedTimerState) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            print("Failed to access App Group")
            return
        }
        
        if let encoded = try? JSONEncoder().encode(state) {
            defaults.set(encoded, forKey: "sharedTimerState")
            defaults.synchronize()
            print("Saved shared timer state: \(state.phase), \(Int(state.timeRemaining))s, runState: \(state.runState)")
        }
    }
    
    static func load() -> SharedTimerState? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: "sharedTimerState"),
              let state = try? JSONDecoder().decode(SharedTimerState.self, from: data) else {
            print("No shared timer state found")
            return nil
        }
        
        print("Loaded shared timer state: \(state.phase), \(Int(state.timeRemaining))s, runState: \(state.runState)")
        return state
    }
    
    static func clear() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.removeObject(forKey: "sharedTimerState")
        defaults.synchronize()
        print("Cleared shared timer state")
    }
}
