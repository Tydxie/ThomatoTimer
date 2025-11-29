//
//  AppDelegate.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/26.
//

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running even when window is closed
        print("🪟 Window closed - app continues running in menu bar")
        return false
    }
}
