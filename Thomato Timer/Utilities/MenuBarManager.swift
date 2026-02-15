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
    
    @AppStorage("keepWindowOpen") private var keepWindowOpen: Bool = false {
        didSet {
            if let popover = popover, popover.isShown {
                popover.behavior = keepWindowOpen ? .applicationDefined : .transient
                
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
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "timer",
                                   accessibilityDescription: "Thomodoro")
            button.title = ""
            button.action = #selector(togglePopover(_:))
            button.target = self
            
            self.attemptAutoOpen(retryCount: 0)
        }
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMenuBarTitle()
        }
    }
    
    private func attemptAutoOpen(retryCount: Int) {
        let maxRetries = 5
        let baseDelay: TimeInterval = 1.5
        let retryDelay = baseDelay + (TimeInterval(retryCount) * 0.4)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            guard let self = self,
                  let button = self.statusItem?.button else {
                print("Status button not ready (attempt \(retryCount + 1))")
                if retryCount < maxRetries {
                    self?.attemptAutoOpen(retryCount: retryCount + 1)
                }
                return
            }
            
            guard button.bounds.width > 0 && button.bounds.height > 0 else {
                print("Button bounds not ready (attempt \(retryCount + 1))")
                if retryCount < maxRetries {
                    self.attemptAutoOpen(retryCount: retryCount + 1)
                }
                return
            }
            
            guard button.window != nil else {
                print("Button window not ready (attempt \(retryCount + 1))")
                if retryCount < maxRetries {
                    self.attemptAutoOpen(retryCount: retryCount + 1)
                }
                return
            }
            
            button.needsLayout = true
            button.layoutSubtreeIfNeeded()
            
            print("Attempting to open popover (attempt \(retryCount + 1))")
            self.showPopover(button)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                
                if let popover = self.popover, popover.isShown {
                    print("Popover successfully shown")
                } else {
                    print("Popover failed to show (attempt \(retryCount + 1))")
                    if retryCount < maxRetries {
                        self.attemptAutoOpen(retryCount: retryCount + 1)
                    }
                }
            }
        }
    }
    
    func checkAndCloseIfNeeded() {
        if !keepWindowOpen, let popover = popover, popover.isShown {
            popover.close()
            self.popover = nil
        }
    }
    
    // MARK: - Popover Handling
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        print("Toggle popover called")
        
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
            let appleMusicManager = appleMusicManager
        else {
            print("Missing viewModel or managers")
            return
        }
        
        guard let button = (sender as? NSButton) ?? statusItem?.button else {
            print("No button available")
            return
        }
        
        guard button.bounds.width > 0 && button.bounds.height > 0 else {
            print("Invalid button bounds")
            return
        }
        
        button.needsLayout = true
        button.layoutSubtreeIfNeeded()
        
        print("Showing popover from button at bounds: \(button.bounds)")
        
        let popover = NSPopover()
        popover.behavior = keepWindowOpen ? .applicationDefined : .transient
        popover.animates = true
        
        popover.contentSize = NSSize(
            width: MacPopoverLayout.width,
            height: MacPopoverLayout.height
        )
        
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
        
        DispatchQueue.main.async {
            if let popoverWindow = popover.contentViewController?.view.window {
                popoverWindow.level = .statusBar
                popoverWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                NSApp.activate(ignoringOtherApps: true)
                popoverWindow.makeKey()
                popoverWindow.orderFrontRegardless()
            }
        }
    }
    
    private func updateMenuBarTitle() {
        statusItem?.button?.title = ""
    }
}
#endif  // os(macOS)
