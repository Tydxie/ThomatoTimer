//
//  NotificationManager.swift
//  Thomato Timer
//
//  Created by Thomas Xie on 2025/11/26.
//  Refactored: 2025/12/30 - Enhanced with notification categories
//

import Foundation
import UserNotifications

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    
    private override init() {
        super.init()
        checkAuthorization()
    }
    
    func setupDelegate() {
        UNUserNotificationCenter.current().delegate = self
        print("Notification delegate set")
    }
    
    func requestAuthorization() {
        print("Requesting notification permission...")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
                if let error = error {
                    print("Notification error: \(error)")
                } else {
                    print(granted ? "Notifications GRANTED" : "Notifications DENIED")
                }
            }
        }
    }
    
    private func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
                print("Current notification status: \(settings.authorizationStatus.rawValue)")
            }
        }
    }
    
    // MARK: - Phase Complete Notification
    
    func sendPhaseCompleteNotification(phase: TimerPhase, nextPhase: TimerPhase) {
        print("Trying to send notification for phase: \(phase)")
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                print("Notifications NOT authorized! Status: \(settings.authorizationStatus.rawValue)")
                return
            }
            
            let content = UNMutableNotificationContent()
            
            switch phase {
            case .warmup:
                content.title = "Warmup Complete!"
                content.body = "Time to start working"
            case .work:
                content.title = "Work Session Complete!"
                content.body = "Great job! Time for a break"
            case .shortBreak:
                content.title = "Break Over!"
                content.body = "Ready to get back to work?"
            case .longBreak:
                content.title = "Long Break Complete!"
                content.body = "Refreshed and ready? Let's go!"
            }
            
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = "TIMER_COMPLETE"
            content.userInfo = [
                "completedPhase": phase.rawValue,
                "nextPhase": nextPhase.rawValue,
                "autoTransition": true
            ]
            
            let request = UNNotificationRequest(
                identifier: "phase_complete_\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            
            print("Sending notification: \(content.title) [Category: TIMER_COMPLETE]")
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Failed to send: \(error)")
                } else {
                    print("Notification sent")
                }
            }
        }
    }
    
    // MARK: - Setup Notification Categories
    
    static func setupNotificationCategories() {
        let continueAction = UNNotificationAction(
            identifier: "CONTINUE_ACTION",
            title: "Continue",
            options: [.foreground]
        )
        
        let skipAction = UNNotificationAction(
            identifier: "SKIP_ACTION",
            title: "Skip",
            options: [.foreground]
        )
        
        let pauseAction = UNNotificationAction(
            identifier: "PAUSE_ACTION",
            title: "Pause",
            options: []
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
        
        print("Notification categories configured")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("Notification appearing now")
        
        let categoryId = notification.request.content.categoryIdentifier
        
        if categoryId == "TIMER_COMPLETE" {
            print("Timer completion notification (foreground)")
            #if os(iOS)
            completionHandler([.banner, .sound, .list, .badge])
            #else
            completionHandler([.banner, .sound, .badge])
            #endif
        } else {
            #if os(iOS)
            completionHandler([.banner, .sound, .list])
            #else
            completionHandler([.banner, .sound])
            #endif
        }
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionId = response.actionIdentifier
        let categoryId = response.notification.request.content.categoryIdentifier
        
        print("User interacted with notification")
        print("   Category: \(categoryId)")
        print("   Action: \(actionId)")
        
        switch actionId {
        case "CONTINUE_ACTION":
            print("Continue action triggered")
        case "SKIP_ACTION":
            print("Skip action triggered")
        case "PAUSE_ACTION":
            print("Pause action triggered")
        case UNNotificationDefaultActionIdentifier:
            print("Notification body tapped")
        case UNNotificationDismissActionIdentifier:
            print("Notification dismissed")
        default:
            print("Unknown action: \(actionId)")
        }
        
        completionHandler()
    }
}
