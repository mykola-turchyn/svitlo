import AppIntents
import WidgetKit

/// Tapping a dot in the widget shows another group (interactive widgets, iOS 17+).
/// The chosen page is stored per widget size in the App Group; WidgetKit reloads the timeline after `perform`.
struct SelectGroupIntent: AppIntent {
    static var title: LocalizedStringResource = "Показати групу"
    static var isDiscoverable = false

    @Parameter(title: "Сторінка") var page: Int
    @Parameter(title: "Розмір віджета") var family: String

    init() {}

    init(page: Int, family: String) {
        self.page = page
        self.family = family
    }

    func perform() async throws -> some IntentResult {
        GroupStore.shared.setPage(page, for: family)
        return .result()
    }
}
