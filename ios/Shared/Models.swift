import Foundation

// MARK: - Schedules (mirror of the backend's JSON)

enum SlotKind: String, Codable, Hashable {
    /// Confirmed outage.
    case off
    /// Possible outage — drawn hatched, does not flip the "power on" state.
    case maybe
}

struct Slot: Codable, Hashable {
    /// Minutes from local (Kyiv) midnight, 0…1440.
    var start: Int
    var end: Int
    var kind: SlotKind
}

enum DayStatus: String, Codable, Hashable {
    case scheduled, waiting, emergency, none

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DayStatus(rawValue: raw) ?? .none
    }
}

struct DaySchedule: Codable, Hashable {
    /// `YYYY-MM-DD` in Kyiv.
    var date: String
    var status: DayStatus
    var slots: [Slot]
}

struct GroupSchedule: Codable, Hashable {
    var region: String
    var group: String
    var updatedAt: String?
    var today: DaySchedule
    var tomorrow: DaySchedule
}

struct Region: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var `operator`: String
    /// False when there is no open schedule source for the region yet.
    var available: Bool

    init(id: String, name: String, operator: String, available: Bool = true) {
        self.id = id
        self.name = name
        self.operator = `operator`
        self.available = available
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        `operator` = try c.decode(String.self, forKey: .operator)
        available = try c.decodeIfPresent(Bool.self, forKey: .available) ?? true
    }
}

// MARK: - API envelopes

struct RegionsResponse: Decodable { var regions: [Region] }
struct GroupsResponse: Decodable { var region: String; var groups: [String] }
struct SchedulesResponse: Decodable {
    var region: String
    var source: String
    var fetchedAt: String
    var stale: Bool
    var groups: [GroupSchedule]
    var missing: [String]?
}

// MARK: - User data

/// A group the user follows, e.g. "Дім · Київ · 3.2".
struct SavedGroup: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var regionId: String
    var group: String
    var notifyBeforeOff = true
    var notifyOnReturn = true

    /// Key used to look up the cached schedule.
    var scheduleKey: String { "\(regionId)/\(group)" }
}

extension GroupSchedule {
    var key: String { "\(region)/\(group)" }
}

/// Regions known offline, so the editor works before the first network call.
enum KnownRegions {
    /// Same catalog as `backend/src/providers/catalog.ts`; used before the first network call.
    static let all: [Region] = [
        Region(id: "kyiv", name: "Київ", operator: "ДТЕК Київські електромережі"),
        Region(id: "kyiv-region", name: "Київська область", operator: "ДТЕК Київські регіональні електромережі"),
        Region(id: "dnipro-dtek", name: "Дніпропетровська область · ДТЕК", operator: "ДТЕК Дніпровські електромережі"),
        Region(id: "dnipro-cek", name: "Дніпропетровська область · ЦЕК", operator: "ЦЕК"),
        Region(id: "odesa", name: "Одеська область", operator: "ДТЕК Одеські електромережі"),
        Region(id: "cherkasy", name: "Черкаська область", operator: "Черкасиобленерго"),
        Region(id: "chernihiv", name: "Чернігівська область", operator: "Чернігівобленерго"),
        Region(id: "ivano-frankivsk", name: "Івано-Франківська область", operator: "Прикарпаттяобленерго"),
        Region(id: "kharkiv", name: "Харківська область", operator: "Харківобленерго"),
        Region(id: "khmelnytskyi", name: "Хмельницька область", operator: "Хмельницькобленерго"),
        Region(id: "lviv", name: "Львівська область", operator: "Львівобленерго"),
        Region(id: "poltava", name: "Полтавська область", operator: "Полтаваобленерго"),
        Region(id: "rivne", name: "Рівненська область", operator: "Рівнеобленерго"),
        Region(id: "ternopil", name: "Тернопільська область", operator: "Тернопільобленерго"),
        Region(id: "zakarpattia", name: "Закарпатська область", operator: "Закарпаттяобленерго"),
        Region(id: "zaporizhzhia", name: "Запорізька область", operator: "Запоріжжяобленерго"),
        Region(id: "zhytomyr", name: "Житомирська область", operator: "Житомиробленерго"),
        Region(id: "chernivtsi", name: "Чернівецька область", operator: "Чернівціобленерго", available: false),
        Region(id: "donetsk", name: "Донецька область", operator: "ДТЕК Донецькі електромережі", available: false),
        Region(id: "kherson", name: "Херсонська область", operator: "Херсонобленерго", available: false),
        Region(id: "kirovohrad", name: "Кіровоградська область", operator: "Кіровоградобленерго", available: false),
        Region(id: "mykolaiv", name: "Миколаївська область", operator: "Миколаївобленерго", available: false),
        Region(id: "sumy", name: "Сумська область", operator: "Сумиобленерго", available: false),
        Region(id: "vinnytsia", name: "Вінницька область", operator: "Вінницяобленерго", available: false),
        Region(id: "volyn", name: "Волинська область", operator: "Волиньобленерго", available: false),
    ]
    static let defaultGroups = ["1.1", "1.2", "2.1", "2.2", "3.1", "3.2", "4.1", "4.2", "5.1", "5.2", "6.1", "6.2"]
}
