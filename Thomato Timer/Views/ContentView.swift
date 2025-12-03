//
//  ContentView.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TimerViewModel()
    @State private var showingSettings = false
    @State private var showingProjectList = false
    @State private var selectedService: MusicService = .none
    @State private var appleMusicManager = AppleMusicManager()
    @State private var showingFirstTimePrompt = false
    
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif
    
    #if os(macOS)
    @StateObject private var menuBarManager = MenuBarManager()
    #endif

    let spotifyManager: SpotifyManager

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
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // TOP HALF - Project Picker + Image
                    VStack(spacing: 16) {
                        // Project Picker + Progress
                        VStack(spacing: 8) {
                            ProjectSwitcherView(viewModel: viewModel)
                            
                            // Progress bar (only if project selected)
                            if let currentProject = viewModel.projectManager.currentProject {
                                ProjectProgressBar(project: currentProject)
                            }
                        }
                        .padding(.horizontal)
                        
                        Spacer()
                        
                        // Image
                        Image(currentImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 250, height: 250)
                            .clipped()
                            .cornerRadius(12)
                            .shadow(radius: 3)
                        
                        Spacer()
                    }
                    .frame(height: geometry.size.height / 2)
                    
                    // BOTTOM HALF - Timer UI
                    VStack(spacing: 16) {
                        Spacer()
                        
                        // Phase Title
                        Text(viewModel.phaseTitle)
                            .font(.title2)
                            .bold()
                        
                        // Timer Display
                        Text(viewModel.displayTime)
                            .font(.system(size: 64, weight: .bold, design: .monospaced))
                        
                        // Slider
                        VStack(spacing: 5) {
                            Slider(
                                value: Binding(
                                    get: {
                                        let maxDur = viewModel.currentPhaseDuration
                                        return maxDur - viewModel.timerState.timeRemaining
                                    },
                                    set: { newValue in
                                        let maxDur = viewModel.currentPhaseDuration
                                        viewModel.timerState.timeRemaining = max(0.1, maxDur - newValue)
                                    }
                                ),
                                in: 0...viewModel.currentPhaseDuration
                            )
                            .tint(.thTeal)
                            
                            HStack {
                                Text("0:00")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(viewModel.displayTime)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 40)
                        
                        // Buttons
                        HStack(spacing: 20) {
                            if viewModel.timerState.isRunning {
                                Button("Skip") { viewModel.skipToNext() }
                                    .buttonStyle(.bordered)
                                    .tint(.thTeal)
                            }
                            
                            Button(viewModel.buttonTitle) {
                                viewModel.toggleTimer()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.thGold)
                            
                            Button("Reset") { viewModel.reset() }
                                .buttonStyle(.bordered)
                                .tint(.thTeal)
                        }
                        .font(.title3)
                        
                        // Checkmarks
                        Text(viewModel.timerState.checkmarks)
                            .font(.title3)
                        
                        Spacer()
                    }
                    .frame(height: geometry.size.height / 2)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("Thomodoro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
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
            .sheet(isPresented: $showingProjectList) {
                ProjectListView()
            }
            .alert("Start Tracking Your Progress", isPresented: $showingFirstTimePrompt) {
                Button("Create Project") {
                    showingProjectList = true
                }
                Button("Skip", role: .cancel) { }
            } message: {
                Text("Create projects and track your progress through milestones: 10h, 30h, 50h, 100h, 500h, 1000h, 2000h. Every session counts!")
            }
            .onAppear {
                setupOnAppear()
            }
            .onChange(of: selectedService) { _, newValue in
                viewModel.selectedService = newValue
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .background {
                    viewModel.handleBackgroundTransition()
                } else if newPhase == .active {
                    viewModel.handleForegroundTransition()
                }
            }
        }
    }
    #endif
    
    // MARK: - macOS Layout
    
    #if os(macOS)
    private var macOSLayout: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
                .ignoresSafeArea()
            
            timerLayoutMac
                .padding(1)
        }
        .frame(width: 700, height: 450)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 12) {
                    Spacer()
                    
                    Group {
                        if let currentProject = viewModel.projectManager.currentProject {
                            ProjectProgressToolbar(project: currentProject)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 180, alignment: .trailing)
                    
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.secondary)
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
        .sheet(isPresented: $showingProjectList) {
            ProjectListView()
        }
        .alert("Start Tracking Your Progress", isPresented: $showingFirstTimePrompt) {
            Button("Create Project") {
                showingProjectList = true
            }
            Button("Skip", role: .cancel) { }
        } message: {
            Text("Create projects and track your progress through milestones: 10h, 30h, 50h, 100h, 500h, 1000h, 2000h. Every session counts!")
        }
        .onAppear {
            setupOnAppear()
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
    
    private var timerLayoutMac: some View {
        HStack(spacing: 0) {
            Spacer()
            
            // LEFT SIDE - PROJECT SWITCHER + IMAGE
            VStack(spacing: 1) {
                ProjectSwitcherView(viewModel: viewModel)
                    .frame(width: 200)
                    .padding(.top, 30)
                
                // Images - adjust each position individually
                ZStack {
                    // Warmup image
                    Image("warmup")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 250)
                        .offset(x: 0, y: -10) // Adjust warmup position here
                        .opacity(viewModel.timerState.currentPhase == .warmup ? 1 : 0)
                    
                    // Work/Tomato image
                    Image("tomato")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 290, height: 370)
                        .offset(x: 0, y: -15) // Adjust tomato position here
                        .opacity(viewModel.timerState.currentPhase == .work ? 1 : 0)
                    
                    // Break image
                    Image("break")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 250)
                        .offset(x: 0, y: -60) // Adjust break position here
                        .opacity(viewModel.timerState.currentPhase == .shortBreak || viewModel.timerState.currentPhase == .longBreak ? 1 : 0)
                }
                .shadow(radius: 3)
                
            Spacer()
            }
            .frame(width: 300)
            
            
            // RIGHT TIMER PANEL
            VStack(spacing: 20) {
                Text(viewModel.phaseTitle)
                    .font(.title)
                    .bold()
                    .foregroundColor(.primary)
                
                Text(viewModel.displayTime)
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                
                VStack(spacing: 5) {
                    Slider(
                        value: Binding(
                            get: {
                                let maxDur = viewModel.currentPhaseDuration
                                return maxDur - viewModel.timerState.timeRemaining
                            },
                            set: { newValue in
                                let maxDur = viewModel.currentPhaseDuration
                                viewModel.timerState.timeRemaining = max(0.1, maxDur - newValue)
                            }
                        ),
                        in: 0...viewModel.currentPhaseDuration
                    )
                    .frame(width: 300)
                    .tint(.thTeal)
                    
                    HStack {
                        Text("0:00")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(viewModel.displayTime)
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                    .foregroundColor(.primary)
            }
            .frame(width: 320)
            
            Spacer()
                .frame(width: 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif
    
    // MARK: - Shared
    
    private func setupOnAppear() {
        viewModel.spotifyManager = spotifyManager
        viewModel.appleMusicManager = appleMusicManager
        viewModel.selectedService = selectedService
        
        if ProjectManager.shared.projects.isEmpty &&
            StatisticsManager.shared.sessions.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingFirstTimePrompt = true
            }
        }
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

// MARK: - iOS Progress Bar (inline)

#if os(iOS)
struct ProjectProgressBar: View {
    let project: Project
    var statsManager = StatisticsManager.shared
    
    var body: some View {
        let totalHours = Int(statsManager.totalHoursForProject(project.id))
        let nextMilestone = Milestone.nextMilestone(for: totalHours)
        let targetHours = nextMilestone?.hours ?? 2000
        let progress = Double(totalHours) / Double(targetHours)
        
        HStack(spacing: 12) {
            Text(project.displayName)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * min(progress, 1.0), height: 8)
                }
            }
            .frame(height: 8)
            
            Text("\(totalHours)h/\(targetHours)h")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
#endif

// MARK: - macOS Toolbar Progress View

#if os(macOS)
struct ProjectProgressToolbar: View {
    let project: Project
    @State private var statsManager = StatisticsManager.shared

    var body: some View {
        let totalHours = Int(statsManager.totalHoursForProject(project.id))
        let nextMilestone = Milestone.nextMilestone(for: totalHours)
        let targetHours = nextMilestone?.hours ?? 2000
        let progress = Double(totalHours) / Double(targetHours)

        HStack(spacing: 8) {
            Text(project.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 80, alignment: .trailing)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 6)

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.blue)
                    .frame(width: 60 * min(progress, 1.0), height: 6)
            }

            Text("\(totalHours)h/\(targetHours)h")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(width: 55, alignment: .leading)
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    ContentView(spotifyManager: SpotifyManager())
}
