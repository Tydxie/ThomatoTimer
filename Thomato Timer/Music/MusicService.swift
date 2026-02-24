//
//  MusicService.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/26.
//

import Foundation

enum MusicService: String, CaseIterable, Identifiable {
    case none = "None"
    case spotify = "Spotify"
    case appleMusic = "Apple Music"
    
    var id: String { rawValue }
}
