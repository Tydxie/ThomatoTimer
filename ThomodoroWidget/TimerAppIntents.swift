//
//  TimerAppIntents.swift
//  Thomato Timer
//

import AppIntents
import Foundation
import ActivityKit

// Toggle (Pause/Resume) Intent
struct ToggleTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Timer"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        print("🎯 Widget: Toggle button pressed")
        
        // Update the Live Activity directly
        if let activity = Activity<TimerAttributes>.activities.first {
            var newState = activity.content.state
            
            // Calculate elapsed time since last update
            let elapsed = Date().timeIntervalSince(newState.lastUpdateTime)
            
            // If running and not paused, subtract elapsed time
            if newState.isRunning && !newState.isPaused {
                newState.timeRemaining = max(0, newState.timeRemaining - elapsed)
            }
            
            if newState.isPaused {
                // Resume
                newState.isPaused = false
                newState.isRunning = true
                newState.lastUpdateTime = Date()
                print("▶️ Widget: Resuming timer - Remaining: \(Int(newState.timeRemaining))s")
            } else if newState.isRunning {
                // Pause
                newState.isPaused = true
                newState.isRunning = false
                newState.lastUpdateTime = Date()
                print("⏸️ Widget: Pausing timer - Remaining: \(Int(newState.timeRemaining))s")
            }
            
            // Update Live Activity
            await activity.update(.init(state: newState, staleDate: nil))
            
            // Save to shared state
            let sharedState = SharedTimerState(
                phase: newState.phase,
                timeRemaining: newState.timeRemaining,
                isRunning: newState.isRunning,
                isPaused: newState.isPaused,
                completedSessions: newState.completedSessions,
                lastUpdateTime: newState.lastUpdateTime,
                workDuration: activity.attributes.workDuration,
                shortBreakDuration: activity.attributes.breakDuration,
                longBreakDuration: activity.attributes.breakDuration * 2,
                sessionsUntilLongBreak: 4
            )
            SharedTimerState.save(sharedState)
            
            print("✅ Widget: Saved new state - isPaused: \(newState.isPaused), Remaining: \(Int(newState.timeRemaining))s")
        }
        
        // Also notify the app if it's running
        NotificationCenter.default.post(name: .toggleTimerFromWidget, object: nil)
        
        return .result()
    }
}

// Skip Intent
struct SkipTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Phase"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        print("🎯 Widget: Skip button pressed")
        
        // Update the Live Activity directly
        if let activity = Activity<TimerAttributes>.activities.first {
            var newState = activity.content.state
            
            // Calculate next phase
            let nextPhase = calculateNextPhase(current: newState.phase, completedSessions: newState.completedSessions)
            
            // Update sessions count if completing a work session
            if newState.phase == .work {
                newState.completedSessions += 1
            }
            
            // Set new phase
            newState.phase = nextPhase
            newState.timeRemaining = getPhaseDuration(phase: nextPhase, workDuration: activity.attributes.workDuration, breakDuration: activity.attributes.breakDuration)
            newState.lastUpdateTime = Date()
            newState.isRunning = true
            newState.isPaused = false
            
            print("⏭️ Widget: Skipped to \(nextPhase), Duration: \(Int(newState.timeRemaining))s")
            
            // Update Live Activity
            await activity.update(.init(state: newState, staleDate: nil))
            
            // Save to shared state
            let sharedState = SharedTimerState(
                phase: newState.phase,
                timeRemaining: newState.timeRemaining,
                isRunning: newState.isRunning,
                isPaused: newState.isPaused,
                completedSessions: newState.completedSessions,
                lastUpdateTime: newState.lastUpdateTime,
                workDuration: activity.attributes.workDuration,
                shortBreakDuration: activity.attributes.breakDuration,
                longBreakDuration: activity.attributes.breakDuration * 2,
                sessionsUntilLongBreak: 4
            )
            SharedTimerState.save(sharedState)
        }
        
        // Also notify the app if it's running
        NotificationCenter.default.post(name: .skipTimerFromWidget, object: nil)
        
        return .result()
    }
    
    private func calculateNextPhase(current: TimerPhase, completedSessions: Int) -> TimerPhase {
        switch current {
        case .warmup:
            return .work
        case .work:
            // After 4 work sessions (now at 4), take long break
            return (completedSessions + 1) % 4 == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .work
        }
    }
    
    private func getPhaseDuration(phase: TimerPhase, workDuration: Int, breakDuration: Int) -> TimeInterval {
        switch phase {
        case .warmup:
            return 0
        case .work:
            return TimeInterval(workDuration * 60)
        case .shortBreak:
            return TimeInterval(breakDuration * 60)
        case .longBreak:
            return TimeInterval(breakDuration * 2 * 60)
        }
    }
}
