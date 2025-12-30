//
//  Thomato_TimerApp.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/24.
//

import SwiftUI
import UserNotifications

// MARK: - macOS App State (menu bar + timer wiring)

#if os(macOS)
@MainActor
final class MacAppState: ObservableObject {
    // Shared instance so AppDelegate can reach the same state
    static var shared: MacAppState?

    let timerViewModel = TimerViewModel()
    let spotifyManager = SpotifyManager()
    let appleMusicManager = AppleMusicManager()
    let menuBarManager = MenuBarManager()
    
    init() {
        // Expose this instance globally (for AppDelegate URL handling)
        MacAppState.shared = self
        
        // Wire music managers into the timer view model
        timerViewModel.spotifyManager = spotifyManager
        timerViewModel.appleMusicManager = appleMusicManager
        timerViewModel.selectedService = .none
        
        // Set up the menu bar icon + popover UI
        menuBarManager.setup(
            viewModel: timerViewModel,
            spotifyManager: spotifyManager,
            appleMusicManager: appleMusicManager
        )
        
        // Hook up NotificationCenter commands for Start/Pause, Reset, Skip
        NotificationCenter.default.addObserver(
            forName: .toggleTimer,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.timerViewModel.toggleTimer()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .resetTimer,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.timerViewModel.reset()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .skipTimer,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.timerViewModel.timerState.isRunning else { return }
                self.timerViewModel.skipToNext()
            }
        }
    }
}
#endif

// MARK: - App Entry

@main
@MainActor
struct Thomato_TimerApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var macState = MacAppState()
    #else
    @StateObject private var timerViewModel = TimerViewModel()
    @State private var spotifyManager = SpotifyManager()
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Configure URLCache for memory-only (no disk storage for compliance)
        URLCache.shared = URLCache(
            memoryCapacity: 50_000_000,  // 50MB memory cache
            diskCapacity: 0,             // No disk storage
            diskPath: nil
        )
        
        // 🔥 Setup crash logging
        CrashLogger.shared.setup()
        
        // Set notification delegate FIRST, then request authorization
        NotificationManager.shared.setupDelegate()
        NotificationManager.shared.requestAuthorization()
        
        print("🏗️ App init() called - creating timerViewModel")
    }
    #endif
    
    var body: some Scene {
        #if os(macOS)
        // No main window: app lives in the menu bar.
        // We still need a scene for commands (menu bar shortcuts).
        Settings {
            EmptyView()
        }
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
        // iOS: regular window using ContentView
        WindowGroup {
            ContentView(
                viewModel: timerViewModel,
                spotifyManager: spotifyManager
            )
                .onAppear {
                    // 🔥 Restore timer state if app was killed
                    timerViewModel.restoreStateIfNeeded()
                }
                .onOpenURL { url in
                    handleDeepLink(url: url, timerViewModel: timerViewModel, spotifyManager: spotifyManager)
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                timerViewModel.handleBackgroundTransition()
            case .active:
                timerViewModel.handleForegroundTransition()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        #endif
    }
    
    // MARK: - Deep Link Handler
    
    #if os(iOS)
    private func handleDeepLink(url: URL, timerViewModel: TimerViewModel, spotifyManager: SpotifyManager) {
        print("🔗 Received URL: \(url)")
        
        // Check if it's a Spotify callback
        if url.scheme == "thomato-timer" && url.host == "callback" {
            print("🎵 Spotify callback detected")
            Task {
                await spotifyManager.handleRedirect(url: url)
            }
            return
        }
        
        // Handle Live Activity button URLs
        guard url.scheme == "thomato-timer" else { return }
        
        switch url.host {
        case "toggle":
            print("🔗 Deep link: Toggle timer")
            timerViewModel.toggleTimer()
            
        case "pause":
            print("🔗 Deep link: PAUSE timer")
            print("   Current state BEFORE: isRunning=\(timerViewModel.timerState.isRunning), isPaused=\(timerViewModel.timerState.isPaused)")
            // Only pause if currently running
            if timerViewModel.timerState.isRunning && !timerViewModel.timerState.isPaused {
                print("   ✅ Calling toggleTimer() to pause")
                timerViewModel.toggleTimer()
            } else {
                print("   ⚠️ Already paused or not running - skipping")
            }
            
        case "resume":
            print("🔗 Deep link: RESUME timer")
            print("   Current state BEFORE: isRunning=\(timerViewModel.timerState.isRunning), isPaused=\(timerViewModel.timerState.isPaused)")
            // Only resume if currently paused
            if timerViewModel.timerState.isPaused {
                print("   ✅ Calling toggleTimer() to resume")
                timerViewModel.toggleTimer()
            } else {
                print("   ⚠️ Already running or not paused - skipping")
            }
            
        case "skip":
            print("🔗 Deep link: Skip phase")
            if timerViewModel.timerState.isRunning {
                timerViewModel.skipToNext()
            }
            
        case "test":
            print("🔗 Deep link: Test button worked! ✅")
            
        default:
            print("🔗 Unknown deep link: \(url.host ?? "none")")
        }
    }
    #endif
}
