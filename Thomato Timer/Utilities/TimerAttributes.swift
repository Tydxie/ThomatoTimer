//
//  TimerAttributes.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/12/21.
//  Refactored: 2025/12/30
//

#if os(iOS)
import ActivityKit
import Foundation

struct TimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: TimerPhase
        var timeRemaining: TimeInterval
        var runState: TimerRunState
        var completedSessions: Int
        var lastUpdateTime: Date
        
        var isRunning: Bool {
            runState == .running
        }
        
        var isPaused: Bool {
            runState == .paused
        }
        
        var isIdle: Bool {
            runState == .idle
        }
        
        // MARK: - Codable Support with Backward Compatibility
        
        enum CodingKeys: String, CodingKey {
            case phase
            case timeRemaining
            case runState
            case completedSessions
            case lastUpdateTime
            case isRunning
            case isPaused
        }
        
        public init(phase: TimerPhase,
                    timeRemaining: TimeInterval,
                    runState: TimerRunState,
                    completedSessions: Int,
                    lastUpdateTime: Date) {
            self.phase = phase
            self.timeRemaining = timeRemaining
            self.runState = runState
            self.completedSessions = completedSessions
            self.lastUpdateTime = lastUpdateTime
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            phase = try container.decode(TimerPhase.self, forKey: .phase)
            timeRemaining = try container.decode(TimeInterval.self, forKey: .timeRemaining)
            completedSessions = try container.decode(Int.self, forKey: .completedSessions)
            lastUpdateTime = try container.decode(Date.self, forKey: .lastUpdateTime)
            
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
                print("TimerAttributes migrated legacy format -> runState=\(runState)")
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(phase, forKey: .phase)
            try container.encode(timeRemaining, forKey: .timeRemaining)
            try container.encode(runState, forKey: .runState)
            try container.encode(completedSessions, forKey: .completedSessions)
            try container.encode(lastUpdateTime, forKey: .lastUpdateTime)
            try container.encode(isRunning, forKey: .isRunning)
            try container.encode(isPaused, forKey: .isPaused)
        }
    }
    
    var workDuration: Int
    var breakDuration: Int
    var projectName: String?
}
#endif // os(iOS)
