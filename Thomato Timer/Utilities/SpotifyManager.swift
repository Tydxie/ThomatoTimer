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
final class SpotifyManager {
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
    
    // MARK: - Authentication Flow
    
    /// Step 1: Generate PKCE values and open Spotify authorization page
    @MainActor
    func authenticate() {
        // Generate PKCE values
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let stateValue = generateState()
        
        // Store for later use
        self.codeVerifier = verifier
        self.state = stateValue
        
        // Build authorization URL
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
        
        // Open in browser
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
    
    /// Step 2: Handle redirect callback from Spotify
    func handleRedirect(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            await MainActor.run {
                errorMessage = "Invalid callback URL"
            }
            return
        }
        
        // Extract query parameters
        let queryItems = components.queryItems ?? []
        
        // Check for error
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            await MainActor.run {
                errorMessage = "Authorization failed: \(error)"
            }
            return
        }
        
        // Extract code and state
        guard let code = queryItems.first(where: { $0.name == "code" })?.value,
              let returnedState = queryItems.first(where: { $0.name == "state" })?.value else {
            await MainActor.run {
                errorMessage = "Missing code or state in callback"
            }
            return
        }
        
        // Verify state matches (CSRF protection)
        guard returnedState == self.state else {
            await MainActor.run {
                errorMessage = "State mismatch - possible CSRF attack"
            }
            return
        }
        
        // Exchange code for token
        guard let verifier = self.codeVerifier else {
            await MainActor.run {
                errorMessage = "Code verifier not found"
            }
            return
        }
        
        await exchangeCodeForToken(code: code, codeVerifier: verifier)
    }
    
    /// Step 3: Exchange authorization code for access token
    private func exchangeCodeForToken(code: String, codeVerifier: String) async {
        var request = URLRequest(url: URL(string: SpotifyConfig.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Build request body
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
            
            // Update state on main actor
            await MainActor.run {
                self.accessToken = tokenResponse.access_token
                self.refreshToken = tokenResponse.refresh_token
                self.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
                self.isAuthenticated = true
                self.errorMessage = nil
                
                // Clear PKCE values
                self.codeVerifier = nil
                self.state = nil
            }
            
            // Auto-fetch playlists
            await fetchPlaylists()
            
        } catch {
            await MainActor.run {
                errorMessage = "Network error: \(error.localizedDescription)"
            }
        }
    }
    
    /// Refresh the access token using refresh token
    func refreshAccessToken() async {
        guard let refreshToken = self.refreshToken else {
            await MainActor.run {
                errorMessage = "No refresh token available"
            }
            return
        }
        
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
                await MainActor.run {
                    errorMessage = "Token refresh failed"
                }
                return
            }
            
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            
            await MainActor.run {
                self.accessToken = tokenResponse.access_token
                self.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
                
                // Update refresh token if provided
                if let newRefreshToken = tokenResponse.refresh_token {
                    self.refreshToken = newRefreshToken
                }
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Refresh error: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - PKCE Helper Functions
    
    /// Generate cryptographically random code verifier (43-128 chars)
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
    
    /// Generate code challenge from verifier using SHA256
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hashed = SHA256.hash(data: data)
        return Data(hashed).base64URLEncodedString()
    }
    
    /// Generate random state for CSRF protection
    private func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
    
    // MARK: - Testing
    func testConfiguration() -> String {
        """
        ✅ Spotify Configuration (Works as of 11/25/2025)
        
        Client ID: \(SpotifyConfig.clientID.prefix(15))...
        Redirect URI: \(SpotifyConfig.redirectURI)
        Auth Method: PKCE (S256)
        Scopes: \(SpotifyConfig.scopes.joined(separator: ", "))
        
        Status: \(isAuthenticated ? "✅ Authenticated" : "⏳ Not authenticated")
        """
    }
    
    // MARK: - Playlist Management
    
    /// Fetch user's playlists from Spotify
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
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
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
    
    // MARK: - Track Search
    
    /// Search for tracks
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
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
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
    
    /// Get available devices
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

    /// Check if token is expired or about to expire (within 5 minutes)
    private func isTokenExpired() -> Bool {
        guard let expirationDate = tokenExpirationDate else { return true }
        return Date().addingTimeInterval(300) >= expirationDate  // 5 min buffer
    }

    /// Ensure we have a valid token, refresh if needed
    private func ensureValidToken() async {
        if isTokenExpired() {
            print("🔄 Token expired, refreshing...")
            await refreshAccessToken()
        }
    }
    
    // MARK: - Playback Control
    
    /// Play a specific track
    func playTrack(trackId: String) async {
        await ensureValidToken()
        guard let accessToken = self.accessToken else { return }
        
        // Get available devices
        let devices = await getAvailableDevices()
        
        guard !devices.isEmpty else {
            print("❌ No Spotify devices found. User needs to open Spotify app.")
            await MainActor.run {
                errorMessage = "Open Spotify app to play music"
            }
            return
        }
        
        // Use active device, or first available
        let targetDevice = devices.first(where: { $0.is_active }) ?? devices.first!
        
        print("🎵 Playing track on device: \(targetDevice.name)")
        
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
                    print("✅ Track playing successfully")
                    await MainActor.run {
                        errorMessage = nil
                    }
                } else {
                    print("❌ Play failed: \(httpResponse.statusCode)")
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("Error: \(errorString)")
                    }
                }
            }
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    /// Play a playlist
    func playPlaylist(playlistId: String) async {
        await ensureValidToken()
        guard let accessToken = self.accessToken else { return }
        
        // Get available devices
        let devices = await getAvailableDevices()
        
        guard !devices.isEmpty else {
            print("❌ No Spotify devices found. User needs to open Spotify app.")
            await MainActor.run {
                errorMessage = "Open Spotify app to play music"
            }
            return
        }
        
        // Use active device, or first available
        let targetDevice = devices.first(where: { $0.is_active }) ?? devices.first!
        
        print("🎵 Playing playlist on device: \(targetDevice.name)")
        
        var request = URLRequest(url: URL(string: "\(SpotifyConfig.apiBaseURL)/me/player/play?device_id=\(targetDevice.id)")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "context_uri": "spotify:playlist:\(playlistId)",
            "offset": ["position": 0],
            "position_ms": 0
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 204 || httpResponse.statusCode == 200 {
                    print("✅ Playlist playing successfully")
                    await MainActor.run {
                        errorMessage = nil
                    }
                } else {
                    print("❌ Play failed: \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    /// Pause playback
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
                    print("✅ Paused successfully")
                }
            }
        } catch {
            print("❌ Error pausing: \(error)")
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

// MARK: - Data Extension for Base64URL Encoding

extension Data {
    /// Base64URL encoding (RFC 4648) - compatible with PKCE
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
