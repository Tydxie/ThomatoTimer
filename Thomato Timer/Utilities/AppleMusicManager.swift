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
    
    // User's playlists from library
    var playlists: [AppleMusicPlaylistItem] = []
    
    // Search results for songs
    var searchResults: [AppleMusicSongItem] = []
    
    var errorMessage: String?
    
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
            
            let items = response.items.map { playlist in
                AppleMusicPlaylistItem(
                    id: playlist.id.rawValue,
                    name: playlist.name
                )
            }
            
            await MainActor.run {
                self.playlists = items
                print("🎵 Loaded \(items.count) Apple Music playlists")
            }
        } catch {
            print("❌ Error fetching playlists: \(error)")
            await MainActor.run {
                self.errorMessage = "Failed to load playlists: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Search Songs
    
    func searchSongs(query: String) async {
        guard isAuthorized, !query.isEmpty else {
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
                    albumName: song.albumTitle ?? ""
                )
            }
            
            await MainActor.run {
                self.searchResults = items
            }
        } catch {
            print("❌ Search error: \(error)")
            await MainActor.run {
                self.searchResults = []
            }
        }
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
                await MainActor.run {
                    errorMessage = nil
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
            // Try library playlist first
            var libraryRequest = MusicLibraryRequest<Playlist>()
            libraryRequest.filter(matching: \.id, equalTo: MusicItemID(id))
            let libraryResponse = try await libraryRequest.response()
            
            if let playlist = libraryResponse.items.first {
                let player = ApplicationMusicPlayer.shared
                player.queue = [playlist]
                try await player.play()
                print("🎵 Playing playlist: \(playlist.name)")
                await MainActor.run {
                    errorMessage = nil
                }
                return
            }
            
            // Fallback to catalog playlist
            let catalogRequest = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: MusicItemID(id))
            let catalogResponse = try await catalogRequest.response()
            
            if let playlist = catalogResponse.items.first {
                let player = ApplicationMusicPlayer.shared
                player.queue = [playlist]
                try await player.play()
                print("🎵 Playing playlist: \(playlist.name)")
                await MainActor.run {
                    errorMessage = nil
                }
            } else {
                await MainActor.run {
                    errorMessage = "Playlist not found"
                }
            }
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
    }
    
    func play() {
        Task {
            do {
                try await ApplicationMusicPlayer.shared.play()
                print("▶️ Music resumed")
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
