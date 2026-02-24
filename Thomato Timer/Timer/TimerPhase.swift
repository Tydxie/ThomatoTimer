//
//  TimerPhase.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2026/02/24.
//

import Foundation

enum TimerPhase: String, CaseIterable {
    case warmup
    case work
    case shortBreak
    case longBreak

    func next(sessionsCompleted: Int, sessionsUntilLong: Int) -> TimerPhase {
        switch self {
        case .warmup:
            return .work
        case .work:
            if sessionsUntilLong > 0, sessionsCompleted % sessionsUntilLong == 0 {
                return .longBreak
            }
            return .shortBreak
        case .shortBreak, .longBreak:
            return .work
        }
    }
    
}

enum TimerRunState {
    case idle
    case running
    case paused
}

