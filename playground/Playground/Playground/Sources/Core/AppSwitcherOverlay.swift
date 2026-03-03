import SwiftUI

/// Overlay that shows all running apps in a switcher interface.
/// Users can tap to switch to an app or close apps.
struct AppSwitcherOverlay: View {
    @StateObject private var runtimeManager = AppRuntimeManager.shared
    @StateObject private var registry = AppRegistry.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingCloseConfirmation = false
    @State private var appToClose: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if runtimeManager.runningApps.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "square.stack.3d.up.slash")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)

                        Text("No running apps")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Horizontal scrollable app list
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(runtimeManager.runningAppsList) { appState in
                                AppCard(
                                    appState: appState,
                                    onTap: {
                                        runtimeManager.switchToApp(appState.appId)
                                        dismiss()
                                    },
                                    onClose: {
                                        appToClose = appState.appId
                                        showingCloseConfirmation = true
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Running Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        runtimeManager.returnToLauncher()
                        dismiss()
                    } label: {
                        Label("Home", systemImage: "house.fill")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .alert("Close App", isPresented: $showingCloseConfirmation) {
                Button("Cancel", role: .cancel) {
                    appToClose = nil
                }
                Button("Close", role: .destructive) {
                    if let appId = appToClose {
                        Task {
                            await runtimeManager.closeApp(appId)
                            // If no more apps, dismiss the overlay
                            if runtimeManager.runningApps.isEmpty {
                                dismiss()
                            }
                        }
                        appToClose = nil
                    }
                }
            } message: {
                Text("Are you sure you want to close this app?")
            }
        }
    }
}

/// Card widget representing a running app in the switcher.
struct AppCard: View {
    let appState: AppRuntimeState
    let onTap: () -> Void
    let onClose: () -> Void

    @StateObject private var runtimeManager = AppRuntimeManager.shared
    @StateObject private var registry = AppRegistry.shared

    var body: some View {
        let app = registry.apps[appState.appId] ?? appState.instance
        let isCurrentApp = runtimeManager.currentAppId == appState.appId

        Button(action: onTap) {
            VStack(spacing: 12) {
                // App icon with close button
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(app.themeColor.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .overlay {
                            Image(systemName: app.iconName)
                                .font(.system(size: 40))
                                .foregroundColor(app.themeColor)
                        }

                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.red)
                            .background(Circle().fill(.white))
                    }
                    .offset(x: 8, y: -8)
                }

                // App name
                Text(app.name)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(width: 140)

                // Status indicator
                if isCurrentApp {
                    Text("Active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .foregroundColor(.accentColor)
                        .cornerRadius(12)
                }
            }
            .frame(width: 160)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(isCurrentApp ? 0.3 : 0.1), radius: isCurrentApp ? 8 : 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AppSwitcherOverlay()
}
