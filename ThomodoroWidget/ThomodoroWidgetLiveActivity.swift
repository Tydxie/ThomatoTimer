//
//  ThomodoroWidgetLiveActivity.swift
//  ThomodoroWidget
//
//  Created by Thomas Xie on 2025/12/22.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ThomodoroWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerAttributes.self) { context in
            // Lock screen/banner UI
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: phaseIcon(context.state.phase))
                            .font(.title3)
                            .foregroundColor(phaseColor(context.state.phase))
                        Text(phaseTitle(context.state.phase))
                            .font(.caption)
                            .bold()
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isRunning && !context.state.isPaused {
                        Text(timerInterval: context.state.lastUpdateTime...context.state.lastUpdateTime.addingTimeInterval(context.state.timeRemaining), countsDown: true)
                            .font(.title2)
                            .bold()
                            .monospacedDigit()
                    } else {
                        Text(timeString(context.state.timeRemaining))
                            .font(.title2)
                            .bold()
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 20) {
                        // Skip button
                        Link(destination: URL(string: "thomato-timer://skip")!) {
                            Image(systemName: "forward.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                        }
                        
                        // Pause/Resume button
                        Link(destination: URL(string: "thomato-timer://toggle")!) {
                            Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.top, 8)
                }
            } compactLeading: {
                Image(systemName: phaseIcon(context.state.phase))
                    .foregroundColor(phaseColor(context.state.phase))
            } compactTrailing: {
                if context.state.isRunning && !context.state.isPaused {
                    Text(timerInterval: context.state.lastUpdateTime...context.state.lastUpdateTime.addingTimeInterval(context.state.timeRemaining), countsDown: true)
                        .monospacedDigit()
                        .font(.caption2)
                } else {
                    Text(timeString(context.state.timeRemaining))
                        .monospacedDigit()
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } minimal: {
                Image(systemName: phaseIcon(context.state.phase))
                    .foregroundColor(phaseColor(context.state.phase))
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func phaseIcon(_ phase: TimerPhase) -> String {
        switch phase {
        case .warmup: return "figure.run"
        case .work: return "laptopcomputer"
        case .shortBreak, .longBreak: return "cup.and.saucer.fill"
        }
    }
    
    private func phaseColor(_ phase: TimerPhase) -> Color {
        switch phase {
        case .warmup: return .orange
        case .work: return .red
        case .shortBreak, .longBreak: return .green
        }
    }
    
    private func phaseTitle(_ phase: TimerPhase) -> String {
        switch phase {
        case .warmup: return "Warmup"
        case .work: return "Work"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }
    
    private func timeString(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Lock Screen View

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<TimerAttributes>
    
    var body: some View {
        HStack(spacing: 12) {
            // Left: Phase icon and title
            HStack(spacing: 6) {
                Image(systemName: phaseIcon)
                    .font(.title3)
                    .foregroundColor(phaseColor)
                
                Text(phaseTitle)
                    .font(.headline)
                    .bold()
            }
            
            Spacer()
            
            // Center: Timer
            if context.state.isRunning && !context.state.isPaused {
                Text(timerInterval: context.state.lastUpdateTime...context.state.lastUpdateTime.addingTimeInterval(context.state.timeRemaining), countsDown: true)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text(timeString)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Right: Control buttons
            HStack(spacing: 12) {
                // Skip button
                Link(destination: URL(string: "thomato-timer://skip")!) {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                
                // Pause/Resume button
                Link(destination: URL(string: "thomato-timer://toggle")!) {
                    Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(phaseColor.opacity(0.2))
    }
    
    // MARK: - Computed Properties
    
    private var phaseIcon: String {
        switch context.state.phase {
        case .warmup: return "figure.run"
        case .work: return "laptopcomputer"
        case .shortBreak, .longBreak: return "cup.and.saucer.fill"
        }
    }
    
    private var phaseColor: Color {
        switch context.state.phase {
        case .warmup: return .orange
        case .work: return .red
        case .shortBreak, .longBreak: return .green
        }
    }
    
    private var phaseTitle: String {
        switch context.state.phase {
        case .warmup: return "Warmup"
        case .work: return "Work"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }
    
    private var timeString: String {
        let minutes = Int(context.state.timeRemaining) / 60
        let secs = Int(context.state.timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

#Preview("Notification", as: .content, using: TimerAttributes(
    workDuration: 25,
    breakDuration: 5,
    projectName: "My Project"
)) {
    ThomodoroWidgetLiveActivity()
} contentStates: {
    TimerAttributes.ContentState(
        phase: .work,
        timeRemaining: 1500,
        isRunning: true,
        isPaused: false,
        completedSessions: 2,
        lastUpdateTime: Date()
    )
}
