//
//  MenuBarManager.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/26.
//

#if os(macOS)
import SwiftUI
import AppKit

class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    private var viewModel: TimerViewModel?
    private var spotifyManager: SpotifyManager?
    private var appleMusicManager: AppleMusicManager?
    
    // 🔹 This is the same value edited in SettingsView
    @AppStorage("keepWindowOpen") private var keepWindowOpen: Bool = false {
        didSet {
            // If the dropdown is already shown, update its behavior instantly
            if let popover = popover, popover.isShown {
                popover.behavior = keepWindowOpen ? .applicationDefined : .transient
                
                // If switching keep-open OFF, force close the dropdown screen
                // User will need to reopen it with the new behavior
                if !keepWindowOpen {
                    popover.close()
                    self.popover = nil
                }
            }
        }
    }
    
    func setup(
        viewModel: TimerViewModel,
        spotifyManager: SpotifyManager,
        appleMusicManager: AppleMusicManager
    ) {
        self.viewModel = viewModel
        self.spotifyManager = spotifyManager
        self.appleMusicManager = appleMusicManager
        
        // Menu bar item (icon only)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "timer",
                                   accessibilityDescription: "Thomodoro")
            button.title = ""
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        // Keeps icon-only behavior
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMenuBarTitle()
        }
    }
    
    // 🔥 NEW: Manual check method called from SettingsView
    func checkAndCloseIfNeeded() {
        if !keepWindowOpen, let popover = popover, popover.isShown {
            popover.close()
            self.popover = nil
        }
    }
    
    // MARK: - Popover Handling
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        if let popover = popover, popover.isShown {
            popover.close()
            self.popover = nil
        } else {
            showPopover(sender)
        }
    }
    
    
    private func showPopover(_ sender: AnyObject?) {
        guard
            let viewModel = viewModel,
            let spotifyManager = spotifyManager,
            let appleMusicManager = appleMusicManager,
            let button = statusItem?.button
        else { return }
        
        // Always create a fresh popover
        let popover = NSPopover()
        popover.behavior = keepWindowOpen ? .applicationDefined : .transient
        popover.animates = true
        
        popover.contentSize = NSSize(
            width: MacPopoverLayout.width,
            height: MacPopoverLayout.height
        )
        
        // IMPORTANT: pass MenuBarManager into the SwiftUI view
        let rootView = MacMenuPopoverView(
            viewModel: viewModel,
            spotifyManager: spotifyManager,
            appleMusicManager: appleMusicManager
        )
        .environmentObject(self)
        
        popover.contentViewController = NSHostingController(rootView: rootView)
        self.popover = popover
        
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        
        // 🔥 KEY FIX: Force the popover window to become key and activate
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
            
            // Optional: Make the view first responder for keyboard events
            popover.contentViewController?.view.window?.makeFirstResponder(
                popover.contentViewController?.view
            )
        }
    }
    
    
    private func updateMenuBarTitle() {
        statusItem?.button?.title = ""
    }
}
#endif  // os(macOS)
