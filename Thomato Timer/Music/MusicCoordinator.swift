//
//  MusicCoordinator.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2026/02/24.
//

import Foundation

class MusicCoordinator {
    var spotifyManager: SpotifyManager?
    var appleMusicManager: AppleMusicManager?
    var selectedService: MusicService = .none

    func play(for phase: TimerPhase) {
        switch selectedService {
        case .spotify:    playSpotify(for: phase)
        case .appleMusic: playAppleMusic(for: phase)
        case .none:       break
        }
    }

    func pause() {
        switch selectedService {
        case .spotify:
            guard let spotify = spotifyManager, spotify.isAuthenticated else { return }
            Task { await spotify.pausePlayback() }
        case .appleMusic:
            guard let appleMusic = appleMusicManager, appleMusic.isAuthorized else { return }
            appleMusic.pause()
        case .none:
            break
        }
    }

    func resume() {
        switch selectedService {
        case .spotify:
            guard let spotify = spotifyManager, spotify.isAuthenticated else { return }
            Task { await spotify.resumePlayback() }
        case .appleMusic:
            guard let appleMusic = appleMusicManager, appleMusic.isAuthorized else { return }
            appleMusic.play()
        case .none:
            break
        }
    }

    // MARK: - Private

    private func playSpotify(for phase: TimerPhase) {
        guard let spotify = spotifyManager, spotify.isAuthenticated else { return }
        Task.detached {
            switch phase {
            case .warmup, .shortBreak, .longBreak:
                if let id = spotify.selectedBreakPlaylistId {
                    await spotify.playPlaylist(playlistId: id)
                } else {
                    await spotify.pausePlayback()
                }
            case .work:
                if let id = spotify.selectedWorkPlaylistId {
                    await spotify.playPlaylist(playlistId: id)
                } else {
                    await spotify.pausePlayback()
                }
            }
        }
    }

    private func playAppleMusic(for phase: TimerPhase) {
        guard let appleMusic = appleMusicManager, appleMusic.isAuthorized else { return }
        Task.detached {
            switch phase {
            case .warmup, .shortBreak, .longBreak:
                if let id = appleMusic.selectedBreakPlaylistId {
                    await appleMusic.playPlaylist(id: id)
                } else {
                    appleMusic.pause()
                }
            case .work:
                if let id = appleMusic.selectedWorkPlaylistId {
                    await appleMusic.playPlaylist(id: id)
                } else {
                    appleMusic.pause()
                }
            }
        }
    }
}
