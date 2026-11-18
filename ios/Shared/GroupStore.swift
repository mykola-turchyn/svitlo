import Foundation

/// Persistence shared between the app and the widget through the App Group container.
/// Small JSON blobs in UserDefaults are enough: a handful of groups and two days of slots each.
final class GroupStore {
    static let appGroupId = "group.com.mykolaturchyn.svitlo"
    static let shared = GroupStore()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Key {
        static let groups = "groups.v1"
        static let schedules = "schedules.v1"
        static let fetchedAt = "fetchedAt.v1"
        static func page(_ family: String) -> String { "widgetPage.\(family)" }
    }

    init(defaults: UserDefaults? = UserDefaults(suiteName: GroupStore.appGroupId)) {
        // Falls back to standard defaults in previews/tests where the App Group is not provisioned.
        self.defaults = defaults ?? .standard
    }

    // MARK: Groups (ordered — the order is also the widget order)

    var groups: [SavedGroup] {
        get { read([SavedGroup].self, Key.groups) ?? [] }
        set { write(newValue, Key.groups) }
    }

    // MARK: Cached schedules, keyed by "region/group"

    var schedules: [String: GroupSchedule] {
        get { read([String: GroupSchedule].self, Key.schedules) ?? [:] }
        set { write(newValue, Key.schedules) }
    }

    var fetchedAt: Date? {
        get { defaults.object(forKey: Key.fetchedAt) as? Date }
        set { defaults.set(newValue, forKey: Key.fetchedAt) }
    }

    func schedule(for group: SavedGroup) -> GroupSchedule? {
        schedules[group.scheduleKey]
    }

    func merge(_ fresh: [GroupSchedule], at date: Date = .now) {
        var all = schedules
        for s in fresh { all[s.key] = s }
        // Drop schedules nobody follows any more.
        let keys = Set(groups.map(\.scheduleKey))
        schedules = all.filter { keys.contains($0.key) }
        fetchedAt = date
    }

    // MARK: Widget paging (which group a widget family currently shows)

    func page(for family: String) -> Int { defaults.integer(forKey: Key.page(family)) }
    func setPage(_ page: Int, for family: String) { defaults.set(page, forKey: Key.page(family)) }

    // MARK: Helpers

    private func read<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? encoder.encode(value), forKey: key)
    }
}
