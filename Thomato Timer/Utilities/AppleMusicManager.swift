//
//  AppleMusicManager.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/26.
//

import Foundation
import MusicKit
import Observation

@Observable
final class AppleMusicManager {
    var isAuthorized = false
    var warmupSongId: String = ""
    var workPlaylistId: String = ""
    var breakPlaylistId: String = ""
    
    var warmupSongName: String?
    var workPlaylistName: String?
    var breakPlaylistName: String?
    
    var errorMessage: String?
    
    // Check authorization status
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
    
    // Request authorization
    func requestAuthorization() async {
        await checkAuthorization()
    }
    
    // Play song by Apple Music ID
    func playSong(id: String) async {
        guard isAuthorized else {
            await MainActor.run {
                errorMessage = "Apple Music not authorized. Enable in System Settings → Privacy → Media & Apple Music"
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
                    errorMessage = "Song not found. Please check the song ID."
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to play song: \(error.localizedDescription)"
            }
            print("❌ Error playing song: \(error)")
        }
    }
    
    // Play playlist by Apple Music ID
    func playPlaylist(id: String) async {
        guard isAuthorized else {
            await MainActor.run {
                errorMessage = "Apple Music not authorized. Enable in System Settings → Privacy → Media & Apple Music"
            }
            return
        }
        
        do {
            let request = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: MusicItemID(id))
            let response = try await request.response()
            
            if let playlist = response.items.first {
                let player = ApplicationMusicPlayer.shared
                player.queue = [playlist]
                try await player.play()
                print("🎵 Playing playlist: \(playlist.name)")
                await MainActor.run {
                    errorMessage = nil
                }
            } else {
                await MainActor.run {
                    errorMessage = "Playlist not found. Please check the playlist ID."
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to play playlist: \(error.localizedDescription)"
            }
            print("❌ Error playing playlist: \(error)")
        }
    }
    
    // Pause playback
    func pause() {
        ApplicationMusicPlayer.shared.pause()
        print("⏸️ Music paused")
    }
    
    // Resume playback
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
    
    // Search for songs
    func searchSongs(query: String) async -> [Song] {
        guard isAuthorized, !query.isEmpty else { return [] }
        
        do {
            var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
            request.limit = 20
            let response = try await request.response()
            return response.songs.map { $0 }
        } catch {
            print("❌ Search error: \(error)")
            return []
        }
    }
    
    // Search for playlists
    func searchPlaylists(query: String) async -> [Playlist] {
        guard isAuthorized, !query.isEmpty else { return [] }
        
        do {
            var request = MusicCatalogSearchRequest(term: query, types: [Playlist.self])
            request.limit = 20
            let response = try await request.response()
            return response.playlists.map { $0 }
        } catch {
            print("❌ Search error: \(error)")
            return []
        }
    }
}
