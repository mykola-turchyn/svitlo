import Foundation

/// Same deterministic schedules as the backend's DemoProvider.
/// Used by SwiftUI previews, widget placeholders and the app's offline "demo" mode.
enum DemoData {
    static func schedule(region: String = "kyiv", group: String, now: Date = .now) -> GroupSchedule {
        let index = KnownRegions.defaultGroups.firstIndex(of: group) ?? 0
        let today = ScheduleMath.dateString(now)
        let tomorrow = ScheduleMath.dateString(now.addingTimeInterval(86_400))
        return GroupSchedule(
            region: region,
            group: group,
            updatedAt: nil,
            today: day(today, index),
            tomorrow: day(tomorrow, index)
        )
    }

    static func day(_ date: String, _ groupIndex: Int) -> DaySchedule {
        // Whole days since 1970 for the calendar date, like `Date.parse(date + "T00:00:00Z")` in the backend.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let p = date.split(separator: "-").compactMap { Int($0) }
        let utcMidnight = p.count == 3 ? utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) : nil
        let dayNumber = Int((utcMidnight ?? .now).timeIntervalSince1970 / 86_400)
        let base = ((groupIndex * 2 + dayNumber * 3) % 8) * 60
        return DaySchedule(date: date, status: .scheduled, slots: [
            Slot(start: base, end: base + 240, kind: .off),
            Slot(start: base + 240, end: base + 300, kind: .maybe),
            Slot(start: base + 720, end: base + 960, kind: .off),
        ])
    }

    static let groups: [SavedGroup] = [
        SavedGroup(name: "Дім", regionId: "kyiv", group: "3.2"),
        SavedGroup(name: "Офіс", regionId: "kyiv", group: "1.1"),
        SavedGroup(name: "Батьки", regionId: "kyiv", group: "5.1"),
    ]
}
