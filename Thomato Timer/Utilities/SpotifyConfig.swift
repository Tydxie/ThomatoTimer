//
//  SpotifyConfig.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/25.
//

import Foundation

struct SpotifyConfig {
    // Load from SpotifySecrets.swift
    static let clientID = SpotifySecrets.clientID
    static let redirectURI = "thomato-timer://callback"
    
    static let authURL = "https://accounts.spotify.com/authorize"
    static let tokenURL = "https://accounts.spotify.com/api/token"
    static let apiBaseURL = "https://api.spotify.com/v1"
    
    static let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "playlist-read-private",
        "playlist-read-collaborative"
    ]
    
    static var scopeString: String {
        scopes.joined(separator: "%20")  // ← Changed this
    }
}
