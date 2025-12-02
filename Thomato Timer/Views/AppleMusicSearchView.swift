//
//  AppleMusicSearchView.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/12/01.
//

import SwiftUI

struct AppleMusicSearchView: View {
    @Bindable var appleMusicManager: AppleMusicManager
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
                            await appleMusicManager.searchSongs(query: newValue)
                        }
                    }
                }
                .padding(.horizontal)
            
            // Results List
            if !appleMusicManager.searchResults.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(appleMusicManager.searchResults) { song in
                            Button(action: {
                                appleMusicManager.selectedWarmupSongId = song.id
                                appleMusicManager.warmupSongName = song.displayName
                                appleMusicManager.searchResults = []
                                dismiss()
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(song.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text(song.artistName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle")
                                        .foregroundColor(.red)
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
                appleMusicManager.searchResults = []
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding(.bottom)
        }
        .frame(width: 480, height: 400)
    }
}

#Preview {
    AppleMusicSearchView(appleMusicManager: AppleMusicManager())
}
