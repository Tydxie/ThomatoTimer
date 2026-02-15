//
//  AppleMusicManager.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/26.
//

import Foundation
import MusicKit
import Observation
#if os(iOS)
import AVFoundation
#endif

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
    // MARK: - Authorization / Basic State
    var isAuthorized = false
    
    var selectedWarmupSongId: String?
    var selectedWorkPlaylistId: String?
    var selectedBreakPlaylistId: String?
    
    var warmupSongName: String?
    var workPlaylistName: String?
    var breakPlaylistName: String?
    
    var playlists: [AppleMusicPlaylistItem] = []
    private var libraryPlaylists: [Playlist] = []
    
    var searchResults: [AppleMusicSongItem] = []
    
    var errorMessage: String?
    
    // MARK: - Artwork / Playback State
    var currentArtworkURL: URL?
    var isPlaying = false
    
    #if os(iOS)
    private let artworkSize = 1024
    #else
    private let artworkSize = 1024
    #endif
    
    // MARK: - Audio Session Setup
    
    #if os(iOS)
    func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            print("Audio session activated for background playback")
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    #endif
    
    // MARK: - Warmup
    
    func warmup() {
        Task {
            if isAuthorized {
                var request = MusicCatalogSearchRequest(term: "a", types: [Song.self])
                request.limit = 1
                _ = try? await request.response()
                print("MusicKit warmed up")
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
            warmup()
            #if os(iOS)
            setupAudioSession()
            #endif
        }
    }
    
    // MARK: - Fetch User Playlists
    
    func fetchUserPlaylists() async {
        guard isAuthorized else { return }
        
        do {
            var request = MusicLibraryRequest<Playlist>()
            request.sort(by: \.name, ascending: true)
            let response = try await request.response()
            
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
                print("Loaded \(items.count) Apple Music playlists")
            }
            
            warmup()
        } catch {
            print("Error fetching playlists: \(error)")
            await MainActor.run {
                self.errorMessage = "Failed to load playlists: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Search Songs
    
    func searchSongs(query: String) async {
        guard isAuthorized,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
                print("Found \(items.count) songs for query: \(query)")
            }
        } catch {
            print("Search error: \(error)")
            await MainActor.run {
                self.searchResults = []
                self.errorMessage = "Search failed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Artwork Helpers
    
    func getSongArtwork(songId: String) async -> URL? {
        guard isAuthorized else { return nil }
        
        do {
            let request = MusicCatalogResourceRequest<Song>(
                matching: \.id,
                equalTo: MusicItemID(songId)
            )
            let response = try await request.response()
            
            if let song = response.items.first {
                return song.artwork?.url(width: artworkSize, height: artworkSize)
            }
            return nil
        } catch {
            print("Error fetching song artwork: \(error)")
            return nil
        }
    }
    
    func getPlaylistArtwork(playlistId: String) async -> URL? {
        guard isAuthorized else { return nil }
        
        if let playlist = libraryPlaylists.first(where: { $0.id.rawValue == playlistId }) {
            return playlist.artwork?.url(width: artworkSize, height: artworkSize)
        }
        
        do {
            let request = MusicLibraryRequest<Playlist>()
            let response = try await request.response()
            
            if let playlist = response.items.first(where: { $0.id.rawValue == playlistId }) {
                return playlist.artwork?.url(width: artworkSize, height: artworkSize)
            }
            return nil
        } catch {
            print("Error fetching playlist artwork: \(error)")
            return nil
        }
    }
    
    func clearArtwork() {
        currentArtworkURL = nil
        isPlaying = false
    }
    
    // MARK: - Playback (Song)
    
    func playSong(id: String) async {
        guard isAuthorized else {
            await MainActor.run {
                errorMessage = "Apple Music not authorized"
            }
            return
        }
        
        #if os(iOS)
        setupAudioSession()
        #endif
        
        do {
            let request = MusicCatalogResourceRequest<Song>(
                matching: \.id,
                equalTo: MusicItemID(id)
            )
            let response = try await request.response()
            
            if let song = response.items.first {
                let player = ApplicationMusicPlayer.shared
                player.queue = [song]
                try await player.play()
                print("Playing song: \(song.title)")
                
                let artworkURL = song.artwork?.url(width: artworkSize, height: artworkSize)
                
                await MainActor.run {
                    errorMessage = nil
                    isPlaying = true
                    currentArtworkURL = artworkURL
                    print("Apple Music song artwork: \(artworkURL?.absoluteString ?? "nil")")
                }
            } else {
                await MainActor.run {
                    errorMessage = "Song not found"
                }
            }
        } catch {
            print("Error playing song: \(error)")
            await MainActor.run {
                errorMessage = "Failed to play song: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Playback (Playlist)
    
    func playPlaylist(id: String) async {
        guard isAuthorized else {
            await MainActor.run {
                errorMessage = "Apple Music not authorized"
            }
            return
        }
        
        #if os(iOS)
        setupAudioSession()
        #endif
        
        do {
            if let playlist = libraryPlaylists.first(where: { $0.id.rawValue == id }) {
                try await playLibraryPlaylist(playlist)
                return
            }
            
            let libraryRequest = MusicLibraryRequest<Playlist>()
            let libraryResponse = try await libraryRequest.response()
            libraryPlaylists = Array(libraryResponse.items)
            
            if let playlist = libraryPlaylists.first(where: { $0.id.rawValue == id }) {
                try await playLibraryPlaylist(playlist)
                return
            }
            
            await MainActor.run {
                errorMessage = "Playlist not found in library"
            }
            print("Playlist not found: \(id)")
            
        } catch {
            print("Error playing playlist: \(error)")
            await MainActor.run {
                errorMessage = "Failed to play playlist: \(error.localizedDescription)"
            }
        }
    }
    
    private func playLibraryPlaylist(_ playlist: Playlist) async throws {
        let detailedPlaylist = try await playlist.with([.tracks])
        
        guard let tracks = detailedPlaylist.tracks, !tracks.isEmpty else {
            await MainActor.run {
                errorMessage = "Playlist has no tracks"
            }
            print("Playlist has no tracks: \(playlist.name)")
            return
        }
        
        let shuffledTracks = Array(tracks).shuffled()
        
        let player = ApplicationMusicPlayer.shared
        player.queue = ApplicationMusicPlayer.Queue(for: shuffledTracks)
        try await player.play()
        
        print("Playing (shuffled) library playlist: \(playlist.name) with \(shuffledTracks.count) tracks")
        
        let artworkURL: URL? =
            playlist.artwork?.url(width: artworkSize, height: artworkSize)
            ?? shuffledTracks.first?.artwork?.url(width: artworkSize, height: artworkSize)
        
        await MainActor.run {
            errorMessage = nil
            isPlaying = true
            currentArtworkURL = artworkURL
            print("Apple Music playlist artwork: \(artworkURL?.absoluteString ?? "nil")")
        }
    }
    
    // MARK: - Pause / Resume
    
    func pause() {
        ApplicationMusicPlayer.shared.pause()
        print("Music paused")
        isPlaying = false
    }
    
    func play() {
        Task {
            #if os(iOS)
            setupAudioSession()
            #endif
            
            do {
                try await ApplicationMusicPlayer.shared.play()
                print("Music resumed")
                await MainActor.run {
                    isPlaying = true
                }
            } catch {
                print("Error resuming: \(error)")
            }
        }
    }
    
    // MARK: - Clear Selection
    
    func clearWarmupSong() {
        selectedWarmupSongId = nil
        warmupSongName = nil
    }
}
