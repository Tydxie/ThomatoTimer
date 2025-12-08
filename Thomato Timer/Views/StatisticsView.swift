//
//  StatisticsView.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/26.
//

import SwiftUI

struct StatisticsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var statsManager = StatisticsManager.shared
    @State private var projectManager = ProjectManager.shared
    
    var body: some View {
        #if os(iOS)
        iOSLayout
        #else
        macOSLayout
        #endif
    }
    
    // MARK: - iOS Layout
    
    #if os(iOS)
    private var iOSLayout: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // TODAY Section
                    TodayStatsCard()
                    
                    // ALL TIME Section
                    AllTimeStatsCard()
                    
                    // Member since
                    if let firstUse = statsManager.firstUseDate {
                        Text("Member since \(firstUse.formatted(date: .long, time: .omitted))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.top, 10)
                            .padding(.bottom, 20)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    #endif
    
    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        VStack(spacing: 0) {
            // Top bar (title + Done)
            HStack {
                Text("Statistics")
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.cancelAction) // Esc closes the sheet as well
            }
            .padding([.top, .horizontal])
            .padding(.bottom, 8)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // TODAY Section
                    TodayStatsCard()
                    
                    // ALL TIME Section
                    AllTimeStatsCard()
                    
                    // Member since
                    if let firstUse = statsManager.firstUseDate {
                        Text("Member since \(firstUse.formatted(date: .long, time: .omitted))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.top, 10)
                            .padding(.bottom, 20)
                    }
                }
                .padding(.horizontal, 1)
                .padding(.top, 20)
            }
            .frame(width: 380, height: 520)
        }
    }
    #endif
}

// MARK: - TODAY Card

struct TodayStatsCard: View {
    @State private var statsManager = StatisticsManager.shared
    @State private var projectManager = ProjectManager.shared
    
    var body: some View {
        GroupBox {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Label("Today", systemImage: "calendar")
                        .font(.headline)
                    Spacer()
                    let stats = statsManager.stats(for: .today)
                    Text(stats.formattedWorkTime)
                        .font(.title2)
                        .bold()
                        .foregroundColor(.primary)
                }
                
                Divider()
                
                // Project breakdown
                let breakdown = statsManager.projectBreakdown(for: .today)
                let unassignedMinutes = statsManager.unassignedMinutes(for: .today)
                
                if breakdown.isEmpty && unassignedMinutes == 0 {
                    HStack {
                        Image(systemName: "moon.zzz")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No sessions today")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    VStack(spacing: 12) {
                        // Sort projects by time
                        ForEach(Array(breakdown.keys.sorted(by: { breakdown[$0]! > breakdown[$1]! })), id: \.self) { projectId in
                            if let project = projectManager.projects.first(where: { $0.id == projectId }),
                               let minutes = breakdown[projectId] {
                                TodayProjectRow(
                                    projectName: project.displayName,
                                    minutes: minutes
                                )
                            }
                        }
                        
                        // Unassigned sessions
                        if unassignedMinutes > 0 {
                            TodayProjectRow(
                                projectName: "Freestyle",
                                minutes: unassignedMinutes
                            )
                        }
                    }
                }
            }
            .padding(4)
        }
    }
}

struct TodayProjectRow: View {
    let projectName: String
    let minutes: Int
    
    var body: some View {
        HStack {
            Text(projectName)
                .font(.body)
            Spacer()
            let hours = minutes / 60
            let mins = minutes % 60
            Text(hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m")
                .font(.body)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ALL TIME Card

struct AllTimeStatsCard: View {
    @State private var statsManager = StatisticsManager.shared
    @State private var projectManager = ProjectManager.shared
    
    var body: some View {
        GroupBox {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Label("All Time", systemImage: "chart.bar.fill")
                        .font(.headline)
                    Spacer()
                    let stats = statsManager.stats(for: .allTime)
                    Text(stats.formattedWorkTime)
                        .font(.title2)
                        .bold()
                        .foregroundColor(.primary)
                }
                
                Divider()
                
                // Project breakdown with progress
                let breakdown = statsManager.projectBreakdown(for: .allTime)
                let unassignedMinutes = statsManager.unassignedMinutes(for: .allTime)
                
                if breakdown.isEmpty && unassignedMinutes == 0 {
                    HStack {
                        Image(systemName: "tray")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No sessions recorded")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    VStack(spacing: 20) {
                        // Sort projects by time
                        ForEach(Array(breakdown.keys.sorted(by: { breakdown[$0]! > breakdown[$1]! })), id: \.self) { projectId in
                            if let project = projectManager.projects.first(where: { $0.id == projectId }),
                               let minutes = breakdown[projectId] {
                                AllTimeProjectCard(
                                    project: project,
                                    minutes: minutes
                                )
                            }
                        }
                        
                        // Unassigned sessions (no progress bar)
                        if unassignedMinutes > 0 {
                            AllTimeUnassignedCard(minutes: unassignedMinutes)
                        }
                    }
                }
            }
            .padding(4)
        }
    }
}

struct AllTimeProjectCard: View {
    let project: Project
    let minutes: Int
    
    var body: some View {
        let totalHours = Int(Double(minutes) / 60.0)
        let current = Milestone.currentMilestone(for: totalHours)
        
        VStack(alignment: .leading, spacing: 10) {
            // Project name and current level
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.displayName)
                        .font(.body)
                        .bold()
                    
                    // Current level badge
                    HStack(spacing: 4) {
                        Text(current.emoji)
                            .font(.caption)
                        Text(current.title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                    
                    let hours = minutes / 60
                    let mins = minutes % 60
                    Text(hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                
                Spacer()
            }
            
            // Progress to next milestone
            if let next = Milestone.nextMilestone(for: totalHours) {
                let progress = Double(totalHours) / Double(next.hours)
                
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 8)
                            
                            // Progress
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.blue.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * min(progress, 1.0), height: 8)
                        }
                    }
                    .frame(height: 8)
                    
                    // Next milestone info
                    HStack {
                        Text("Next: \(next.emoji) \(next.title)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(next.hours - totalHours)h to go")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // Completed all milestones
                HStack {
                    Text("🎉 All milestones completed!")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
}

struct AllTimeUnassignedCard: View {
    let minutes: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Freestyle")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                let hours = minutes / 60
                let mins = minutes % 60
                Text(hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

#Preview {
    StatisticsView()
}
