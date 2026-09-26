import Foundation
import UserNotifications

/// Local due-date notifications for plans (IDEA-110).
///
/// No entitlements needed — plain `UNUserNotificationCenter` local requests.
/// Permission is asked only the first time the user actually sets a reminder,
/// never at launch. Denied permission just means no banner; the due date and
/// sidebar overdue badge still work.
enum Reminders {
    private static func identifier(for planID: String) -> String { "due-\(planID)" }

    /// Schedule (or re-schedule) the banner for a plan. Past dates and
    /// finished plans get no request — the overdue badge covers them.
    /// `askPermission` is true only when the user has just set a reminder; re-arming
    /// at launch or after a sync never prompts.
    static func sync(_ saved: SavedPlan, askPermission: Bool = false) {
        let center = UNUserNotificationCenter.current()
        let id = identifier(for: saved.id)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let due = saved.dueDate, due > .now, saved.progress < 1 else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                schedule(id: id, saved: saved, due: due)
            case .notDetermined:
                guard askPermission else { return }
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    if granted { schedule(id: id, saved: saved, due: due) }
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private static func schedule(id: String, saved: SavedPlan, due: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Test \(saved.plan.ticket.key) before \(due.formatted(date: .abbreviated, time: .omitted))"
        content.body = saved.plan.ticket.title
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        // Morning nudge (9am) on the due day rather than midnight.
        var fire = comps
        fire.hour = 9
        fire.minute = 0
        let triggerDate = Calendar.current.date(from: fire) ?? due
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: max(triggerDate, .now.addingTimeInterval(60))), repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel(planID: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(for: planID)])
    }
}
