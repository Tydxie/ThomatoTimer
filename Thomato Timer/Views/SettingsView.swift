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
    @State private var showingTrackSearch = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Settings")
                    .font(.title2)
                    .bold()
                
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
                        HStack {
                            Text("Service:")
                                .frame(width: 180, alignment: .leading)
                            
                            Picker("", selection: .constant("Spotify")) {
                                Text("None").tag("None")
                                Text("Spotify").tag("Spotify")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }
                        
                        Divider()
                        
                        // Spotify Connection
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
                                            spotifyManager.accessToken = nil
                                            spotifyManager.refreshToken = nil
                                            spotifyManager.isAuthenticated = false
                                            spotifyManager.playlists = []
                                            spotifyManager.selectedWorkPlaylistId = nil
                                            spotifyManager.selectedBreakPlaylistId = nil
                                            spotifyManager.selectedWarmupTrackId = nil
                                            spotifyManager.warmupTrackName = nil
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
                    .padding(.vertical, 10)
                }
            }
            .padding()
        }
        .frame(width: 480, height: 400)
        .sheet(isPresented: $showingTrackSearch) {
            TrackSearchView(spotifyManager: spotifyManager)
        }
    }
}

#Preview {
    SettingsView(viewModel: TimerViewModel(), spotifyManager: SpotifyManager())
}
