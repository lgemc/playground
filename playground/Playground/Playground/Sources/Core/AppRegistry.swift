import SwiftUI
import Combine

/// Simple registry that stores all sub-apps in the Playground
class AppRegistry: ObservableObject {
    static let shared = AppRegistry()

    @Published private(set) var apps: [String: any SubApp] = [:]

    private init() {
        // Private initializer for singleton
    }

    /// Register a sub-app
    func register(_ app: any SubApp) {
        apps[app.id] = app
        Task {
            await app.onInit()
        }
    }

    /// Get all registered apps
    func getAllApps() -> [any SubApp] {
        return Array(apps.values)
    }

    /// Get a specific app by ID
    func getApp(id: String) -> (any SubApp)? {
        return apps[id]
    }
}
