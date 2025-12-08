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
    
    func setup(
        viewModel: TimerViewModel,
        spotifyManager: SpotifyManager,
        appleMusicManager: AppleMusicManager
    ) {
        self.viewModel = viewModel
        self.spotifyManager = spotifyManager
        self.appleMusicManager = appleMusicManager
        
        // Simple icon-only item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Thomodoro")
            button.title = ""
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        // Keep title empty (icon-only), like before
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMenuBarTitle()
        }
    }
    
    // MARK: - Popover Handling
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        if let popover = popover, popover.isShown {
            // Close and reset so next open creates a fresh popover + SwiftUI view
            popover.performClose(sender)
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
        
        // 🔁 Always create a fresh popover & hosting controller
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 520)
        
        let rootView = MacMenuPopoverView(
            viewModel: viewModel,
            spotifyManager: spotifyManager,
            appleMusicManager: appleMusicManager
        )
        popover.contentViewController = NSHostingController(rootView: rootView)
        
        self.popover = popover
        
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // Still keeps the icon-only style
    private func updateMenuBarTitle() {
        guard let button = statusItem?.button else { return }
        button.title = ""
    }
}
#endif
