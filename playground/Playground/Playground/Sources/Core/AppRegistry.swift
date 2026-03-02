import SwiftUI
import Combine

/// Singleton registry that manages all sub-apps in the Playground
class AppRegistry: ObservableObject {
    static let shared = AppRegistry()

    @Published private(set) var apps: [String: any SubApp] = [:]
    @Published private(set) var activeAppId: String?

    private var factories: [String: () -> any SubApp] = [:]
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Private initializer for singleton
    }

    // MARK: - Registration

    /// Register a sub-app directly
    func register(_ app: any SubApp) {
        apps[app.id] = app
        Task {
            await app.onInit()
        }
    }

    /// Register a factory that creates apps on demand (lazy loading)
    func registerFactory(id: String, factory: @escaping () -> any SubApp) {
        factories[id] = factory
    }

    /// Get or create an app by ID
    func getApp(id: String) -> (any SubApp)? {
        // Return existing app if already created
        if let app = apps[id] {
            return app
        }

        // Try to create from factory
        if let factory = factories[id] {
            let app = factory()
            apps[id] = app
            Task {
                await app.onInit()
            }
            return app
        }

        return nil
    }

    /// Get all registered and instantiated apps
    func getAllApps() -> [any SubApp] {
        return Array(apps.values)
    }

    /// Get all app IDs (including factories not yet instantiated)
    func getAllAppIds() -> [String] {
        let registeredIds = Set(apps.keys)
        let factoryIds = Set(factories.keys)
        return Array(registeredIds.union(factoryIds)).sorted()
    }

    // MARK: - Navigation

    /// Navigate to a specific app
    func navigateTo(appId: String) async {
        // Pause current app
        if let currentAppId = activeAppId,
           let currentApp = apps[currentAppId] {
            await currentApp.onPause()
        }

        // Get or create the target app
        guard let targetApp = getApp(id: appId) else {
            print("⚠️ App not found: \(appId)")
            return
        }

        // Resume target app
        await MainActor.run {
            activeAppId = appId
        }
        await targetApp.onResume()
    }

    /// Return to launcher (pause current app)
    func returnToLauncher() async {
        if let currentAppId = activeAppId,
           let currentApp = apps[currentAppId] {
            await currentApp.onPause()
        }

        await MainActor.run {
            activeAppId = nil
        }
    }

    // MARK: - Lifecycle

    /// Called when the entire app enters background
    func onAppBackground() async {
        if let currentAppId = activeAppId,
           let currentApp = apps[currentAppId] {
            await currentApp.onPause()
        }
    }

    /// Called when the entire app enters foreground
    func onAppForeground() async {
        if let currentAppId = activeAppId,
           let currentApp = apps[currentAppId] {
            await currentApp.onResume()
        }
    }

    /// Dispose of an app and remove it from registry
    func dispose(appId: String) async {
        if let app = apps[appId] {
            await app.onDispose()
            apps.removeValue(forKey: appId)
        }
    }

    /// Dispose all apps
    func disposeAll() async {
        for app in apps.values {
            await app.onDispose()
        }
        apps.removeAll()
    }
}
