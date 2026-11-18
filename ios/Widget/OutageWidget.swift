import SwiftUI
import WidgetKit

// MARK: - Timeline

struct OutageEntry: TimelineEntry {
    let date: Date
    let groups: [SavedGroup]
    let schedules: [String: GroupSchedule]
    /// Current page per widget family (`small`, `medium`), chosen with the dots.
    let pages: [String: Int]

    func schedule(for group: SavedGroup) -> GroupSchedule? { schedules[group.scheduleKey] }

    func page(_ family: String) -> Int {
        guard !groups.isEmpty else { return 0 }
        return min(max(0, pages[family] ?? 0), groups.count - 1)
    }

    static func demo(at date: Date = .now) -> OutageEntry {
        let groups = DemoData.groups
        let schedules = Dictionary(uniqueKeysWithValues: groups.map { ($0.scheduleKey, DemoData.schedule(group: $0.group, now: date)) })
        return OutageEntry(date: date, groups: groups, schedules: schedules, pages: [:])
    }
}

struct OutageProvider: TimelineProvider {
    /// Refresh network data at most this often; between refreshes the widget redraws from cache.
    static let refreshInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> OutageEntry { .demo() }

    func getSnapshot(in context: Context, completion: @escaping (OutageEntry) -> Void) {
        let entry = makeEntry(at: .now)
        completion(entry.groups.isEmpty && context.isPreview ? .demo() : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OutageEntry>) -> Void) {
        Task {
            await refreshIfNeeded()
            let now = Date.now
            let base = makeEntry(at: now)
            // One entry now and one at every slot boundary in the next 24 h, so the status flips on time.
            let changes = ScheduleMath.changeDates(Array(base.schedules.values), after: now)
                .filter { $0 < now.addingTimeInterval(24 * 3600) }
                .prefix(40)
            let entries = [base] + changes.map { makeEntry(at: $0) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.refreshInterval))))
        }
    }

    private func makeEntry(at date: Date) -> OutageEntry {
        let store = GroupStore.shared
        return OutageEntry(
            date: date,
            groups: store.groups,
            schedules: store.schedules,
            pages: ["small": store.page(for: "small"), "medium": store.page(for: "medium")]
        )
    }

    /// The app usually keeps the cache fresh; this covers days when it is not opened.
    private func refreshIfNeeded() async {
        let store = GroupStore.shared
        let groups = store.groups
        guard !groups.isEmpty else { return }
        if let fetchedAt = store.fetchedAt, Date.now.timeIntervalSince(fetchedAt) < Self.refreshInterval { return }
        let result = await APIClient.live.schedules(for: groups)
        if !result.schedules.isEmpty { store.merge(result.schedules) }
    }
}

// MARK: - Widget

struct OutageWidget: Widget {
    let kind = "OutageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OutageProvider()) { entry in
            OutageWidgetView(entry: entry)
                .containerBackground(Theme.surface, for: .widget)
        }
        .configurationDisplayName("Графік світла")
        .description("Чи є світло зараз і коли наступне вимкнення. Крапки перемикають групи.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct OutageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: OutageEntry

    var body: some View {
        if entry.groups.isEmpty {
            VStack(spacing: 8) {
                PowerIcon(isOn: true, size: 18)
                Text("Додайте групу в застосунку «Світло»")
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.fg)
            }
        } else {
            switch family {
            case .systemSmall: SmallView(entry: entry)
            case .systemMedium: MediumView(entry: entry)
            default: LargeView(entry: entry)
            }
        }
    }
}

// MARK: - Sizes

private struct SmallView: View {
    var entry: OutageEntry

    var body: some View {
        let index = entry.page("small")
        let group = entry.groups[index]
        VStack(alignment: .leading, spacing: 0) {
            GroupHeader(group: group, compact: true)
            Spacer(minLength: 4)
            if let schedule = entry.schedule(for: group) {
                let status = StatusText(schedule: schedule, now: entry.date)
                PowerIcon(isOn: status.isOn, size: 15)
                Text(status.title).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.fg).padding(.top, 6)
                Text(status.short).font(.footnote).monospacedDigit().foregroundStyle(Theme.muted)
                Spacer(minLength: 6)
                TimelineBar(day: schedule.today, height: 8, cornerRadius: 4, now: entry.date)
            } else {
                NoData()
            }
            PageDots(count: entry.groups.count, current: index, family: "small").padding(.top, 6)
        }
        .widgetURL(URL(string: "svitlo://group/\(group.id.uuidString)"))
    }
}

private struct MediumView: View {
    var entry: OutageEntry

    var body: some View {
        let index = entry.page("medium")
        let group = entry.groups[index]
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                GroupHeader(group: group, compact: false)
                Spacer()
                if let fetched = GroupStore.shared.fetchedAt {
                    Text("оновлено \(ScheduleMath.hhmm(fetched))").font(.caption2).foregroundStyle(Theme.subtle)
                }
            }
            Spacer(minLength: 6)
            if let schedule = entry.schedule(for: group) {
                let status = StatusText(schedule: schedule, now: entry.date)
                HStack(spacing: 12) {
                    PowerIcon(isOn: status.isOn, size: 19)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(status.title).font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.fg)
                        Text([status.next, status.countdown].filter { !$0.isEmpty }.joined(separator: ", "))
                            .font(.footnote).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                TimelineBar(day: schedule.today, height: 10, showsHours: true, now: entry.date)
            } else {
                NoData()
            }
            PageDots(count: entry.groups.count, current: index, family: "medium").padding(.top, 4)
        }
        .widgetURL(URL(string: "svitlo://group/\(group.id.uuidString)"))
    }
}

private struct LargeView: View {
    var entry: OutageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Відключення сьогодні").font(.headline).foregroundStyle(Theme.fg)
                Spacer()
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).locale(Locale(identifier: "uk_UA"))))
                    .font(.caption).foregroundStyle(Theme.subtle)
            }
            ForEach(entry.groups.prefix(4)) { group in
                Link(destination: URL(string: "svitlo://group/\(group.id.uuidString)")!) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            GroupHeader(group: group, compact: true)
                            Spacer()
                            if let schedule = entry.schedule(for: group) {
                                StatusPill(status: StatusText(schedule: schedule, now: entry.date))
                            }
                        }
                        if let schedule = entry.schedule(for: group) {
                            TimelineBar(day: schedule.today, height: 12, now: entry.date)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text("00"); Spacer(); Text("06"); Spacer(); Text("12"); Spacer(); Text("18"); Spacer(); Text("24")
            }
            .font(.caption2).monospacedDigit().foregroundStyle(Theme.subtle)
            TimelineLegend().font(.caption2)
        }
    }
}

// MARK: - Bits

private struct GroupHeader: View {
    var group: SavedGroup
    var compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(group.name).font(.system(size: compact ? 13 : 14, weight: .semibold)).foregroundStyle(Theme.fg).lineLimit(1)
            Text(compact ? group.group : "група \(group.group)")
                .font(.caption2.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 6).frame(height: 18)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
}

private struct StatusPill: View {
    var status: StatusText

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(status.isOn ? Theme.on : Theme.off).frame(width: 7, height: 7)
            Text(status.short).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(status.isOn ? Theme.onText : Theme.offText)
        .padding(.horizontal, 9).frame(height: 22)
        .background(status.isOn ? Theme.onSoft : Theme.offSoft, in: Capsule())
        .accessibilityLabel("\(status.title), \(status.next)")
    }
}

/// Tap a dot to show that group (iOS 17 interactive widgets).
private struct PageDots: View {
    var count: Int
    var current: Int
    var family: String

    var body: some View {
        if count > 1 {
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    Button(intent: SelectGroupIntent(page: i, family: family)) {
                        Capsule()
                            .fill(i == current ? Theme.fg : Theme.maybeBg)
                            .frame(width: i == current ? 14 : 6, height: 6)
                            .frame(width: 18, height: 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Група \(i + 1) з \(count)")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct NoData: View {
    var body: some View {
        Text("Немає даних. Відкрийте застосунок, щоб оновити.")
            .font(.caption).foregroundStyle(Theme.muted)
    }
}

#Preview(as: .systemSmall) { OutageWidget() } timeline: { OutageEntry.demo() }
#Preview(as: .systemMedium) { OutageWidget() } timeline: { OutageEntry.demo() }
#Preview(as: .systemLarge) { OutageWidget() } timeline: { OutageEntry.demo() }
