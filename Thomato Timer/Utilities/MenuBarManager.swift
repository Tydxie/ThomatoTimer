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
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Thomato Timer")
            button.action = #selector(toggleWindow)
            button.target = self
        }
        
        updateMenuBarTitle()
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMenuBarTitle()
        }
    }
    
    @objc private func toggleWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "Thomato Timer" }) {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    private func updateMenuBarTitle() {
        guard let viewModel = viewModel else { return }
        
        if let button = statusItem?.button {
            let emoji: String
            switch viewModel.timerState.currentPhase {
            case .warmup:
                emoji = "⏳"
            case .work:
                emoji = "💼"
            case .shortBreak, .longBreak:
                emoji = "☕"
            }
            
            if viewModel.timerState.isRunning {
                let minutes = Int(viewModel.timerState.timeRemaining) / 60
                let seconds = Int(viewModel.timerState.timeRemaining) % 60
                button.title = String(format: "%@ %02d:%02d", emoji, minutes, seconds)
            } else {
                button.title = "\(emoji) Thomato"
            }
        }
    }
}
#endif
