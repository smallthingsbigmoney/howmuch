//
//  NotificationScheduler.swift
//  smallthings, bigmoney.
//
//  Schedules a local "퇴근 10분 전" reminder so the user opens the app at
//  least once a day. One weekly-repeating notification per working day,
//  fired `leadMinutes` before the configured check-out time.
//

import Foundation
import UserNotifications

enum NotificationScheduler {
    /// How many minutes before check-out the reminder fires.
    static let leadMinutes = 10

    /// One stable identifier per weekday, so rescheduling cleanly replaces them.
    private static var identifiers: [String] {
        Weekday.allCases.map { "checkout-reminder-\($0.rawValue)" }
    }

    /// Requests permission (the system prompt shows only the first time) and
    /// then (re)schedules when the settings sheet closes.
    /// `completion` runs on the main thread once the permission step is settled
    /// (immediately when notifications are off).
    static func refresh(for settings: UserSettings, completion: (() -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        guard settings.notificationsEnabled else {
            DispatchQueue.main.async { completion?() }
            return
        }

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if granted { schedule(for: settings) }
                completion?()
            }
        }
    }

    /// Re-schedules ONLY when already authorized — never prompts. Call on
    /// launch/foreground to keep the schedule in sync without nagging.
    static func rescheduleIfAuthorized(for settings: UserSettings) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { status in
            let ok = status.authorizationStatus == .authorized
                  || status.authorizationStatus == .provisional
            guard ok else { return }
            DispatchQueue.main.async {
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
                schedule(for: settings)
            }
        }
    }

    /// Pool of reminder copy. A random one is picked per scheduled day, and
    /// rescheduling on every app open re-rolls them — so the message rotates
    /// instead of repeating the same line every day.
    private static func messagePool() -> [(title: String, body: String)] {
        [
            ("오늘 얼마 벌었을까요? 👀", "퇴근 \(leadMinutes)분 전! 앱을 열어 오늘 번 돈을 확인해보세요."),
            ("곧 퇴근이에요 🎉",        "오늘 벌어온 돈 확인하고 뿌듯하게 마무리해요."),
            ("퇴근 \(leadMinutes)분 전 알림! 💸", "오늘 얼마 벌었는지 앱을 열어 확인하세요."),
        ]
    }

    private static func schedule(for settings: UserSettings) {
        guard settings.notificationsEnabled, !settings.workingDays.isEmpty else { return }
        let center = UNUserNotificationCenter.current()

        // Check-out time minus the lead, in minutes from midnight -> hour/minute.
        // Overnight shifts check out on the next calendar day, so the trigger
        // weekday may differ from the shift's starting weekday.
        var minutes = settings.checkOutMinutes - leadMinutes
        var weekdayOffset = settings.checkOutMinutes <= settings.checkInMinutes ? 1 : 0
        if minutes < 0 {
            minutes += 24 * 60
            weekdayOffset -= 1
        }
        let hour = minutes / 60
        let minute = minutes % 60

        let pool = messagePool()

        for day in settings.workingDays {
            let notificationDay = weekday(day, offsetBy: weekdayOffset)
            let message = pool.randomElement()! // re-rolled on every reschedule
            let content = UNMutableNotificationContent()
            content.title = message.title
            content.body = message.body
            content.sound = .default

            var comps = DateComponents()
            comps.weekday = notificationDay.calendarWeekday
            comps.hour = hour
            comps.minute = minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(
                identifier: "checkout-reminder-\(day.rawValue)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private static func weekday(_ day: Weekday, offsetBy offset: Int) -> Weekday {
        let count = Weekday.allCases.count
        let value = (day.rawValue + offset % count + count) % count
        return Weekday(rawValue: value)!
    }
}
