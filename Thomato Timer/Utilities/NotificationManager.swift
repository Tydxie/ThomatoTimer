//
//  NotificationManager.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/26.
//

import Foundation
import UserNotifications

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorization()
    }
    
    func requestAuthorization() {
        print("🔔 Requesting notification permission...")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
                if let error = error {
                    print("❌ Notification error: \(error)")
                } else {
                    print(granted ? "✅ Notifications GRANTED" : "⚠️ Notifications DENIED")
                }
            }
        }
    }
    
    private func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
                print("🔔 Current notification status: \(settings.authorizationStatus.rawValue)")
            }
        }
    }
    
    func sendPhaseCompleteNotification(phase: TimerPhase, nextPhase: TimerPhase) {
        print("🔔 Trying to send notification for phase: \(phase)")
        
        guard isAuthorized else {
            print("⚠️ Notifications NOT authorized!")
            return
        }
        
        let content = UNMutableNotificationContent()
        
        switch phase {
        case .warmup:
            content.title = "Warmup Complete!"
            content.body = "Time to start working 💪"
        case .work:
            content.title = "Work Session Complete!"
            content.body = "Great job! Time for a break ☕"
        case .shortBreak:
            content.title = "Break Over!"
            content.body = "Ready to get back to work? 🍅"
        case .longBreak:
            content.title = "Long Break Complete!"
            content.body = "Refreshed and ready? Let's go! 🚀"
        }
        
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        print("🔔 Sending notification: \(content.title)")
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send: \(error)")
            } else {
                print("✅ Notification sent!")
            }
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("🔔 Notification appearing now!")
        completionHandler([.banner, .sound])
    }
}
