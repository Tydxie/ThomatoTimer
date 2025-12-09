//
//  MacMenuPopoverView.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/12/07.
//

#if os(macOS)
import SwiftUI

// MARK: - Shared popover size for ALL macOS sheets & dropdowns
enum MacPopoverLayout {
    static let width: CGFloat = 380    // EDIT THIS to test width
    static let height: CGFloat = 600   // EDIT THIS to test height
}

struct MacMenuPopoverView: View {
    @ObservedObject var viewModel: TimerViewModel
    let spotifyManager: SpotifyManager
    let appleMusicManager: AppleMusicManager
    
    @State private var selectedService: MusicService = .none
    @State private var showingSettings = false
    @State private var showingProjectList = false
    
    // MARK: - Computed helpers
    
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
    
    private var currentImage: String {
        switch viewModel.timerState.currentPhase {
        case .warmup: return "warmup"
        case .work: return "tomato"
        case .shortBreak, .longBreak: return "break"
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            
            
            VStack(spacing: 16) {
                
                // Project switcher
                ProjectSwitcherView(viewModel: viewModel)
                    .padding(.top, 8)
                    .padding(.horizontal)
                
                // Artwork / phase image + Spotify attribution
                VStack(spacing: 8) {
                    artworkImageView
                        .frame(width: 200, height: 200)
                        .cornerRadius(8)
                        .shadow(radius: 3)
                    
                    if selectedService == .spotify && isMusicPlaying {
                        spotifyAttribution
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                
                // Timer title
                Text(viewModel.phaseTitle)
                    .font(.title2)
                    .bold()
                    .padding(.top, 30)
                
                // Timer value
                Text(viewModel.displayTime)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                
                // Slider
                VStack(spacing: 4) {
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
                    .padding(.horizontal, 40)
                    
                    HStack {
                        Text("0:00").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(viewModel.displayTime)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 40)
                }
                
                // Buttons
                HStack(spacing: 16) {
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
                    .tint(.thomodoroGold)
                    .foregroundColor(.thBlack)
                    
                    Button("Reset") { viewModel.reset() }
                        .buttonStyle(.bordered)
                        .tint(.thTeal)
                        .foregroundColor(.thBlack)
                }
                .font(.title3)
                .padding(.top, 4)
                
                // Checkmarks
                Text(viewModel.timerState.checkmarks)
                    .font(.title3)
                    .padding(.top, 4)
                
                Spacer(minLength: 8)
            }
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // MARK: - Fixed dropdown size
        .frame(width: MacPopoverLayout.width,
               height: MacPopoverLayout.height)
        
        // MARK: - Blur material
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(4)
        
        .tint(.thTeal)
        
        .onAppear { selectedService = viewModel.selectedService }
        .onChange(of: selectedService) { _, newValue in
            viewModel.selectedService = newValue
        }
        
        // MARK: - Sheets
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
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 8) {
            if let currentProject = viewModel.projectManager.currentProject {
                ProjectProgressToolbar(project: currentProject)
            } else {
                Spacer()
            }
            
            Spacer()
            
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.95)
        )
    }
    
    // MARK: - Artwork
    
    @ViewBuilder
    private var artworkImageView: some View {
        if let artworkURL = currentArtworkURL, isMusicPlaying {
            AsyncImage(url: artworkURL) { image in
                image.resizable().scaledToFill().clipped()
            } placeholder: {
                Image(currentImage).resizable().scaledToFill().clipped()
            }
        } else {
            Image(currentImage)
                .resizable()
                .scaledToFill()
                .clipped()
        }
    }
    
    // MARK: - Spotify Attribution
    
    private var spotifyAttribution: some View {
        Button { openInSpotify() } label: {
            HStack(spacing: 6) {
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
        NSWorkspace.shared.open(url)
    }
}

#endif
