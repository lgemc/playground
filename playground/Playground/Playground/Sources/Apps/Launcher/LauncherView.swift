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

    var body: some View {
        NavigationLink {
            app.buildView()
                .navigationTitle(app.name)
                .navigationBarTitleDisplayMode(.inline)
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
    var body: some View {
        Form {
            Section("AI Model") {
                HStack {
                    Text("Model")
                    Spacer()
                    Text("Qwen3.5 2B")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Provider")
                    Spacer()
                    Text("MLX (On-Device)")
                        .foregroundColor(.secondary)
                }
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
