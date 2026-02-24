//
//  Thomato_TimerApp.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/24.
//  Updated: 2026/01/09
//

import SwiftUI
import UserNotifications



@MainActor
final class MacAppState: ObservableObject {
    static var shared: MacAppState?

    let timerViewModel = TimerViewModel()
    let spotifyManager = SpotifyManager()
    let appleMusicManager = AppleMusicManager()
    let menuBarManager = MenuBarManager()
    
    init() {
        MacAppState.shared = self
        
        timerViewModel.spotifyManager = spotifyManager
        timerViewModel.appleMusicManager = appleMusicManager
        timerViewModel.selectedService = .none
        
        menuBarManager.setup(
            viewModel: timerViewModel,
            spotifyManager: spotifyManager,
            appleMusicManager: appleMusicManager
        )
        
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



@main
@MainActor
struct Thomato_TimerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var macState = MacAppState()
   
    
    var body: some Scene {
        
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
       
    }
    
   
}



