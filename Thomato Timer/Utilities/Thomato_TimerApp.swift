//
//  Thomato_TimerApp.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/24.
//  Updated: 2026/01/09
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
        // Making this instance visible globally (for AppDelegate URL handling)
        MacAppState.shared = self
        
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
                guard let self, self.timerViewModel.timerState.runState == .running else { return }
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
        
        URLCache.shared = URLCache(
            memoryCapacity: 50_000_000,
            diskCapacity: 0,             // No disk storage (easier for apple compliance)
            diskPath: nil
        )
        
        CrashLogger.shared.setup()
        
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        
        NotificationDelegate.setupNotificationCategories()
        
        // Set notification delegate and request authorization
        NotificationManager.shared.setupDelegate()
        NotificationManager.shared.requestAuthorization()
        
        print("App init() called - notification system configured")
    }
    #endif
    
    var body: some Scene {
        #if os(macOS)
        // We still need a scene for menu bar shortcuts.
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
        WindowGroup {
            ContentView(
                viewModel: timerViewModel,
                spotifyManager: spotifyManager
            )
                .onAppear {
                    NotificationDelegate.shared.timerViewModel = timerViewModel
                    
                    // Restore timer state if app was killed by IOS
                    timerViewModel.restoreStateIfNeeded()
                }
                .onOpenURL { url in
                    handleDeepLink(url: url, timerViewModel: timerViewModel, spotifyManager: spotifyManager)
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            print("📱 Scene phase changed: \(oldPhase) → \(newPhase)")
            switch newPhase {
            case .background:
                print("📱 → BACKGROUND")
                timerViewModel.handleBackgroundTransition()
            case .active:
                print("📱 → ACTIVE")
                timerViewModel.handleForegroundTransition()
            case .inactive:
                print("📱 → INACTIVE (screen locked or app switching)")
                // Set background time when going inactive (screen lock)
                if timerViewModel.timerState.runState == .running {
                    timerViewModel.markAsBackgrounded()
                }
            @unknown default:
                break
            }
        }
        #endif
    }
    
    // MARK: - Deep Link Handler
    
    #if os(iOS)
    private func handleDeepLink(url: URL, timerViewModel: TimerViewModel, spotifyManager: SpotifyManager) {
        print("Received URL: \(url)")
        
        // Check if it's a Spotify callback
        if url.scheme == "thomato-timer" && url.host == "callback" {
            print("Spotify callback detected")
            Task {
                await spotifyManager.handleRedirect(url: url)
            }
            return
        }
        
        // Handle Live Activity button URLs
        guard url.scheme == "thomato-timer" else { return }
        
        switch url.host {
        case "toggle":
            print("Deep link: Toggle timer")
            timerViewModel.toggleTimer()
            
        case "pause":
            print("Pause timer")
            print("Current runState: \(timerViewModel.timerState.runState)")
            // Only pause if currently running
            if timerViewModel.timerState.runState == .running {
                print("Calling toggleTimer() to pause")
                timerViewModel.toggleTimer()
            } else {
                print("Not running - skipping")
            }
            
        case "resume":
            print("Resume timer")
            print("Current runState: \(timerViewModel.timerState.runState)")
            // Only resume if currently paused
            if timerViewModel.timerState.runState == .paused {
                print(" Calling toggleTimer() to resume")
                timerViewModel.toggleTimer()
            } else {
                print(" Not paused - skipping")
            }
            
        case "skip":
            print("Skip phase")
            if timerViewModel.timerState.runState == .running {
                timerViewModel.skipToNext()
            }
            
        case "test":
            print("Test button worked!")
            
        default:
            print("Unknown deep link: \(url.host ?? "none")")
        }
    }
    #endif
}

// MARK: - Notification Delegate with Push Notification Support

#if os(iOS)
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    weak var timerViewModel: TimerViewModel?
    
    // MARK: - Notification Categories Setup
    
    static func setupNotificationCategories() {

        let continueAction = UNNotificationAction(
            identifier: "CONTINUE_ACTION",
            title: "Continue",
            options: [.foreground]  // Opens app
        )
        
        let skipAction = UNNotificationAction(
            identifier: "SKIP_ACTION",
            title: "Skip",
            options: [.foreground]
        )
        
        let pauseAction = UNNotificationAction(
            identifier: "PAUSE_ACTION",
            title: "Pause",
            options: []  // Doesn't open app
        )
        
        
        let timerCompleteCategory = UNNotificationCategory(
            identifier: "TIMER_COMPLETE",
            actions: [continueAction, skipAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        let timerRunningCategory = UNNotificationCategory(
            identifier: "TIMER_RUNNING",
            actions: [pauseAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            timerCompleteCategory,
            timerRunningCategory
        ])
        
        print("Notification categories configured with actions")
    }
    
    // MARK: - Delegate Methods
    
    // Called when notification is delivered while app is in FOREGROUND
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("Notification delivered while app in foreground")
        
        let categoryId = notification.request.content.categoryIdentifier
        
        if categoryId == "TIMER_COMPLETE" {
            print("Timer completion notification while in foreground")
            
            // Show notification banner even in foreground
            completionHandler([.banner, .sound, .badge])
            
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay (testing)
                self.timerViewModel?.updateLiveActivity()
            }
        } else {
            // Regular notification
            completionHandler([.banner, .sound])
        }
    }
    
    // Called when user taps notification OR when notification is delivered while BACKGROUNDED
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("Notification response received")
        print("Action: \(response.actionIdentifier)")
        
        let notification = response.notification
        let categoryId = notification.request.content.categoryIdentifier
        let actionId = response.actionIdentifier
        
        Task { @MainActor in
            guard let viewModel = self.timerViewModel else {
                print("No timerViewModel available")
                completionHandler()
                return
            }
            
        
            switch actionId {
            case "CONTINUE_ACTION":
                print("User tapped CONTINUE - app opening")
                
                // Give it a moment to fully wake up
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s (testing)
                
                viewModel.updateLiveActivity()
                print("Continue action complete")
                
            case "SKIP_ACTION":
                print("User tapped SKIP")
                if viewModel.timerState.runState == .running {
                    viewModel.skipToNext()
                    print("Skipped to next phase")
                }
                
            case "PAUSE_ACTION":
                print("User tapped PAUSE")
                if viewModel.timerState.runState == .running {
                    viewModel.toggleTimer()
                    print("Timer paused")
                }
                
            case UNNotificationDefaultActionIdentifier:
                // User tapped the notification body (not an action button)
                print("User tapped notification - opening app")
                
                if categoryId == "TIMER_COMPLETE" {
                    print("Timer completion notification tapped")
                    
                    // Give app time to fully wake and restore state
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                    
                    // The foreground transition will handle phase detection and transition
                    // Just make sure Live Activity is updated
                    viewModel.updateLiveActivity()
                    
                    print("App opened, state should be restored via foreground transition")
                }
                
            case UNNotificationDismissActionIdentifier:
                print("ℹ️ User dismissed notification")
                
            default:
                print("Unknown action: \(actionId)")
            }
            
            completionHandler()
        }
    }
}
#endif
