//
//  ControlNotifier.swift
//  SMCController
//
//  User notifications for events the user may not be looking at.
//

import Foundation
import UserNotifications

enum ControlNotifier {
    /// Posts a notification that fan control stopped. Permission is requested the first
    /// time this is needed, so users who never hit a failure never see a prompt.
    static func postControlStopped(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        Task {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                guard granted else { return }
            case .denied:
                return
            default:
                break
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "com.minepacu.smccontroller.controlStopped",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }
}
