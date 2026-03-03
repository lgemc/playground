import SwiftUI
import Combine

/// Represents the runtime state of a running sub-app
struct AppRuntimeState: Identifiable {
    let appId: String
    let instance: any SubApp
    let launchedAt: Date

    var id: String { appId }
}

/// Manages the runtime state of running sub-apps.
/// Tracks which apps are running, handles lifecycle, and manages app switching.
@MainActor
class AppRuntimeManager: ObservableObject {
    static let shared = AppRuntimeManager()

    @Published private(set) var runningApps: [String: AppRuntimeState] = [:]
    @Published private(set) var currentAppId: String?

    private init() {
        // Private initializer for singleton
    }

    /// Get list of all running apps sorted by launch time
    var runningAppsList: [AppRuntimeState] {
        runningApps.values.sorted { $0.launchedAt < $1.launchedAt }
    }

    /// Check if an app is currently running
    func isRunning(_ appId: String) -> Bool {
        runningApps.containsKey(appId)
    }

    /// Launch an app (or switch to it if already running)
    func launchApp(appId: String, factory: () -> any SubApp) async {
        if runningApps.containsKey(appId) {
            // App is already running, just switch to it
            switchToApp(appId)
            return
        }

        // Create new instance
        let instance = factory()
        await instance.onInit()

        // Add to running apps
        runningApps[appId] = AppRuntimeState(
            appId: appId,
            instance: instance,
            launchedAt: Date()
        )

        // Make it the current app
        switchToApp(appId)
    }

    /// Switch to an already running app
    func switchToApp(_ appId: String) {
        guard runningApps.containsKey(appId) else {
            print("⚠️ Cannot switch to app '\(appId)' - not running")
            return
        }

        let previousAppId = currentAppId

        // Pause previous app if any
        if let previousAppId = previousAppId,
           let previousState = runningApps[previousAppId] {
            Task {
                await previousState.instance.onPause()
            }
        }

        // Switch to new app
        currentAppId = appId

        // Resume new app
        if let newState = runningApps[appId] {
            Task {
                await newState.instance.onResume()
            }
        }
    }

    /// Close a running app
    func closeApp(_ appId: String) async {
        guard let appState = runningApps[appId] else {
            return
        }

        await appState.instance.onDispose()
        runningApps.removeValue(forKey: appId)

        // If we closed the current app, switch to another one or clear current
        if currentAppId == appId {
            if !runningApps.isEmpty {
                // Switch to the most recently launched app
                if let latestApp = runningApps.values.max(by: { $0.launchedAt < $1.launchedAt }) {
                    currentAppId = latestApp.appId
                    await latestApp.instance.onResume()
                }
            } else {
                currentAppId = nil
            }
        }
    }

    /// Close all running apps
    func closeAllApps() async {
        let appIds = Array(runningApps.keys)
        for appId in appIds {
            await closeApp(appId)
        }
    }

    /// Return to launcher (keep apps running in background)
    func returnToLauncher() {
        if let currentAppId = currentAppId,
           let currentState = runningApps[currentAppId] {
            Task {
                await currentState.instance.onPause()
            }
            self.currentAppId = nil
        }
    }

    /// Get runtime state for a specific app
    func getAppState(_ appId: String) -> AppRuntimeState? {
        runningApps[appId]
    }
}

// Helper extension for containsKey
private extension Dictionary {
    func containsKey(_ key: Key) -> Bool {
        self[key] != nil
    }
}
