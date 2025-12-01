//
//  ContentView.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TimerViewModel()
    @StateObject private var menuBarManager = MenuBarManager()
    @State private var showingSettings = false
    @State private var selectedService: MusicService = .none
    @State private var appleMusicManager = AppleMusicManager()
    @State private var showingFirstTimePrompt = false

    let spotifyManager: SpotifyManager

    var body: some View {
        ZStack {
            // Full-window background
            Color.thWhite
                .ignoresSafeArea()

            // Main content
            timerLayout
                .padding(40)
        }
        .frame(width: 700, height: 500)  // FIXED SIZE - no resizing
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 12) {
                    Spacer()
                    
                    // Progress bar in fixed-width container (or empty space)
                    Group {
                        if let currentProject = viewModel.projectManager.currentProject {
                            ProjectProgressToolbar(project: currentProject)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 180, alignment: .trailing)
                    
                    // Gear icon - always in same position
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.thBlack)
                    }
                }
                .frame(width: 400, alignment: .trailing)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                viewModel: viewModel,
                spotifyManager: spotifyManager,
                appleMusicManager: appleMusicManager,
                selectedService: $selectedService
            )
        }
        .alert("Start Tracking Your Progress", isPresented: $showingFirstTimePrompt) {
            Button("Create Project") { }
            Button("Skip", role: .cancel) { }
        } message: {
            Text("Create projects and track your progress through milestones: 10h, 30h, 50h, 100h, 500h, 1000h, 2000h. Every session counts!")
        }
        .onAppear {
            viewModel.spotifyManager = spotifyManager
            viewModel.appleMusicManager = appleMusicManager
            viewModel.selectedService = selectedService

            if ProjectManager.shared.projects.isEmpty &&
                StatisticsManager.shared.sessions.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingFirstTimePrompt = true
                }
            }

            menuBarManager.setup(viewModel: viewModel)

            NotificationCenter.default.addObserver(
                forName: .toggleTimer,
                object: nil,
                queue: .main
            ) { _ in viewModel.toggleTimer() }

            NotificationCenter.default.addObserver(
                forName: .resetTimer,
                object: nil,
                queue: .main
            ) { _ in viewModel.reset() }

            NotificationCenter.default.addObserver(
                forName: .skipTimer,
                object: nil,
                queue: .main
            ) { _ in
                if viewModel.timerState.isRunning {
                    viewModel.skipToNext()
                }
            }
        }
        .onChange(of: selectedService) { _, newValue in
            viewModel.selectedService = newValue
        }
    }

    // MARK: - MAIN TIMER LAYOUT (unchanged)

    private var timerLayout: some View {
        HStack(spacing: 0) {

            // LEFT SPACER
            Spacer()

            // LEFT SIDE - PROJECT SWITCHER + IMAGE
            VStack(spacing: 12) {
                ProjectSwitcherView(viewModel: viewModel)
                    .frame(width: 200)

                Image(currentImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 350, height: 350)
                    .shadow(radius: 3)
            }
            .frame(width: 350)

            // MIDDLE SPACER
            Spacer()
                .frame(width: 15)

            // RIGHT TIMER PANEL
            VStack(spacing: 20) {

                Text(viewModel.phaseTitle)
                    .font(.title)
                    .bold()
                    .foregroundColor(.thBlack)

                Text(viewModel.displayTime)
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundColor(.thBlack)

                VStack(spacing: 5) {
                    Slider(
                        value: Binding(
                            get: {
                                let maxDur = viewModel.currentPhaseDuration
                                return maxDur - viewModel.timerState.timeRemaining
                            },
                            set: { newValue in
                                let maxDur = viewModel.currentPhaseDuration
                                viewModel.timerState.timeRemaining =
                                    max(0.1, maxDur - newValue)
                            }
                        ),
                        in: 0...viewModel.currentPhaseDuration
                    )
                    .frame(width: 300)
                    .tint(.thTeal)

                    HStack {
                        Text("0:00")
                            .font(.caption)
                            .foregroundColor(.thBlack)
                        Spacer()
                        Text(viewModel.displayTime)
                            .font(.caption)
                            .foregroundColor(.thBlack)
                    }
                    .frame(width: 300)
                }

                HStack(spacing: 20) {

                    if viewModel.timerState.isRunning {
                        Button("Skip") { viewModel.skipToNext() }
                            .buttonStyle(.bordered)
                            .tint(.thTeal)
                            .foregroundColor(.thBlack)
                    }

                    Button(viewModel.buttonTitle) {
                        viewModel.toggleTimer()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.thGold)
                    .foregroundColor(.thBlack)

                    Button("Reset") { viewModel.reset() }
                        .buttonStyle(.bordered)
                        .tint(.thTeal)
                        .foregroundColor(.thBlack)
                }
                .font(.title2)

                Text(viewModel.timerState.checkmarks)
                    .font(.title3)
                    .foregroundColor(.thBlack)
            }
            .frame(width: 320)

            Spacer()
                .frame(width: 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentImage: String {
        switch viewModel.timerState.currentPhase {
        case .warmup:
            return "warmup"
        case .work:
            return "tomato"
        case .shortBreak, .longBreak:
            return "break"
        }
    }
}

#Preview {
    ContentView(spotifyManager: SpotifyManager())
}

// MARK: - Toolbar Progress View

struct ProjectProgressToolbar: View {
    let project: Project
    @State private var statsManager = StatisticsManager.shared

    var body: some View {
        let totalHours = Int(statsManager.totalHoursForProject(project.id))
        let nextMilestone = Milestone.nextMilestone(for: totalHours)
        let targetHours = nextMilestone?.hours ?? 2000
        let progress = Double(totalHours) / Double(targetHours)

        HStack(spacing: 8) {
            // Project name - fixed width, truncates if too long
            Text(project.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 80, alignment: .trailing)

            // Progress bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 6)

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.blue)
                    .frame(width: 60 * min(progress, 1.0), height: 6)
            }

            // Hours progress - fixed width
            Text("\(totalHours)h/\(targetHours)h")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(width: 55, alignment: .leading)
        }
    }
}
