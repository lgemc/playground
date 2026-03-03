import SwiftUI

/// Main container view that manages the stack of running apps.
/// Preserves state of all running apps while showing only the active one.
struct PlaygroundContainer: View {
    @StateObject private var runtimeManager = AppRuntimeManager.shared
    @StateObject private var registry = AppRegistry.shared

    var body: some View {
        ZStack {
            // Launcher (always at the bottom)
            LauncherView()
                .opacity(runtimeManager.currentAppId == nil ? 1 : 0)
                .zIndex(0)

            // Running apps (stacked on top)
            ForEach(Array(runtimeManager.runningAppsList.enumerated()), id: \.element.id) { index, appState in
                AppContainerView(appState: appState)
                    .opacity(runtimeManager.currentAppId == appState.appId ? 1 : 0)
                    .zIndex(Double(index + 1))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Show app switcher FAB when apps are running
            if !runtimeManager.runningApps.isEmpty {
                AppSwitcherFAB()
                    .padding()
            }
        }
    }
}

/// Container for a single app instance that preserves its state.
/// Each app gets its own NavigationStack for independent routing.
struct AppContainerView: View {
    let appState: AppRuntimeState

    var body: some View {
        // Wrap each app in its own NavigationStack to preserve navigation state
        NavigationStack {
            AnyView(appState.instance.buildView())
                .navigationTitle(appState.instance.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            AppRuntimeManager.shared.returnToLauncher()
                        } label: {
                            Image(systemName: "house.fill")
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task {
                                await AppRuntimeManager.shared.closeApp(appState.appId)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
        }
        .id(appState.appId) // Preserve identity for state retention
    }
}

#Preview {
    PlaygroundContainer()
}
