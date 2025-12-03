//
//  AppleMusicSearchView.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/12/01.
//

import SwiftUI
import MusicKit

struct AppleMusicSearchView: View {
    var appleMusicManager: AppleMusicManager
    @Environment(\.dismiss) var dismiss
    @State private var searchQuery = ""
    @State private var searchResults: [AppleMusicSongItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        #if os(iOS)
        iOSLayout
        #else
        macOSLayout
        #endif
    }
    
    private func performSearch(_ query: String) {
        searchTask?.cancel()
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            
            await MainActor.run { isSearching = true }
            
            do {
                var request = MusicCatalogSearchRequest(term: trimmed, types: [Song.self])
                request.limit = 20
                let response = try await request.response()
                
                guard !Task.isCancelled else { return }
                
                let items = response.songs.map { song in
                    AppleMusicSongItem(
                        id: song.id.rawValue,
                        name: song.title,
                        artistName: song.artistName,
                        albumName: song.albumTitle ?? ""
                    )
                }
                
                await MainActor.run {
                    searchResults = items
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }
    
    private func selectSong(_ song: AppleMusicSongItem) {
        appleMusicManager.selectedWarmupSongId = song.id
        appleMusicManager.warmupSongName = song.displayName
        dismiss()
    }
    
    // MARK: - iOS Layout
    
    #if os(iOS)
    private var iOSLayout: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search for a song...", text: $searchQuery)
                        .autocorrectionDisabled()
                        .onChange(of: searchQuery) { _, newValue in
                            performSearch(newValue)
                        }
                }
                
                if isSearching {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else if !searchResults.isEmpty {
                    Section("Results") {
                        ForEach(searchResults) { song in
                            Button(action: { selectSong(song) }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(song.name)
                                        .foregroundColor(.primary)
                                    Text(song.artistName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } else if !searchQuery.isEmpty {
                    Section {
                        Text("No results found")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Select Warmup Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        searchTask?.cancel()
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
            
            TextField("Search for a song...", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .onChange(of: searchQuery) { _, newValue in
                    performSearch(newValue)
                }
                .padding(.horizontal)
            
            searchResultsView
            
            Button("Cancel") {
                searchTask?.cancel()
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding(.bottom)
        }
        .frame(width: 480, height: 400)
    }
    
    @ViewBuilder
    private var searchResultsView: some View {
        if isSearching {
            VStack {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            }
        } else if !searchResults.isEmpty {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(searchResults) { song in
                        Button(action: { selectSong(song) }) {
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
    }
    #endif
}

#Preview {
    AppleMusicSearchView(appleMusicManager: AppleMusicManager())
}
