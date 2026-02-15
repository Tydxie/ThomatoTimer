//
//  SpotifyManager.swift
//  Thomodoro
//
//  Created by Thomas Xie on 2025/11/25.
//

import Foundation
import SwiftUI
import Observation
import CryptoKit

@Observable
final class SpotifyManager: NSObject {
    // MARK: - Published State
    var isAuthenticated = false
    var accessToken: String?
    var refreshToken: String?
    var tokenExpirationDate: Date?
    var errorMessage: String?
    
    // MARK: - Private PKCE State
    private var codeVerifier: String?
    private var state: String?
    
    // MARK: - Playlist & Track State
    var playlists: [SpotifyPlaylist] = []
    var selectedWorkPlaylistId: String?
    var selectedBreakPlaylistId: String?
    var selectedWarmupTrackId: String?
    var warmupTrackName: String?
    var searchResults: [SpotifyTrack] = []
    
    // MARK: - Current Playback State (for artwork)
    var currentArtworkURL: URL?
    var isPlaying = false
    var currentTrackName: String?
    var currentArtistName: String?
    var currentTrackSpotifyURL: String?
    private var currentTrackId: String?
    
    // MARK: - Device Preference
    private var preferredDeviceId: String?
    
    // MARK: - Playback Polling
    private var pollingTimer: Timer?
    private var isPollingEnabled = false
    
    // MARK: - Authentication Flow
    
    @MainActor
    func authenticate() {
        
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let stateValue = generateState()
        
        self.codeVerifier = verifier
        self.state = stateValue
        
        var components = URLComponents(string: SpotifyConfig.authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: SpotifyConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: stateValue),
            URLQueryItem(name: "scope", value: SpotifyConfig.scopeString)
        ]
        
        guard let url = components.url else {
            errorMessage = "Failed to create authorization URL"
            return
        }
        
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
    
    func handleRedirect(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            await MainActor.run {
                errorMessage = "Invalid callback URL"
            }
            return
        }
        
        let queryItems = components.queryItems ?? []
        
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            await MainActor.run {
                errorMessage = "Authorization failed: \(error)"
            }
            return
        }
        
        guard let code = queryItems.first(where: { $0.name == "code" })?.value,
              let returnedState = queryItems.first(where: { $0.name == "state" })?.value else {
            await MainActor.run {
                errorMessage = "Missing code or state in callback"
            }
            return
        }
        
        guard returnedState == self.state else {
            await MainActor.run {
                errorMessage = "State mismatch - possible CSRF attack"
            }
            return
        }
        
        guard let verifier = self.codeVerifier else {
            await MainActor.run {
                errorMessage = "Code verifier not found"
            }
            return
        }
        
        await exchangeCodeForToken(code: code, codeVerifier: verifier)
    }
    
    private func exchangeCodeForToken(code: String, codeVerifier: String) async {
        var request = URLRequest(url: URL(string: SpotifyConfig.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectURI,
            "client_id": SpotifyConfig.clientID,
            "code_verifier": codeVerifier
        ]
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    errorMessage = "Invalid response from server"
                }
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                if let errorResponse = try? JSONDecoder().decode(SpotifyErrorResponse.self, from: data) {
                    await MainActor.run {
                        errorMessage = "Token exchange failed: \(errorResponse.error_description ?? errorResponse.error)"
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Token exchange failed with status \(httpResponse.statusCode)"
                    }
                }
                return
            }
            
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            
            await MainActor.run {
                self.accessToken = tokenResponse.access_token
                self.refreshToken = tokenResponse.refresh_token
                self.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
                self.isAuthenticated = true
                self.errorMessage = nil
                self.codeVerifier = nil
                self.state = nil
                
                print("Spotify authenticated successfully")
            }
            
            await fetchPlaylists()
            
        } catch {
            await MainActor.run {
                errorMessage = "Network error: \(error.localizedDescription)"
            }
        }
    }
    
    func refreshAccessToken() async {
        guard let refreshToken = self.refreshToken else {
            print("No refresh token available")
            await MainActor.run {
                errorMessage = "No refresh token available"
            }
            return
        }
        
        print("Refreshing Spotify access token...")
        
        var request = URLRequest(url: URL(string: SpotifyConfig.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": SpotifyConfig.clientID
        ]
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("Token refresh failed")
                await MainActor.run {
                    errorMessage = "Token refresh failed"
                }
                return
            }
            
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            
            await MainActor.run {
                self.accessToken = tokenResponse.access_token
                self.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
                
                if let newRefreshToken = tokenResponse.refresh_token {
                    self.refreshToken = newRefreshToken
                }
                
                print("Token refreshed successfully")
            }
            
        } catch {
            print("Token refresh error: \(error)")
            await MainActor.run {
                errorMessage = "Refresh error: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - PKCE Helper Functions
    
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hashed = SHA256.hash(data: data)
        return Data(hashed).base64URLEncodedString()
    }
    
    private func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
    
    // MARK: - Testing
    func testConfiguration() -> String {
        """
        Spotify Configuration (Works as of 11/25/2025)
        
        Client ID: \(SpotifyConfig.clientID.prefix(15))...
        Redirect URI: \(SpotifyConfig.redirectURI)
        Auth Method: PKCE (S256)
        Scopes: \(SpotifyConfig.scopeString)
        
        Status: \(isAuthenticated ? "Authenticated" : "Not authenticated")
        """
    }
    
    // MARK: - Playlist Management
    
    func fetchPlaylists() async {
        await ensureValidToken()
        guard let accessToken = self.accessToken else {
            await MainActor.run {
                errorMessage = "Not authenticated"
            }
            return
        }
        
        var request = URLRequest(url: URL(string: "\(SpotifyConfig.apiBaseURL)/me/playlists?limit=50")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    errorMessage = "Invalid response"
                }
                return
            }
            
            if httpResponse.statusCode == 401 {
                print("401 Unauthorized - refreshing token and retrying...")
                await refreshAccessToken()
                
                if let newToken = self.accessToken {
                    request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
                    guard let retryHttp = retryResponse as? HTTPURLResponse,
                          retryHttp.statusCode == 200 else {
                        await MainActor.run {
                            errorMessage = "Failed to fetch playlists after retry"
                        }
                        return
                    }
                    let playlistResponse = try JSONDecoder().decode(PlaylistResponse.self, from: retryData)
                    await MainActor.run {
                        self.playlists = playlistResponse.items
                    }
                }
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                await MainActor.run {
                    errorMessage = "Failed to fetch playlists"
                }
                return
            }
            
            let playlistResponse = try JSONDecoder().decode(PlaylistResponse.self, from: data)
            
            await MainActor.run {
                self.playlists = playlistResponse.items
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Error fetching playlists: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Playlist Metadata
    
    private func getPlaylistTrackCount(playlistId: String) async -> Int? {
        await ensureValidToken()
        guard let accessToken = self.accessToken else { return nil }
        
        guard let url = URL(string: "\(SpotifyConfig.apiBaseURL)/playlists/\(playlistId)?fields=tracks.total") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            struct PlaylistTrackCountResponse: Codable {
                struct Tracks: Codable { let total: Int }
                let tracks: Tracks
            }
            
            let decoded = try JSONDecoder().decode(PlaylistTrackCountResponse.self, from: data)
            return decoded.tracks.total
        } catch {
            print("Error getting playlist track count: \(error)")
            return nil
        }
    }
    
    // MARK: - Track Search
    
    func searchTracks(query: String) async {
        await ensureValidToken()
        guard let accessToken = self.accessToken else {
            await MainActor.run {
                errorMessage = "Not authenticated"
            }
            return
        }
        
        guard !query.isEmpty else {
            await MainActor.run {
                self.searchResults = []
            }
            return
        }
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var request = URLRequest(url: URL(string: "\(SpotifyConfig.apiBaseURL)/search?q=\(encodedQuery)&type=track&limit=20")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    errorMessage = "Invalid response"
                }
                return
            }
            
            if httpResponse.statusCode == 401 {
                print("401 Unauthorized - refreshing token and retrying...")
                await refreshAccessToken()
                
                if let newToken = self.accessToken {
                    request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
                    guard let retryHttp = retryResponse as? HTTPURLResponse,
                          retryHttp.statusCode == 200 else {
                        await MainActor.run {
                            errorMessage = "Failed to search tracks after retry"
                        }
                        return
                    }
                    let searchResponse = try JSONDecoder().decode(TrackSearchResponse.self, from: retryData)
                    await MainActor.run {
                        self.searchResults = searchResponse.tracks.items
                    }
                }
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                await MainActor.run {
                    errorMessage = "Failed to search tracks"
                }
                return
            }
            
            let searchResponse = try JSONDecoder().decode(TrackSearchResponse.self, from: data)
            
            await MainActor.run {
                self.searchResults = searchResponse.tracks.items
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Error searching tracks: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Device Management
    
    func getAvailableDevices() async -> [SpotifyDevice] {
        guard let accessToken = self.accessToken else { return [] }
        
        var request = URLRequest(url: URL(string: "\(SpotifyConfig.apiBaseURL)/me/player/devices")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }
            
            let deviceResponse = try JSONDecoder().decode(DeviceResponse.self, from: data)
            return deviceResponse.devices
            
        } catch {
            return []
        }
    }
    
    // MARK: - Token Management

    private func ensureValidToken() async {
        guard let expirationDate = tokenExpirationDate else {
            if refreshToken != nil {
                await refreshAccessToken()
            }
            return
        }
        
        if expirationDate.timeIntervalSinceNow < 300 {
            await refreshAccessToken()
        }
    }
    
    // MARK: - Playback Polling
    
    @MainActor
    func startPlaybackPolling() {
        guard !isPollingEnabled else { return }
        isPollingEnabled = true
        
        Task {
            await self.fetchCurrentPlayback()
        }
        
        pollingTimer = Timer.scheduledTimer(
            timeInterval: 3.0,
            target: self,
            selector: #selector(handlePollingTimer(_:)),
            userInfo: nil,
            repeats: true
        )
        
        print("Started Spotify playback polling")
    }
    
    @objc private func handlePollingTimer(_ timer: Timer) {
        Task {
            await self.fetchCurrentPlayback()
        }
    }
    
    @MainActor
    func stopPlaybackPolling() {
        isPollingEnabled = false
        pollingTimer?.invalidate()
        pollingTimer = nil
        currentArtworkURL = nil
        currentTrackId = nil
        currentTrackName = nil
        currentArtistName = nil
        currentTrackSpotifyURL = nil
        isPlaying = false
        print("Stopped Spotify playback polling")
    }
    
    // MARK: - Current Playback State
    
    func fetchCurrentPlayback() async {
        await ensureValidToken()
        guard let accessToken = self.accessToken else { return }
        
        var request = URLRequest(url: URL(string: "\(SpotifyConfig.apiBaseURL)/me/player/currently-playing")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else { return }
            
            if httpResponse.statusCode == 204 {
                await MainActor.run {
                    self.isPlaying = false
                    self.currentArtworkURL = nil
                    self.currentTrackId = nil
                    self.currentTrackName = nil
                    self.currentArtistName = nil
                    self.currentTrackSpotifyURL = nil
                }
                return
            }
            
            guard httpResponse.statusCode == 200 else { return }
            
            let playbackResponse = try JSONDecoder().decode(CurrentPlaybackResponse.self, from: data)
            
            await MainActor.run {
                self.isPlaying = playbackResponse.is_playing
                
                let newTrackId = playbackResponse.item?.id
                if newTrackId != self.currentTrackId {
                    self.currentTrackId = newTrackId
                    self.currentTrackName = playbackResponse.item?.name
                    self.currentArtistName = playbackResponse.item?.artists.first?.name
                    
                    if let externalUrls = playbackResponse.item?.external_urls {
                        self.currentTrackSpotifyURL = externalUrls.spotify
                    }
                    
                    if let images = playbackResponse.item?.album?.images, !images.isEmpty {
                        let artwork = images.first(where: { $0.width == 300 }) ?? images.first
                        if let urlString = artwork?.url {
                            self.currentArtworkURL = URL(string: urlString)
                            print("Updated artwork for: \(self.currentTrackName ?? "Unknown")")
                        }
                    } else {
                        self.currentArtworkURL = nil
                    }
                }
            }
            
        } catch {
        }
    }
    
    // MARK: - Shuffle Control
    
    private func enableShuffle(on deviceId: String) async {
        await ensureValidToken()
        guard let accessToken = self.accessToken else { return }
        
        guard let url = URL(string: "\(SpotifyConfig.apiBaseURL)/me/player/shuffle?state=true&device_id=\(deviceId)") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                    print("Shuffle enabled")
                }
            }
        } catch {
        }
    }
    
    // MARK: - Playback Control
    
    func playTrack(trackId: String) async {
        await ensureValidToken()
        guard let accessToken = self.accessToken else { return }
        
        let devices = await getAvailableDevices()
        
        guard !devices.isEmpty else {
            print("No Spotify devices found")
            await MainActor.run {
                errorMessage = "Open Spotify app to play music"
            }
            return
        }
        
        let targetDevice: SpotifyDevice
        if let active = devices.first(where: { $0.is_active }) {
            targetDevice = active
            preferredDeviceId = active.id
        } else if let preferredId = preferredDeviceId,
                  let preferred = devices.first(where: { $0.id == preferredId }) {
            targetDevice = preferred
        } else {
            targetDevice = devices.first!
            preferredDeviceId = targetDevice.id
        }
        
        print("Playing track on: \(targetDevice.name)")
        
        var request = URLRequest(url: URL(string: "\(SpotifyConfig.apiBaseURL)/me/player/play?device_id=\(targetDevice.id)")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "uris": ["spotify:track:\(trackId)"]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                    print("Track playing")
                    await MainActor.run {
                        errorMessage = nil
                        isPlaying = true
                        startPlaybackPolling()
                    }
                } else if httpResponse.statusCode == 401 {
                    print("Token expired, retrying...")
                    await refreshAccessToken()
                    
                    if let newToken = self.accessToken {
                        request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        let (_, retryResponse) = try await URLSession.shared.data(for: request)
                        if let retryHttp = retryResponse as? HTTPURLResponse,
                           retryHttp.statusCode == 204 || retryHttp.statusCode == 200 {
                            await MainActor.run {
                                errorMessage = nil
                                isPlaying = true
                                startPlaybackPolling()
                            }
                        }
                    }
                } else {
                    print("Play failed: \(httpResponse.statusCode)")
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("Error: \(errorString)")
                    }
                }
            }
        } catch {
            print("Error: \(error)")
        }
    }
    
    func playPlaylist(playlistId: String) async {
        await ensureValidToken()
        guard let accessToken = self.accessToken else {
            print("No access token")
            return
        }
        
        let devices = await getAvailableDevices()
        
        guard !devices.isEmpty else {
            print("No Spotify devices found")
            await MainActor.run {
                errorMessage = "Open Spotify app to play music"
            }
            return
        }
        
        let targetDevice: SpotifyDevice
        if let active = devices.first(where: { $0.is_active }) {
            targetDevice = active
            preferredDeviceId = active.id
        } else if let preferredId = preferredDeviceId,
                  let preferred = devices.first(where: { $0.id == preferredId }) {
            targetDevice = preferred
        } else {
            targetDevice = devices.first!
            preferredDeviceId = targetDevice.id
        }
        
        await enableShuffle(on: targetDevice.id)
        
        let trackCount = await getPlaylistTrackCount(playlistId: playlistId) ?? 0
        let randomOffset = trackCount > 0 ? Int.random(in: 0..<trackCount) : 0
        
        print("Playing playlist on: \(targetDevice.name)")
        
        var request = URLRequest(url: URL(string: "\(SpotifyConfig.apiBaseURL)/me/player/play?device_id=\(targetDevice.id)")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "context_uri": "spotify:playlist:\(playlistId)",
            "offset": ["position": randomOffset],
            "position_ms": 0
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                    print("Playlist playing")
                    await MainActor.run {
                        errorMessage = nil
                        isPlaying = true
                        startPlaybackPolling()
                    }
                } else if httpResponse.statusCode == 401 {
                    print("Token expired, retrying...")
                    await refreshAccessToken()
                    
                    if let newToken = self.accessToken {
                        request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        let (_, retryResponse) = try await URLSession.shared.data(for: request)
                        if let retryHttp = retryResponse as? HTTPURLResponse,
                           retryHttp.statusCode == 204 || retryHttp.statusCode == 200 {
                            print("Playlist playing (retry)")
                            await MainActor.run {
                                errorMessage = nil
                                isPlaying = true
                                startPlaybackPolling()
                            }
                        }
                    }
                } else {
                    print("Play failed: \(httpResponse.statusCode)")
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("Error: \(errorString)")
                    }
                }
            }
        } catch {
            print("Error: \(error)")
        }
    }
    
    func pausePlayback() async {
        await ensureValidToken()
        guard let accessToken = self.accessToken else { return }
        
        var request = URLRequest(url: URL(string: "\(SpotifyConfig.apiBaseURL)/me/player/pause")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                    print("Paused")
                    await MainActor.run {
                        isPlaying = false
                        stopPlaybackPolling()
                    }
                } else if httpResponse.statusCode == 401 {
                    print("Token expired, retrying...")
                    await refreshAccessToken()
                    
                    if let newToken = self.accessToken {
                        request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        let (_, retryResponse) = try await URLSession.shared.data(for: request)
                        if let retryHttp = retryResponse as? HTTPURLResponse,
                           retryHttp.statusCode == 204 || retryHttp.statusCode == 200 {
                            await MainActor.run {
                                isPlaying = false
                                stopPlaybackPolling()
                            }
                        }
                    }
                }
            }
        } catch {
            print("Error pausing: \(error)")
        }
    }
    
    func resumePlayback() async {
        await ensureValidToken()
        guard let accessToken = self.accessToken else { return }
        
        var request = URLRequest(url: URL(string: "\(SpotifyConfig.apiBaseURL)/me/player/play")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                    print("Resumed playback")
                    await MainActor.run {
                        isPlaying = true
                        startPlaybackPolling()
                    }
                } else if httpResponse.statusCode == 401 {
                    print("Token expired, retrying...")
                    await refreshAccessToken()
                    
                    if let newToken = self.accessToken {
                        request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        let (_, retryResponse) = try await URLSession.shared.data(for: request)
                        if let retryHttp = retryResponse as? HTTPURLResponse,
                           retryHttp.statusCode == 204 || retryHttp.statusCode == 200 {
                            await MainActor.run {
                                isPlaying = true
                                startPlaybackPolling()
                            }
                        }
                    }
                }
            }
        } catch {
            print("Error resuming: \(error)")
        }
    }
}

// MARK: - Response Models

struct TokenResponse: Codable {
    let access_token: String
    let token_type: String
    let expires_in: Int
    let refresh_token: String?
    let scope: String
}

struct SpotifyErrorResponse: Codable {
    let error: String
    let error_description: String?
}

// MARK: - Playlist Models

struct PlaylistResponse: Codable {
    let items: [SpotifyPlaylist]
}

struct SpotifyPlaylist: Codable, Identifiable {
    let id: String
    let name: String
    let images: [SpotifyImage]?
    
    var imageURL: String? {
        images?.first?.url
    }
}

struct SpotifyImage: Codable {
    let url: String
    let height: Int?
    let width: Int?
}

// MARK: - Track Models

struct TrackSearchResponse: Codable {
    let tracks: TrackSearchResults
}

struct TrackSearchResults: Codable {
    let items: [SpotifyTrack]
}

struct SpotifyTrack: Codable, Identifiable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let uri: String
    
    var artistNames: String {
        artists.map { $0.name }.joined(separator: ", ")
    }
    
    var displayName: String {
        "\(name) - \(artistNames)"
    }
}

struct SpotifyArtist: Codable {
    let name: String
}

// MARK: - Device Models

struct DeviceResponse: Codable {
    let devices: [SpotifyDevice]
}

struct SpotifyDevice: Codable, Identifiable {
    let id: String
    let name: String
    let type: String
    let is_active: Bool
}

// MARK: - Current Playback Models

struct CurrentPlaybackResponse: Codable {
    let is_playing: Bool
    let item: CurrentTrack?
}

struct CurrentTrack: Codable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum?
    let external_urls: SpotifyExternalURLs?
}

struct SpotifyAlbum: Codable {
    let images: [SpotifyImage]?
}

struct SpotifyExternalURLs: Codable {
    let spotify: String?
}

// MARK: - Data Extension for Base64URL Encoding

extension Data {
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
