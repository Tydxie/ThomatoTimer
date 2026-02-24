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

    private var activeService: (any MusicPlayerService)? {
        switch selectedService {
        case .spotify:    return spotifyManager
        case .appleMusic: return appleMusicManager
        case .none:       return nil
        }
    }

    private func playlistId(for phase: TimerPhase) -> String? {
        switch selectedService {
        case .spotify:
            return phase == .work
                ? spotifyManager?.selectedWorkPlaylistId
                : spotifyManager?.selectedBreakPlaylistId
        case .appleMusic:
            return phase == .work
                ? appleMusicManager?.selectedWorkPlaylistId
                : appleMusicManager?.selectedBreakPlaylistId
        case .none:
            return nil
        }
    }

    func play(for phase: TimerPhase) {
        guard let service = activeService else { return }
        let id = playlistId(for: phase)
        Task.detached {
            if let id {
                await service.playPlaylist(id: id)
            } else {
                service.pause()
            }
        }
    }

    func pause() {
        activeService?.pause()
    }

    func resume() {
        guard let service = activeService else { return }
        service.play()
    }
}
