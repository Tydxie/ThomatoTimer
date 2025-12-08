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
    
    // MARK: - Artwork URL Helper
    
    private var currentArtworkURL: URL? {
        switch selectedService {
        case .appleMusic:
            return appleMusicManager.currentArtworkURL
        case .spotify:
            return spotifyManager.currentArtworkURL
        case .none:
            return nil
        }
    }
    
    private var isMusicPlaying: Bool {
        switch selectedService {
        case .appleMusic:
            return appleMusicManager.isPlaying
        case .spotify:
            return spotifyManager.isPlaying
        case .none:
            return false
        }
    }
    
    // MARK: - iOS Layout
    
    #if os(iOS)
    private var iOSLayout: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // TOP HALF - Project Picker + Image
                    VStack(spacing: 16) {
                        // Project Picker
                        ProjectSwitcherView(viewModel: viewModel)
                            .padding(.horizontal)
                        
                        Spacer()
                        
                        // Image - show album artwork if playing, otherwise phase image
                        artworkImageView
                            .frame(width: 250, height: 250)
                            .cornerRadius(8)  // Spotify guideline: 8px for large devices
                            .shadow(radius: 3)
                        
                        // Spotify attribution (required by design guidelines)
                        if selectedService == .spotify && isMusicPlaying {
                            spotifyAttribution
                        }
                        
                        Spacer()
                    }
                    .frame(height: geometry.size.height / 2)
                    
                    // BOTTOM HALF - Timer UI
                    VStack(spacing: 16) {
                        
                        
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
            Text("Start Tracking Your Progress", comment: "Alert explaining project milestones")
        }
        .onAppear {
            setupOnAppear()
            
            // 🔹 NEW: pass managers into MenuBarManager so it can build the popover
            menuBarManager.setup(
                viewModel: viewModel,
                spotifyManager: spotifyManager,
                appleMusicManager: appleMusicManager
            )
            
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
                
                // Images - show album artwork if playing, otherwise phase images
                ZStack {
                    if let artworkURL = currentArtworkURL, isMusicPlaying {
                        // Album artwork from music service
                        VStack(spacing: 8) {
                            AsyncImage(url: artworkURL) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                            } placeholder: {
                                // Show phase image while loading
                                phaseImageMac
                            }
                            .frame(width: 220, height: 220)
                            .cornerRadius(8)  // Spotify guideline: 8px for large devices
                            
                            // Spotify attribution (required by design guidelines)
                            if selectedService == .spotify {
                                spotifyAttribution
                            }
                        }
                        .offset(y: 30)
                    } else {
                        // Default phase images
                        phaseImageMac
                    }
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
    
    // MARK: - macOS Phase Images
    
    @ViewBuilder
    private var phaseImageMac: some View {
        ZStack {
            // Warmup image
            Image("warmup")
                .resizable()
                .scaledToFit()
                .frame(width: 350, height: 250)
                .offset(x: 0, y: -10)
                .opacity(viewModel.timerState.currentPhase == .warmup ? 1 : 0)
            
            // Work/Tomato image
            Image("tomato")
                .resizable()
                .scaledToFit()
                .frame(width: 290, height: 370)
                .offset(x: 0, y: -15)
                .opacity(viewModel.timerState.currentPhase == .work ? 1 : 0)
            
            // Break image
            Image("break")
                .resizable()
                .scaledToFit()
                .frame(width: 250, height: 250)
                .offset(x: 0, y: -60)
                .opacity(viewModel.timerState.currentPhase == .shortBreak || viewModel.timerState.currentPhase == .longBreak ? 1 : 0)
        }
    }
    #endif
    
    // MARK: - Spotify Attribution (required by design guidelines)
    
    private var spotifyAttribution: some View {
        Button {
            openInSpotify()
        } label: {
            HStack(spacing: 6) {
                // Spotify icon (green circle with sound waves)
                Image(systemName: "music.note")
                    .foregroundColor(.green)
                    .font(.caption)
                
                VStack(alignment: .leading, spacing: 1) {
                    if let trackName = spotifyManager.currentTrackName {
                        Text(trackName)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                    }
                    Text("Play on Spotify")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    private func openInSpotify() {
        guard let urlString = spotifyManager.currentTrackSpotifyURL,
              let url = URL(string: urlString) else { return }
        
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
    
    // MARK: - Shared Artwork View (iOS)
    
    @ViewBuilder
    private var artworkImageView: some View {
        if let artworkURL = currentArtworkURL, isMusicPlaying {
            // Album artwork from music service
            AsyncImage(url: artworkURL) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } placeholder: {
                // Show phase image while loading
                Image(currentImage)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            }
        } else {
            // Default phase image
            Image(currentImage)
                .resizable()
                .scaledToFill()
                .clipped()
        }
    }
    
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
