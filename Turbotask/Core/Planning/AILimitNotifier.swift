//
//  AILimitNotifier.swift
//  Turbotask
//

import Foundation
import UserNotifications

enum AILimitNotifier {
    private static var didRequestAuthorization = false

    static func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyTasksReady(count: Int, resetTime: Date) {
        requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = "AI tasks are ready"
        let taskWord = count == 1 ? "task is" : "tasks are"
        content.body = "\(count) AI-dependent \(taskWord) available again · reset \(resetTime.formatted(date: .omitted, time: .shortened))"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "turbo.ai-limit.ready.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
