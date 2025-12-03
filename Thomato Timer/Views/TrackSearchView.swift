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
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        #if os(iOS)
        iOSLayout
        #else
        macOSLayout
        #endif
    }
    
    private func performSearch(_ query: String) {
        // Cancel previous search
        searchTask?.cancel()
        
        // Start new debounced search
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s debounce
            
            guard !Task.isCancelled else { return }
            
            await spotifyManager.searchTracks(query: query)
        }
    }
    
    // MARK: - iOS Layout
    
    #if os(iOS)
    private var iOSLayout: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                TextField("Search for a song...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .onChange(of: searchQuery) { oldValue, newValue in
                        performSearch(newValue)
                    }
                
                // Results
                searchResultsView
            }
            .navigationTitle("Select Warmup Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        spotifyManager.searchResults = []
                        dismiss()
                    }
                }
            }
        }
    }
    #endif
    
    // MARK: - macOS Layout
    
    #if os(macOS)
    private var macOSLayout: some View {
        VStack(spacing: 15) {
            Text("Select Warmup Song")
                .font(.title2)
                .bold()
            
            // Search Bar
            TextField("Search for a song...", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .onChange(of: searchQuery) { oldValue, newValue in
                    performSearch(newValue)
                }
                .padding(.horizontal)
            
            // Results
            searchResultsView
            
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
    #endif
    
    // MARK: - Shared Results View
    
    @ViewBuilder
    private var searchResultsView: some View {
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
    }
}

#Preview {
    TrackSearchView(spotifyManager: SpotifyManager())
}
