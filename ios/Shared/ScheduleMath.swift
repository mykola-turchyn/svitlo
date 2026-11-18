import Foundation

/// Pure schedule logic shared by the app, the widget and the notification scheduler.
/// Mirrors `backend/src/domain/schedule.ts`; keep the two in sync (both have tests).
enum ScheduleMath {
    static let minutesPerDay = 1440
    static let timeZone = TimeZone(identifier: "Europe/Kyiv")!

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = Locale(identifier: "uk_UA")
        return c
    }()

    // MARK: Dates

    /// `YYYY-MM-DD` of an instant in Kyiv.
    static func dateString(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Kyiv midnight for a `YYYY-MM-DD` string.
    static func midnight(of day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The instant `minute` minutes after midnight of `day`.
    static func instant(day: String, minute: Int) -> Date? {
        midnight(of: day).map { $0.addingTimeInterval(TimeInterval(minute * 60)) }
    }

    // MARK: State

    struct PowerState: Equatable {
        var isOn: Bool
        /// When the state next changes; `nil` when nothing is planned.
        var nextChange: Date?
    }

    /// Absolute outage intervals across today and tomorrow, merged (an outage over midnight is one interval).
    static func outages(_ schedule: GroupSchedule, kinds: Set<SlotKind> = [.off]) -> [DateInterval] {
        var result: [DateInterval] = []
        for day in [schedule.today, schedule.tomorrow] {
            for slot in day.slots where kinds.contains(slot.kind) {
                guard let s = instant(day: day.date, minute: slot.start),
                      let e = instant(day: day.date, minute: slot.end), e > s else { continue }
                result.append(DateInterval(start: s, end: e))
            }
        }
        result.sort { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in result {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    static func state(_ schedule: GroupSchedule, at now: Date) -> PowerState {
        let off = outages(schedule)
        if let active = off.first(where: { $0.start <= now && now < $0.end }) {
            return PowerState(isOn: false, nextChange: active.end)
        }
        return PowerState(isOn: true, nextChange: off.first(where: { $0.start > now })?.start)
    }

    /// Every moment the widget should redraw (slot boundaries), after `now`.
    static func changeDates(_ schedules: [GroupSchedule], after now: Date) -> [Date] {
        let all = schedules.flatMap { outages($0, kinds: [.off, .maybe]) }.flatMap { [$0.start, $0.end] }
        return Array(Set(all.filter { $0 > now })).sorted()
    }

    // MARK: Timeline bar

    enum SegmentKind: Equatable { case on, off, maybe }

    struct Segment: Equatable {
        var kind: SegmentKind
        /// Length in minutes.
        var length: Int
    }

    /// The whole day split into on / off / maybe segments, for the 24-hour bar.
    static func segments(_ day: DaySchedule) -> [Segment] {
        var minutes = Array(repeating: SegmentKind.on, count: minutesPerDay / 15)
        func paint(_ slot: Slot, _ kind: SegmentKind) {
            let from = max(0, slot.start / 15), to = min(minutes.count, Int((Double(slot.end) / 15).rounded(.up)))
            if from < to { for i in from..<to { minutes[i] = kind } }
        }
        day.slots.filter { $0.kind == .maybe }.forEach { paint($0, .maybe) }
        day.slots.filter { $0.kind == .off }.forEach { paint($0, .off) }

        var out: [Segment] = []
        for kind in minutes {
            if let last = out.last, last.kind == kind { out[out.count - 1].length += 15 }
            else { out.append(Segment(kind: kind, length: 15)) }
        }
        return out
    }

    // MARK: Formatting (Ukrainian)

    static func hhmm(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    static func hhmm(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return hhmm((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// "3 год 40 хв", "45 хв", "2 год".
    static func duration(from: Date, to: Date) -> String {
        let total = max(0, Int((to.timeIntervalSince(from) / 60).rounded()))
        let h = total / 60, m = total % 60
        switch (h, m) {
        case (0, _): return "\(m) хв"
        case (_, 0): return "\(h) год"
        default: return "\(h) год \(m) хв"
        }
    }

    /// "08:00–12:00 · 18:00–22:00"
    static func ranges(_ day: DaySchedule, kind: SlotKind) -> String {
        // Word joiners keep "21:00–24:00" on one line; lines may break only at " · ".
        day.slots.filter { $0.kind == kind }.map { "\(hhmm($0.start))\u{2060}–\u{2060}\(hhmm($0.end))" }.joined(separator: " · ")
    }
}

/// Ready-to-display texts for a group's current state.
struct StatusText: Equatable {
    var isOn: Bool
    /// "Світло є" / "Світла немає"
    var title: String
    /// "Вимкнення о 18:00" / "Увімкнуть о 16:00" / "Сьогодні без вимкнень"
    var next: String
    /// "через 3 год 40 хв"
    var countdown: String
    /// "до 18:00" — compact for small widgets.
    var short: String

    /// False when the operator has not published a schedule for today.
    var hasData = true

    init(schedule: GroupSchedule, now: Date) {
        if schedule.today.status == .none || schedule.today.status == .waiting {
            isOn = true
            hasData = false
            title = "Немає графіка"
            next = "Оператор ще не опублікував графік на сьогодні"
            countdown = ""
            short = "немає даних"
            return
        }
        let state = ScheduleMath.state(schedule, at: now)
        isOn = state.isOn
        title = state.isOn ? "Світло є" : "Світла немає"
        if let change = state.nextChange {
            let time = ScheduleMath.hhmm(change)
            let isTomorrow = ScheduleMath.dateString(change) != ScheduleMath.dateString(now)
            let day = isTomorrow ? " завтра" : ""
            next = state.isOn ? "Вимкнення\(day) о \(time)" : "Увімкнуть\(day) о \(time)"
            countdown = "через \(ScheduleMath.duration(from: now, to: change))"
            short = "до \(time)"
        } else {
            next = state.isOn ? "Вимкнень не заплановано" : "Час увімкнення невідомий"
            countdown = ""
            short = state.isOn ? "без вимкнень" : "—"
        }
    }
}
