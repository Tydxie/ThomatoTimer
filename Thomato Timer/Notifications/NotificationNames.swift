//
//  NotificationNames.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/12/22.
//

import Foundation

extension Notification.Name {
    static let toggleTimer = Notification.Name("toggleTimer")
    static let resetTimer = Notification.Name("resetTimer")
    static let skipTimer = Notification.Name("skipTimer")
    
    // Widget button notifications
    static let toggleTimerFromWidget = Notification.Name("toggleTimerFromWidget")
    static let skipTimerFromWidget = Notification.Name("skipTimerFromWidget")
}
