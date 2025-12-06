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
    private var viewModel: TimerViewModel?
    
    func setup(viewModel: TimerViewModel) {
        self.viewModel = viewModel
        
        // Use square length so it's just the icon width
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Thomodoro")
            button.title = "" // 🔹 ensure no text from the start
            button.action = #selector(toggleWindow)
            button.target = self
        }
        
        updateMenuBarTitle()
        
        // You technically don't need this timer anymore,
        // but if you keep it, it will just keep the title empty.
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMenuBarTitle()
        }
    }
    
    @objc private func toggleWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "Thomodoro" }) {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    private func updateMenuBarTitle() {
        // 🔹 Always icon-only, no emoji, no timer, no text
        guard let button = statusItem?.button else { return }
        button.title = ""
    }
}
#endif
