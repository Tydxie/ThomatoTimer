//
//  TimerAttributes.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/12/21.
//

#if os(iOS)
import ActivityKit
import Foundation

struct TimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: TimerPhase
        var timeRemaining: TimeInterval
        var isRunning: Bool
        var isPaused: Bool
        var completedSessions: Int
        var lastUpdateTime: Date
    }
    
    // Fixed attributes
    var workDuration: Int
    var breakDuration: Int
    var projectName: String?
}
#endif
