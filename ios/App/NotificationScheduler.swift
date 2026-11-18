import Foundation
import UserNotifications

/// Local notifications built from the cached schedules:
/// 30 minutes before each outage and when power should return.
/// Rebuilt from scratch after every refresh, so a changed schedule never leaves stale alerts.
enum NotificationScheduler {
    /// iOS keeps at most 64 pending local notifications per app; leave headroom.
    static let limit = 60
    static let leadTime: TimeInterval = 30 * 60

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func reschedule(groups: [SavedGroup], schedules: [String: GroupSchedule], now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        for (_, request) in plan(groups: groups, schedules: schedules, now: now).prefix(limit) {
            try? await center.add(request)
        }
    }

    /// Pure planning step, sorted by fire date (kept separate so it can be unit-tested).
    static func plan(groups: [SavedGroup], schedules: [String: GroupSchedule], now: Date) -> [(Date, UNNotificationRequest)] {
        var items: [(Date, UNNotificationRequest)] = []
        for group in groups {
            guard let schedule = schedules[group.scheduleKey] else { continue }
            for outage in ScheduleMath.outages(schedule) {
                let range = "\(ScheduleMath.hhmm(outage.start))–\(ScheduleMath.hhmm(outage.end))"
                let stamp = Int(outage.start.timeIntervalSince1970)

                let warnAt = outage.start.addingTimeInterval(-leadTime)
                if group.notifyBeforeOff, warnAt > now {
                    items.append((warnAt, request(
                        id: "\(group.id)-off-\(stamp)",
                        title: "\(group.name): за 30 хв вимкнуть світло",
                        body: "Група \(group.group) · вимкнення \(range)",
                        at: warnAt)))
                }
                if group.notifyOnReturn, outage.end > now {
                    items.append((outage.end, request(
                        id: "\(group.id)-on-\(stamp)",
                        title: "\(group.name): світло має повернутися",
                        body: "Група \(group.group) · за графіком о \(ScheduleMath.hhmm(outage.end))",
                        at: outage.end)))
                }
            }
        }
        return items.sorted { $0.0 < $1.0 }
    }

    private static func request(id: String, title: String, body: String, at date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "svitlo"
        let components = ScheduleMath.calendar.dateComponents([.timeZone, .year, .month, .day, .hour, .minute], from: date)
        return UNNotificationRequest(identifier: id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }
}
