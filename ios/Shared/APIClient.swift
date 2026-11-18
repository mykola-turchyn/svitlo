import Foundation

/// Talks to the Svitlo backend (see `backend/`). The base URL comes from Info.plist (`SvitloAPIBaseURL`),
/// which is set per build configuration in `project.yml`.
struct APIClient {
    enum APIError: LocalizedError {
        case badStatus(Int)
        case server(String)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "Сервер відповів з кодом \(code)"
            case .server(let message): return message
            }
        }
    }

    var baseURL: URL
    var session: URLSession = .shared

    static var live: APIClient {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SvitloAPIBaseURL") as? String
        let url = raw.flatMap { URL(string: $0) } ?? URL(string: "http://localhost:8787")!
        return APIClient(baseURL: url)
    }

    func regions() async throws -> [Region] {
        try await get(RegionsResponse.self, path: "v1/regions").regions
    }

    func groups(region: String) async throws -> [String] {
        try await get(GroupsResponse.self, path: "v1/regions/\(region)/groups").groups
    }

    func schedules(region: String, groups: [String]) async throws -> SchedulesResponse {
        let query = [URLQueryItem(name: "groups", value: groups.joined(separator: ","))]
        return try await get(SchedulesResponse.self, path: "v1/regions/\(region)/schedule", query: query)
    }

    /// What one refresh produced. A failing region never hides the others.
    struct FetchResult {
        var schedules: [GroupSchedule] = []
        /// Region id → error message.
        var failedRegions: [String: String] = [:]
        /// `region/group` keys the server does not know.
        var missingKeys: Set<String> = []
    }

    /// Fetches every followed group, one request per region, in parallel.
    func schedules(for saved: [SavedGroup]) async -> FetchResult {
        let byRegion = Dictionary(grouping: saved, by: \.regionId)
        return await withTaskGroup(of: (String, Result<SchedulesResponse, Error>).self) { tasks in
            for (region, items) in byRegion {
                let groups = Array(Set(items.map(\.group))).sorted()
                tasks.addTask {
                    do { return (region, .success(try await self.schedules(region: region, groups: groups))) }
                    catch { return (region, .failure(error)) }
                }
            }
            var result = FetchResult()
            for await (region, outcome) in tasks {
                switch outcome {
                case .success(let response):
                    result.schedules += response.groups
                    for g in response.missing ?? [] { result.missingKeys.insert("\(region)/\(g)") }
                case .failure(let error):
                    if case .server(let message)? = error as? APIError, message.hasPrefix("Unknown group") {
                        for item in byRegion[region] ?? [] { result.missingKeys.insert(item.scheduleKey) }
                    } else {
                        result.failedRegions[region] = error.localizedDescription
                    }
                }
            }
            return result
        }
    }

    private struct ErrorBody: Decodable {
        struct Inner: Decodable { var message: String }
        var error: Inner
    }

    private func get<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) { throw APIError.server(body.error.message) }
            throw APIError.badStatus(status)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
