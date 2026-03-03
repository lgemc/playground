import SwiftUI

/// Launcher view - the "home screen" showing all available apps
struct LauncherView: View {
    @StateObject private var registry = AppRegistry.shared
    @State private var showingSettings = false

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 20)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(registry.getAllApps(), id: \.id) { app in
                        AppIconButton(app: app)
                    }
                }
                .padding()
            }
            .navigationTitle("Playground")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsPlaceholder()
                }
            }   
        }
    }
}

/// Individual app icon button in the launcher
struct AppIconButton: View {
    let app: any SubApp
    @StateObject private var runtimeManager = AppRuntimeManager.shared

    var body: some View {
        Button {
            Task {
                // Launch app using AppRuntimeManager
                // This will either create a new instance or switch to existing one
                await runtimeManager.launchApp(appId: app.id) {
                    return app
                }
            }
        } label: {
            VStack(spacing: 8) {
                // App Icon
                ZStack {
                    Circle()
                        .fill(app.themeColor)
                        .frame(width: 80, height: 80)

                    Image(systemName: app.iconName)
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                }

                // App Name
                Text(app.name)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 100)
        }
        .buttonStyle(.plain)
    }
}

/// Placeholder settings view
struct SettingsPlaceholder: View {
    @StateObject private var configService = ConfigService.shared

    var body: some View {
        Form {
            Section("LLM Configuration") {
                TextField("Base URL", text: Binding(
                    get: { configService.getString(key: "llm.base_url") },
                    set: { configService.setConfig(key: "llm.base_url", value: $0) }
                ))
                .autocapitalization(.none)

                SecureField("API Key", text: Binding(
                    get: { configService.getString(key: "llm.api_key") },
                    set: { configService.setConfig(key: "llm.api_key", value: $0) }
                ))

                TextField("Model", text: Binding(
                    get: { configService.getString(key: "llm.model") },
                    set: { configService.setConfig(key: "llm.model", value: $0) }
                ))
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        LauncherView()
    }
}
