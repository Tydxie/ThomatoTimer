//
//  MusicPlayerService.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2026/02/24.
//

import Foundation

protocol MusicPlayerService {
    var isPlaying: Bool { get }
    var currentArtworkURL: URL? { get }

    func play()
    func pause()
    func playPlaylist(id: String) async
}
