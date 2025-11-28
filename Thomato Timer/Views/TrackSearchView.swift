//
//  TrackSearchView.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/26.
//

import SwiftUI

struct TrackSearchView: View {
    @Bindable var spotifyManager: SpotifyManager
    @Environment(\.dismiss) var dismiss
    @State private var searchQuery = ""
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Select Warmup Song")
                .font(.title2)
                .bold()
            
            // Search Bar
            TextField("Search for a song...", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .onChange(of: searchQuery) { oldValue, newValue in
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
                        if newValue == searchQuery { // Still the same query
                            await spotifyManager.searchTracks(query: newValue)
                        }
                    }
                }
                .padding(.horizontal)
            
            // Results List
            if !spotifyManager.searchResults.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(spotifyManager.searchResults) { track in
                            Button(action: {
                                spotifyManager.selectedWarmupTrackId = track.id
                                spotifyManager.warmupTrackName = track.displayName
                                spotifyManager.searchResults = []
                                dismiss()
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text(track.artistNames)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle")
                                        .foregroundColor(.green)
                                }
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            } else if !searchQuery.isEmpty {
                VStack {
                    Spacer()
                    Text("No results found")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Search for a song")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            // Cancel Button
            Button("Cancel") {
                spotifyManager.searchResults = []
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding(.bottom)
        }
        .frame(width: 480, height: 400)
    }
}

#Preview {
    TrackSearchView(spotifyManager: SpotifyManager())
}
