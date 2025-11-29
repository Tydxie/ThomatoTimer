//
//  SettingsView.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/24.
//

import SwiftUI

struct SettingsView: View {
    
    @ObservedObject var viewModel: TimerViewModel
    @Bindable var spotifyManager: SpotifyManager
    @Bindable var appleMusicManager: AppleMusicManager
    @Binding var selectedService: MusicService
    @State private var showingTrackSearch = false
    @State private var showingStats = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Text("Settings")
                        .font(.title2)
                        .bold()
                    
                    Spacer()
                    
                    Button("View Statistics") {
                        showingStats = true
                    }
                    .buttonStyle(.bordered)
                }
                
                // Timer Settings Section
                GroupBox(label: Label("Timer Settings", systemImage: "clock")) {
                    VStack(spacing: 15) {
                        HStack {
                            Text("Work Session (Mins):")
                                .frame(width: 180, alignment: .leading)
                            TextField("Minutes", value: $viewModel.timerState.workDuration, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                        }
                        
                        HStack {
                            Text("Short Break (Mins):")
                                .frame(width: 180, alignment: .leading)
                            TextField("Minutes", value: $viewModel.timerState.shortBreakDuration, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                        }
                        
                        HStack {
                            Text("Long Break (Mins):")
                                .frame(width: 180, alignment: .leading)
                            TextField("Minutes", value: $viewModel.timerState.longBreakDuration, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                        }
                        
                        HStack {
                            Text("Warmup Duration:")
                                .frame(width: 180, alignment: .leading)
                            Picker(selection: $viewModel.timerState.warmupDuration, label: Text("")) {
                                Text("5 min").tag(5)
                                Text("10 min").tag(10)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }
                    }
                    .padding(.vertical, 10)
                }
                
                // Music Integration Section
                GroupBox(label: Label("Music Integration", systemImage: "music.note")) {
                    VStack(spacing: 15) {
                        // SERVICE PICKER
                        HStack {
                            Text("Service:")
                                .frame(width: 180, alignment: .leading)
                            
                            Picker("", selection: $selectedService) {
                                ForEach(MusicService.allCases) { service in
                                    Text(service.rawValue).tag(service)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }
                        
                        Divider()
                        
                        // CONDITIONAL SECTIONS BASED ON SERVICE
                        if selectedService == .spotify {
                            spotifySection()
                        } else if selectedService == .appleMusic {
                            appleMusicSection()
                        } else {
                            Text("No music service selected")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding()
        }
        .frame(width: 480, height: 400)
        .sheet(isPresented: $showingTrackSearch) {
            TrackSearchView(spotifyManager: spotifyManager)
        }
        .sheet(isPresented: $showingStats) {
            StatisticsView()
        }
    }
    
    // SPOTIFY SECTION
    @ViewBuilder
    private func spotifySection() -> some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "music.note.list")
                    .foregroundColor(.green)
                Text("Spotify")
                    .font(.headline)
                Spacer()
                
                if spotifyManager.isAuthenticated {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            
            if !spotifyManager.isAuthenticated {
                Button("Connect to Spotify") {
                    spotifyManager.authenticate()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else {
                VStack(spacing: 10) {
                    // Playlist Pickers
                    if !spotifyManager.playlists.isEmpty {
                        VStack(spacing: 8) {
                            // Work Playlist
                            HStack {
                                Text("Work Playlist:")
                                    .frame(width: 120, alignment: .leading)
                                
                                Picker("", selection: $spotifyManager.selectedWorkPlaylistId) {
                                    Text("None").tag(nil as String?)
                                    ForEach(spotifyManager.playlists) { playlist in
                                        Text(playlist.name).tag(playlist.id as String?)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            
                            // Break Playlist
                            HStack {
                                Text("Break Playlist:")
                                    .frame(width: 120, alignment: .leading)
                                
                                Picker("", selection: $spotifyManager.selectedBreakPlaylistId) {
                                    Text("None").tag(nil as String?)
                                    ForEach(spotifyManager.playlists) { playlist in
                                        Text(playlist.name).tag(playlist.id as String?)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            
                            // Warmup Song
                            HStack {
                                Text("Warmup Song:")
                                    .frame(width: 120, alignment: .leading)
                                
                                if let trackName = spotifyManager.warmupTrackName {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(trackName)
                                            .lineLimit(1)
                                            .font(.caption)
                                    }
                                    Spacer()
                                    Button("Change") {
                                        showingTrackSearch = true
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                } else {
                                    Text("None selected")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                    Spacer()
                                    Button("Select Song") {
                                        showingTrackSearch = true
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    } else {
                        Button("Load Playlists") {
                            Task {
                                await spotifyManager.fetchPlaylists()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack(spacing: 10) {
                        Button("Disconnect") {
                            Task {
                                // Pause music first (while we still have credentials)
                                await spotifyManager.pausePlayback()
                                print("🎵 Music pause command sent")
                                
                                // Wait a moment for command to process
                                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                                
                                // Now clear credentials
                                await MainActor.run {
                                    spotifyManager.accessToken = nil
                                    spotifyManager.refreshToken = nil
                                    spotifyManager.isAuthenticated = false
                                    spotifyManager.playlists = []
                                    spotifyManager.selectedWorkPlaylistId = nil
                                    spotifyManager.selectedBreakPlaylistId = nil
                                    spotifyManager.selectedWarmupTrackId = nil
                                    spotifyManager.warmupTrackName = nil
                                    
                                    print("🎵 Spotify disconnected")
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Refresh Token") {
                            Task {
                                await spotifyManager.refreshAccessToken()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if let expirationDate = spotifyManager.tokenExpirationDate {
                        Text("Token expires: \(expirationDate, style: .relative)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let error = spotifyManager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // APPLE MUSIC SECTION
    @ViewBuilder
    private func appleMusicSection() -> some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "music.note")
                    .foregroundColor(.red)
                Text("Apple Music")
                    .font(.headline)
                Spacer()
                
                if appleMusicManager.isAuthorized {
                    Label("Authorized", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            
            if !appleMusicManager.isAuthorized {
                Button("Authorize Apple Music") {
                    Task {
                        await appleMusicManager.requestAuthorization()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                
                Text("Requires Apple Music subscription")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Text("Warmup Song ID:")
                            .frame(width: 120, alignment: .leading)
                        TextField("Apple Music Song ID", text: $appleMusicManager.warmupSongId)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                    
                    HStack {
                        Text("Work Playlist ID:")
                            .frame(width: 120, alignment: .leading)
                        TextField("Apple Music Playlist ID", text: $appleMusicManager.workPlaylistId)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                    
                    HStack {
                        Text("Break Playlist ID:")
                            .frame(width: 120, alignment: .leading)
                        TextField("Apple Music Playlist ID", text: $appleMusicManager.breakPlaylistId)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                }
                
                Text("Find IDs in Apple Music URLs")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 5)
            }
            
            if let error = appleMusicManager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

#Preview {
    SettingsView(
        viewModel: TimerViewModel(),
        spotifyManager: SpotifyManager(),
        appleMusicManager: AppleMusicManager(),
        selectedService: .constant(.none)
    )
}
