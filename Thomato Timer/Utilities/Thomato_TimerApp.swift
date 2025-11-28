//
//  Thomato_TimerApp.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/24.
//

import SwiftUI

@main
@MainActor
struct Thomato_TimerApp: App {
    @State private var spotifyManager = SpotifyManager()
    
    var body: some Scene {
        #if os(macOS)
        Window("Thomato Timer", id: "main") {
            ContentView(spotifyManager: spotifyManager)
                .onOpenURL { url in
                    print("🎵 App received URL: \(url)")
                    Task {
                        await spotifyManager.handleRedirect(url: url)
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()  // Removes File > New Window
        #else
        WindowGroup {
            ContentView(spotifyManager: spotifyManager)
                .onOpenURL { url in
                    print("🎵 App received URL: \(url)")
                    Task {
                        await spotifyManager.handleRedirect(url: url)
                    }
                }
        }
        #endif
    }
}
