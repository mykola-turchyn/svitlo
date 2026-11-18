import XCTest
@testable import Svitlo

final class ScheduleMathTests: XCTestCase {
    private func schedule(today: [Slot], tomorrow: [Slot] = []) -> GroupSchedule {
        GroupSchedule(
            region: "kyiv", group: "3.2", updatedAt: nil,
            today: DaySchedule(date: "2026-11-17", status: .scheduled, slots: today),
            tomorrow: DaySchedule(date: "2026-11-18", status: .scheduled, slots: tomorrow)
        )
    }

    private func at(_ day: String, _ minute: Int) -> Date {
        ScheduleMath.instant(day: day, minute: minute)!
    }

    func testPowerOnWithNextOutage() {
        let s = schedule(today: [Slot(start: 480, end: 720, kind: .off), Slot(start: 1080, end: 1320, kind: .off)])
        let state = ScheduleMath.state(s, at: at("2026-11-17", 14 * 60 + 20))
        XCTAssertTrue(state.isOn)
        XCTAssertEqual(state.nextChange, at("2026-11-17", 1080))
    }

    func testOutageReportsReturnTime() {
        let s = schedule(today: [Slot(start: 480, end: 720, kind: .off)])
        let state = ScheduleMath.state(s, at: at("2026-11-17", 9 * 60))
        XCTAssertFalse(state.isOn)
        XCTAssertEqual(state.nextChange, at("2026-11-17", 720))
    }

    func testPossibleOutageDoesNotTurnPowerOff() {
        let s = schedule(today: [Slot(start: 720, end: 780, kind: .maybe)])
        XCTAssertTrue(ScheduleMath.state(s, at: at("2026-11-17", 750)).isOn)
    }

    func testOvernightOutageIsOneInterval() {
        let s = schedule(today: [Slot(start: 1320, end: 1440, kind: .off)], tomorrow: [Slot(start: 0, end: 120, kind: .off)])
        let state = ScheduleMath.state(s, at: at("2026-11-17", 1400))
        XCTAssertEqual(state.nextChange, at("2026-11-18", 120))
    }

    func testSegmentsCoverTheWholeDay() {
        let day = DaySchedule(date: "2026-11-17", status: .scheduled, slots: [
            Slot(start: 480, end: 720, kind: .off),
            Slot(start: 720, end: 780, kind: .maybe),
        ])
        let segments = ScheduleMath.segments(day)
        XCTAssertEqual(segments.map(\.length).reduce(0, +), 1440)
        XCTAssertEqual(segments.map(\.kind), [.on, .off, .maybe, .on])
    }

    func testStatusTextInUkrainian() {
        let s = schedule(today: [Slot(start: 1080, end: 1320, kind: .off)])
        let text = StatusText(schedule: s, now: at("2026-11-17", 14 * 60 + 20))
        XCTAssertEqual(text.title, "Світло є")
        XCTAssertEqual(text.next, "Вимкнення о 18:00")
        XCTAssertEqual(text.countdown, "через 3 год 40 хв")
        XCTAssertEqual(text.short, "до 18:00")
    }

    func testNotificationPlanSkipsThePastAndSorts() {
        let group = SavedGroup(name: "Дім", regionId: "kyiv", group: "3.2")
        let s = schedule(today: [Slot(start: 480, end: 720, kind: .off), Slot(start: 1080, end: 1320, kind: .off)])
        let plan = NotificationScheduler.plan(groups: [group], schedules: [group.scheduleKey: s], now: at("2026-11-17", 600))
        // 08:00 warning is in the past; 12:00 return, 17:30 warning and 22:00 return remain.
        XCTAssertEqual(plan.map(\.0), [at("2026-11-17", 720), at("2026-11-17", 1050), at("2026-11-17", 1320)])
    }

    func testNoScheduleIsNotShownAsPower() {
        var s = schedule(today: [])
        s.today.status = .none
        let text = StatusText(schedule: s, now: at("2026-11-17", 600))
        XCTAssertFalse(text.hasData)
        XCTAssertEqual(text.title, "Немає графіка")
    }
}
