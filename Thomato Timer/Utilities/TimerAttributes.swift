//
//  TimerAttributes.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/12/21.
//

import ActivityKit
import Foundation

struct TimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic properties that update during the activity
        var phase: TimerPhase
        var timeRemaining: TimeInterval
        var isRunning: Bool
        var isPaused: Bool
        var completedSessions: Int
        var lastUpdateTime: Date
    }
    
    // Fixed properties that don't change during the activity
    var workDuration: Int
    var breakDuration: Int
    var projectName: String?
}

