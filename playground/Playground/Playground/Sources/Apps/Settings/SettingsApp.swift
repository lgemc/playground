import SwiftUI
import Combine

/// Settings sub-app - App configuration and model management
class SettingsApp: SubApp {
    let id = "settings"
    let name = "Settings"
    let iconName = "gearshape.fill"
    let themeColor = Color.gray

    let supportsSearch = false

    // ObservableObject conformance
    let objectWillChange = ObservableObjectPublisher()

    init() {}

    func buildView() -> AnyView {
        AnyView(SettingsView())
    }

    // MARK: - Lifecycle

    func onInit() async {
        print("✅ Settings app initialized")
    }

    func search(query: String) async -> [SearchResult] {
        return []
    }

    func navigateToSearchResult(result: SearchResult) async {
        // Not applicable for Settings
    }
}
