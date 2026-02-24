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
        checkAuthorization()
    }

    func setupDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
            }
        }
    }

    private func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }


    func sendPhaseCompleteNotification(phase: TimerPhase, nextPhase: TimerPhase) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

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

            let request = UNNotificationRequest(
                identifier: "phase_complete_\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request) { _ in }
        }
    }
}


extension NotificationManager: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let categoryId = notification.request.content.categoryIdentifier
        if categoryId == "TIMER_COMPLETE" {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.banner, .sound])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
