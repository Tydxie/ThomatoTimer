//
//  SharedTimerState.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/12/21.
//


import Foundation

struct SharedTimerState: Codable {
    var phase: TimerPhase
    var timeRemaining: TimeInterval
    var isRunning: Bool
    var isPaused: Bool
    var completedSessions: Int
    var lastUpdateTime: Date
    var workDuration: Int
    var shortBreakDuration: Int
    var longBreakDuration: Int
    var sessionsUntilLongBreak: Int
    
    static let appGroupID = "group.com.thomasxie.thomato" // 🔥 Change to your App Group ID
    
    static func save(_ state: SharedTimerState) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            print("❌ Failed to access App Group")
            return
        }
        
        if let encoded = try? JSONEncoder().encode(state) {
            defaults.set(encoded, forKey: "sharedTimerState")
            defaults.synchronize()
            print("✅ Saved shared timer state: \(state.phase), \(Int(state.timeRemaining))s")
        }
    }
    
    static func load() -> SharedTimerState? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: "sharedTimerState"),
              let state = try? JSONDecoder().decode(SharedTimerState.self, from: data) else {
            print("❌ No shared timer state found")
            return nil
        }
        
        print("✅ Loaded shared timer state: \(state.phase), \(Int(state.timeRemaining))s")
        return state
    }
    
    static func clear() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.removeObject(forKey: "sharedTimerState")
        defaults.synchronize()
        print("🗑️ Cleared shared timer state")
    }
}
