//
//  AppDelegate.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/26.
//

#if os(macOS)
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    
    /// Keep app running even when the last window is closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        print("🪟 Window closed - app continues running in menu bar")
        return false
    }
    
    /// Handle custom URL schemes (Spotify redirect)
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        print("🎵 AppDelegate received URL (macOS): \(url)")
        
        Task { @MainActor in
            if let appState = MacAppState.shared {
                await appState.spotifyManager.handleRedirect(url: url)
            }
        }
    }
}
#endif
 
