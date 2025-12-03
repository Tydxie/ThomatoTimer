//
//  Thomato_TimerApp.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/24.
//

import SwiftUI
import UserNotifications

@main
@MainActor
struct Thomato_TimerApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    
    @State private var spotifyManager = SpotifyManager()
    
    init() {
        // Configure URLCache for memory-only (no disk storage for compliance)
        // This allows fast re-displays during the session without storing artwork to disk
        URLCache.shared = URLCache(
            memoryCapacity: 50_000_000,  // 50MB memory cache
            diskCapacity: 0,              // No disk storage
            diskPath: nil
        )
        
        // Set notification delegate FIRST, then request authorization
        NotificationManager.shared.setupDelegate()
        NotificationManager.shared.requestAuthorization()
    }
    
    var body: some Scene {
        #if os(macOS)
        Window("Thomodoro", id: "main") {
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
        .commands {
            CommandGroup(replacing: .newItem) { }
            
            CommandMenu("Timer") {
                Button("Start/Pause") {
                    NotificationCenter.default.post(name: .toggleTimer, object: nil)
                }
                .keyboardShortcut(.space, modifiers: [])
                
                Button("Reset") {
                    NotificationCenter.default.post(name: .resetTimer, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [])
                
                Button("Skip Phase") {
                    NotificationCenter.default.post(name: .skipTimer, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
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

// MARK: - Notification Names

extension Notification.Name {
    static let toggleTimer = Notification.Name("toggleTimer")
    static let resetTimer = Notification.Name("resetTimer")
    static let skipTimer = Notification.Name("skipTimer")
}
