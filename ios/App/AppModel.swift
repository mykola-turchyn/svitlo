import Foundation
import Observation
import WidgetKit

/// App state: followed groups, cached schedules and the actions the screens call.
/// Everything that the widget needs is written through `GroupStore` (App Group).
@MainActor
@Observable
final class AppModel {
    private(set) var groups: [SavedGroup]
    private(set) var schedules: [String: GroupSchedule]
    private(set) var regions: [Region] = KnownRegions.all
    private(set) var fetchedAt: Date?
    private(set) var isRefreshing = false
    var errorMessage: String?
    /// Per-group problem shown on its card (`region/group` → text).
    private(set) var problems: [String: String] = [:]

    /// The last deleted group, kept for a few seconds so the user can undo.
    private(set) var recentlyDeleted: (group: SavedGroup, index: Int)?

    @ObservationIgnored private let store: GroupStore
    @ObservationIgnored let api: APIClient

    init(store: GroupStore = .shared, api: APIClient = .live) {
        self.store = store
        self.api = api
        #if DEBUG
        // QA: `xcrun simctl launch booted com.mykolaturchyn.svitlo -seedDemoGroups YES` fills an empty app.
        if UserDefaults.standard.bool(forKey: "seedDemoGroups"), store.groups.isEmpty {
            store.groups = [
                SavedGroup(name: "Дім", regionId: "kyiv", group: "1.1"),
                SavedGroup(name: "Дача", regionId: "chernihiv", group: "1.1"),
                SavedGroup(name: "Батьки", regionId: "lviv", group: "1.1"),
            ]
        }
        #endif
        self.groups = store.groups
        self.schedules = store.schedules
        self.fetchedAt = store.fetchedAt
    }

    func schedule(for group: SavedGroup) -> GroupSchedule? {
        schedules[group.scheduleKey]
    }

    // MARK: Loading

    func loadRegions() async {
        if let fresh = try? await api.regions(), !fresh.isEmpty { regions = fresh }
    }

    func refresh() async {
        guard !groups.isEmpty, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let result = await api.schedules(for: groups)
        if !result.schedules.isEmpty {
            store.merge(result.schedules)
            schedules = store.schedules
            fetchedAt = store.fetchedAt
        }

        var problems: [String: String] = [:]
        for group in groups {
            if result.missingKeys.contains(group.scheduleKey) {
                problems[group.scheduleKey] = "Групи \(group.group) немає в цьому регіоні. Можливо, оператор змінив нумерацію черг — змініть групу."
            } else if let message = result.failedRegions[group.regionId] {
                problems[group.scheduleKey] = "Не вдалося отримати графік: \(message)"
            }
        }
        self.problems = problems

        if result.failedRegions.isEmpty {
            errorMessage = nil
        } else {
            errorMessage = schedules.isEmpty
                ? "Немає звʼязку з сервером. Перевірте інтернет і потягніть вниз, щоб оновити."
                : "Немає звʼязку — показуємо збережений графік."
        }
        didChangeData()
    }

    func problem(for group: SavedGroup) -> String? {
        problems[group.scheduleKey]
    }

    /// Schedule for a group that is not saved yet (editor preview).
    func preview(region: String, group: String) async -> GroupSchedule? {
        try? await api.schedules(region: region, groups: [group]).groups.first
    }

    func availableGroups(region: String) async -> [String] {
        (try? await api.groups(region: region)).flatMap { $0.isEmpty ? nil : $0 } ?? KnownRegions.defaultGroups
    }

    // MARK: Editing

    func add(_ group: SavedGroup) {
        groups.append(group)
        saveGroups()
        Task { await refresh() }
    }

    func update(_ group: SavedGroup) {
        guard let i = groups.firstIndex(where: { $0.id == group.id }) else { return }
        let regionOrGroupChanged = groups[i].scheduleKey != group.scheduleKey
        groups[i] = group
        saveGroups()
        if regionOrGroupChanged { Task { await refresh() } } else { didChangeData() }
    }

    func delete(_ group: SavedGroup) {
        guard let i = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups.remove(at: i)
        recentlyDeleted = (group, i)
        saveGroups()
    }

    func undoDelete() {
        guard let deleted = recentlyDeleted else { return }
        groups.insert(deleted.group, at: min(deleted.index, groups.count))
        recentlyDeleted = nil
        saveGroups()
        Task { await refresh() }
    }

    func clearUndo() {
        recentlyDeleted = nil
    }

    /// Reorder by drag. The first group is the one widgets show first.
    func move(from offsets: IndexSet, to destination: Int) {
        groups.move(fromOffsets: offsets, toOffset: destination)
        saveGroups()
    }

    // MARK: Deep links from the widget: svitlo://group/<uuid>

    private(set) var highlightedGroup: UUID?

    func handle(_ url: URL) {
        guard url.scheme == "svitlo", url.host == "group", let id = UUID(uuidString: url.lastPathComponent) else { return }
        highlightedGroup = id
    }

    // MARK: Private

    private func saveGroups() {
        store.groups = groups
        didChangeData()
    }

    private func didChangeData() {
        WidgetCenter.shared.reloadAllTimelines()
        let groups = groups, schedules = schedules
        Task { await NotificationScheduler.reschedule(groups: groups, schedules: schedules) }
    }
}
