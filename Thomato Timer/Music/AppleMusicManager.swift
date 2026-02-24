//
//  AppleMusicManager.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/26.
//

import Foundation
import MusicKit
import Observation

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
    var currentArtworkURL: URL?
    var isPlaying = false

    private let artworkSize = 1024

    func warmup() {
        Task {
            if isAuthorized {
                var request = MusicCatalogSearchRequest(term: "a", types: [Song.self])
                request.limit = 1
                _ = try? await request.response()
            }
        }
    }

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
        }
    }

    func fetchUserPlaylists() async {
        guard isAuthorized else { return }

        do {
            var request = MusicLibraryRequest<Playlist>()
            request.sort(by: \.name, ascending: true)
            let response = try await request.response()

            let fetchedPlaylists = Array(response.items)
            let items = fetchedPlaylists.map { playlist in
                AppleMusicPlaylistItem(id: playlist.id.rawValue, name: playlist.name)
            }

            await MainActor.run {
                self.libraryPlaylists = fetchedPlaylists
                self.playlists = items
            }

            warmup()
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load playlists: \(error.localizedDescription)"
            }
        }
    }

    func searchSongs(query: String) async {
        guard isAuthorized,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run { self.searchResults = [] }
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

            await MainActor.run { self.searchResults = items }
        } catch {
            await MainActor.run {
                self.searchResults = []
                self.errorMessage = "Search failed: \(error.localizedDescription)"
            }
        }
    }

    func getSongArtwork(songId: String) async -> URL? {
        guard isAuthorized else { return nil }

        do {
            let request = MusicCatalogResourceRequest<Song>(
                matching: \.id,
                equalTo: MusicItemID(songId)
            )
            let response = try await request.response()
            return response.items.first?.artwork?.url(width: artworkSize, height: artworkSize)
        } catch {
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
            return response.items.first(where: { $0.id.rawValue == playlistId })?
                .artwork?.url(width: artworkSize, height: artworkSize)
        } catch {
            return nil
        }
    }

    func clearArtwork() {
        currentArtworkURL = nil
        isPlaying = false
    }

    func playSong(id: String) async {
        guard isAuthorized else {
            await MainActor.run { errorMessage = "Apple Music not authorized" }
            return
        }

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

                let artworkURL = song.artwork?.url(width: artworkSize, height: artworkSize)
                await MainActor.run {
                    errorMessage = nil
                    isPlaying = true
                    currentArtworkURL = artworkURL
                }
            } else {
                await MainActor.run { errorMessage = "Song not found" }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to play song: \(error.localizedDescription)"
            }
        }
    }

    func playPlaylist(id: String) async {
        guard isAuthorized else {
            await MainActor.run { errorMessage = "Apple Music not authorized" }
            return
        }

        do {
            if let playlist = libraryPlaylists.first(where: { $0.id.rawValue == id }) {
                try await playLibraryPlaylist(playlist)
                return
            }

            let libraryResponse = try await MusicLibraryRequest<Playlist>().response()
            libraryPlaylists = Array(libraryResponse.items)

            if let playlist = libraryPlaylists.first(where: { $0.id.rawValue == id }) {
                try await playLibraryPlaylist(playlist)
                return
            }

            await MainActor.run { errorMessage = "Playlist not found in library" }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to play playlist: \(error.localizedDescription)"
            }
        }
    }

    private func playLibraryPlaylist(_ playlist: Playlist) async throws {
        let detailedPlaylist = try await playlist.with([.tracks])

        guard let tracks = detailedPlaylist.tracks, !tracks.isEmpty else {
            await MainActor.run { errorMessage = "Playlist has no tracks" }
            return
        }

        let shuffledTracks = Array(tracks).shuffled()
        let player = ApplicationMusicPlayer.shared
        player.queue = ApplicationMusicPlayer.Queue(for: shuffledTracks)
        try await player.play()

        let artworkURL: URL? =
            playlist.artwork?.url(width: artworkSize, height: artworkSize)
            ?? shuffledTracks.first?.artwork?.url(width: artworkSize, height: artworkSize)

        await MainActor.run {
            errorMessage = nil
            isPlaying = true
            currentArtworkURL = artworkURL
        }
    }

    func pause() {
        ApplicationMusicPlayer.shared.pause()
        isPlaying = false
    }

    func play() {
        Task {
            do {
                try await ApplicationMusicPlayer.shared.play()
                await MainActor.run { isPlaying = true }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to resume: \(error.localizedDescription)"
                }
            }
        }
    }

    func clearWarmupSong() {
        selectedWarmupSongId = nil
        warmupSongName = nil
    }
}
