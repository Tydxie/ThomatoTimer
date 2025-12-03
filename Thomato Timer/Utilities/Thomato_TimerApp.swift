//
//  Thomato_TimerApp.swift
//  Thomodoro
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
        // Set delegate before requesting authorization (ios notifications don't work otherwise)
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

// Notification Names

extension Notification.Name {
    static let toggleTimer = Notification.Name("toggleTimer")
    static let resetTimer = Notification.Name("resetTimer")
    static let skipTimer = Notification.Name("skipTimer")
}
