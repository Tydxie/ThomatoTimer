//
//  AppleMusicManager.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/26.
//

import Foundation
import MusicKit
import Observation

// Simple playlist model for picker
struct AppleMusicPlaylistItem: Identifiable, Hashable {
    let id: String
    let name: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: AppleMusicPlaylistItem, rhs: AppleMusicPlaylistItem) -> Bool {
        lhs.id == rhs.id
    }
}

// Simple song model for search results
struct AppleMusicSongItem: Identifiable {
    let id: String
    let name: String
    let artistName: String
    let albumName: String
    let artworkURL: URL?
    
    var displayName: String {
        "\(name) - \(artistName)"
    }
}

@Observable
final class AppleMusicManager {
    var isAuthorized = false
    
    // Selected IDs
    var selectedWarmupSongId: String?
    var selectedWorkPlaylistId: String?
    var selectedBreakPlaylistId: String?
    
    // Display names
    var warmupSongName: String?
    var workPlaylistName: String?
    var breakPlaylistName: String?
    
    // User's playlists from library (store full playlist for playback)
    var playlists: [AppleMusicPlaylistItem] = []
    private var libraryPlaylists: [Playlist] = []
    
    // Search results for songs
    var searchResults: [AppleMusicSongItem] = []
    
    var errorMessage: String?
    
    // MARK: - Current Playback Artwork
    var currentArtworkURL: URL?
    var isPlaying = false
    
    // MARK: - Artwork Size (platform-specific)
    #if os(iOS)
    private let artworkSize = 1024
    #else
    private let artworkSize = 1024
    #endif
    
    // MARK: - Warmup (call this to pre-initialize MusicKit)
    
    func warmup() {
        Task {
            // Pre-warm MusicKit by doing a minimal request
            if isAuthorized {
                var request = MusicCatalogSearchRequest(term: "a", types: [Song.self])
                request.limit = 1
                _ = try? await request.response()
                print("🎵 MusicKit warmed up")
            }
        }
    }
    
    // MARK: - Authorization
    
    func checkAuthorization() async {
        let status = await MusicAuthorization.request()
        
        await MainActor.run {
            switch status {
            case .authorized:
                self.isAuthorized = true
                self.errorMessage = nil
            case .denied, .restricted:
                self.isAuthorized = false
                self.errorMessage = "Music access denied. Enable in System Settings → Privacy → Media & Apple Music"
            case .notDetermined:
                self.isAuthorized = false
            @unknown default:
                self.isAuthorized = false
            }
        }
    }
    
    func requestAuthorization() async {
        await checkAuthorization()
        if isAuthorized {
            await fetchUserPlaylists()
            warmup() // Pre-warm for search
        }
    }
    
    // MARK: - Fetch User's Playlists
    
    func fetchUserPlaylists() async {
        guard isAuthorized else { return }
        
        do {
            // Fetch playlists from user's library
            var request = MusicLibraryRequest<Playlist>()
            request.sort(by: \.name, ascending: true)
            let response = try await request.response()
            
            // Store full playlists for playback
            let fetchedPlaylists = Array(response.items)
            
            let items = fetchedPlaylists.map { playlist in
                AppleMusicPlaylistItem(
                    id: playlist.id.rawValue,
                    name: playlist.name
                )
            }
            
            await MainActor.run {
                self.libraryPlaylists = fetchedPlaylists
                self.playlists = items
                print("🎵 Loaded \(items.count) Apple Music playlists")
            }
            
            // Pre-warm for search
            warmup()
        } catch {
            print("❌ Error fetching playlists: \(error)")
            await MainActor.run {
                self.errorMessage = "Failed to load playlists: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Search Songs
    
    func searchSongs(query: String) async {
        guard isAuthorized, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                self.searchResults = []
            }
            return
        }
        
        do {
            var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
            request.limit = 25
            let response = try await request.response()
            
            let items = response.songs.map { song in
                AppleMusicSongItem(
                    id: song.id.rawValue,
                    name: song.title,
                    artistName: song.artistName,
                    albumName: song.albumTitle ?? "",
                    artworkURL: song.artwork?.url(width: artworkSize, height: artworkSize)
                )
            }
            
            await MainActor.run {
                self.searchResults = items
                print("🎵 Found \(items.count) songs for query: \(query)")
            }
        } catch {
            print("❌ Search error: \(error)")
            await MainActor.run {
                self.searchResults = []
                self.errorMessage = "Search failed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Artwork Helpers
    
    /// Get artwork URL for a song by ID
    func getSongArtwork(songId: String) async -> URL? {
        guard isAuthorized else { return nil }
        
        do {
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(songId))
            let response = try await request.response()
            
            if let song = response.items.first {
                return song.artwork?.url(width: artworkSize, height: artworkSize)
            }
            return nil
        } catch {
            print("❌ Error fetching song artwork: \(error)")
            return nil
        }
    }
    
    /// Get artwork URL for a playlist by ID
    func getPlaylistArtwork(playlistId: String) async -> URL? {
        guard isAuthorized else { return nil }
        
        // Check cached playlists first
        if let playlist = libraryPlaylists.first(where: { $0.id.rawValue == playlistId }) {
            return playlist.artwork?.url(width: artworkSize, height: artworkSize)
        }
        
        // Fetch from library if not cached
        do {
            let request = MusicLibraryRequest<Playlist>()
            let response = try await request.response()
            
            if let playlist = response.items.first(where: { $0.id.rawValue == playlistId }) {
                return playlist.artwork?.url(width: artworkSize, height: artworkSize)
            }
            return nil
        } catch {
            print("❌ Error fetching playlist artwork: \(error)")
            return nil
        }
    }
    
    /// Clear artwork when stopping
    func clearArtwork() {
        currentArtworkURL = nil
        isPlaying = false
    }
    
    // MARK: - Playback
    
    func playSong(id: String) async {
        guard isAuthorized else {
            await MainActor.run {
                errorMessage = "Apple Music not authorized"
            }
            return
        }
        
        do {
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
            let response = try await request.response()
            
            if let song = response.items.first {
                let player = ApplicationMusicPlayer.shared
                player.queue = [song]
                try await player.play()
                print("🎵 Playing song: \(song.title)")
                
                // Update artwork
                let artworkURL = song.artwork?.url(width: artworkSize, height: artworkSize)
                await MainActor.run {
                    errorMessage = nil
                    isPlaying = true
                    currentArtworkURL = artworkURL
                }
            } else {
                await MainActor.run {
                    errorMessage = "Song not found"
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to play song: \(error.localizedDescription)"
            }
            print("❌ Error playing song: \(error)")
        }
    }
    
    func playPlaylist(id: String) async {
        guard isAuthorized else {
            await MainActor.run {
                errorMessage = "Apple Music not authorized"
            }
            return
        }
        
        do {
            // First, check if we have this playlist in our cached library playlists
            if let playlist = libraryPlaylists.first(where: { $0.id.rawValue == id }) {
                // Load the playlist with its tracks
                let detailedPlaylist = try await playlist.with([.tracks])
                
                if let tracks = detailedPlaylist.tracks {
                    let player = ApplicationMusicPlayer.shared
                    player.queue = ApplicationMusicPlayer.Queue(for: tracks)
                    try await player.play()
                    print("🎵 Playing library playlist: \(playlist.name) with \(tracks.count) tracks")
                    
                    // Get artwork from first track or playlist
                    let artworkURL: URL? = playlist.artwork?.url(width: artworkSize, height: artworkSize)
                        ?? tracks.first?.artwork?.url(width: artworkSize, height: artworkSize)
                    
                    await MainActor.run {
                        errorMessage = nil
                        isPlaying = true
                        currentArtworkURL = artworkURL
                    }
                    return
                }
            }
            
            // If not in cache, try fetching from library again
            let libraryRequest = MusicLibraryRequest<Playlist>()
            let libraryResponse = try await libraryRequest.response()
            
            if let playlist = libraryResponse.items.first(where: { $0.id.rawValue == id }) {
                let detailedPlaylist = try await playlist.with([.tracks])
                
                if let tracks = detailedPlaylist.tracks {
                    let player = ApplicationMusicPlayer.shared
                    player.queue = ApplicationMusicPlayer.Queue(for: tracks)
                    try await player.play()
                    print("🎵 Playing library playlist: \(playlist.name) with \(tracks.count) tracks")
                    
                    // Get artwork from first track or playlist
                    let artworkURL: URL? = playlist.artwork?.url(width: artworkSize, height: artworkSize)
                        ?? tracks.first?.artwork?.url(width: artworkSize, height: artworkSize)
                    
                    await MainActor.run {
                        errorMessage = nil
                        isPlaying = true
                        currentArtworkURL = artworkURL
                    }
                    return
                }
            }
            
            await MainActor.run {
                errorMessage = "Playlist not found in library"
            }
            print("❌ Playlist not found: \(id)")
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to play playlist: \(error.localizedDescription)"
            }
            print("❌ Error playing playlist: \(error)")
        }
    }
    
    func pause() {
        ApplicationMusicPlayer.shared.pause()
        print("⏸️ Music paused")
        isPlaying = false
    }
    
    func play() {
        Task {
            do {
                try await ApplicationMusicPlayer.shared.play()
                print("▶️ Music resumed")
                await MainActor.run {
                    isPlaying = true
                }
            } catch {
                print("❌ Error resuming: \(error)")
            }
        }
    }
    
    // MARK: - Clear Selection
    
    func clearWarmupSong() {
        selectedWarmupSongId = nil
        warmupSongName = nil
    }
}
