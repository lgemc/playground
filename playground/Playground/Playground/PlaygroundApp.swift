import SwiftUI

@main
struct PlaygroundApp: App {
    init() {
        print("🚀 PlaygroundApp init started")

        // Initialize core services
        print("📦 Initializing AppRegistry...")
        _ = AppRegistry.shared

        print("⚙️ Initializing ConfigService...")
        _ = ConfigService.shared

        print("🚌 Initializing AppBus...")
        _ = AppBus.shared

        print("📋 Initializing QueueService...")
        QueueService.shared.initialize()

        print("📝 Initializing DerivativeService...")
        DerivativeService.shared.initialize()

        // Register sub-apps
        print("📱 Registering sub-apps...")
        AppRegistry.shared.register(ChatApp())
        AppRegistry.shared.register(VocabularyApp())
        AppRegistry.shared.register(FileSystemApp())
        AppRegistry.shared.register(QueuesApp())
        AppRegistry.shared.register(LogsApp())
        AppRegistry.shared.register(ImageGenApp())

        // Register tools for LLM
        print("🛠️ Registering tools...")
        // TODO: Re-implement GenerateImageTool with proper Swift 6 concurrency
        // Task {
        //     await ToolService.shared.register(GenerateImageTool.create())
        // }

        print("✅ PlaygroundApp init completed")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var registry = AppRegistry.shared

    var body: some View {
        NavigationStack {
            LauncherView()
        }
    }
}
