import SwiftUI

@main
struct PlaygroundApp: App {
    init() {
        print("🚀 PlaygroundApp init started")

        // Debug: Print container path to track changes on rebuild
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            print("📂 ==================== STORAGE DIAGNOSTICS ====================")
            print("📂 App Container Path:")
            print("   \(documentsURL.path)")

            // Check if storage directory exists and list files
            let storageURL = documentsURL
                .appendingPathComponent("data")
                .appendingPathComponent("file_system")
                .appendingPathComponent("storage")

            print("\n📂 Storage Directory:")
            print("   \(storageURL.path)")

            if FileManager.default.fileExists(atPath: storageURL.path) {
                print("✅ Storage directory EXISTS")

                // List all contents recursively
                if let enumerator = FileManager.default.enumerator(atPath: storageURL.path) {
                    var fileCount = 0
                    print("\n📁 Contents:")
                    while let file = enumerator.nextObject() as? String {
                        fileCount += 1
                        let fullPath = storageURL.appendingPathComponent(file).path
                        let isDirectory = (try? FileManager.default.attributesOfItem(atPath: fullPath)[.type] as? FileAttributeType) == .typeDirectory
                        let icon = isDirectory ? "📁" : "📄"
                        print("   \(icon) \(file)")
                        if fileCount >= 20 {
                            print("   ... (showing first 20 items)")
                            break
                        }
                    }
                    if fileCount == 0 {
                        print("   ⚠️ Directory exists but is EMPTY")
                    }
                }
            } else {
                print("⚠️ Storage directory DOES NOT EXIST - will be created on first file add")
            }

            // Check database for file records
            print("\n💾 Database File Records:")
            let result = FileStorage.shared.getAllFiles()
            switch result {
            case .ok(let files):
                print("   Found \(files.count) file(s) in database")
                for file in files.prefix(5) {
                    let exists = FileManager.default.fileExists(atPath: file.absolutePath)
                    let icon = exists ? "✅" : "❌"
                    print("   \(icon) \(file.name)")
                    print("      Relative: \(file.relativePath ?? "nil")")
                    print("      Absolute: \(file.absolutePath)")
                    print("      Exists on disk: \(exists)")
                }
                if files.count > 5 {
                    print("   ... (showing first 5 files)")
                }
            case .err(let error):
                print("   ❌ Error reading database: \(error)")
            }

            print("📂 ============================================================\n")
        }

        // Initialize core services
        print("📦 Initializing AppRegistry...")
        _ = AppRegistry.shared

        print("🎮 Initializing AppRuntimeManager...")
        _ = AppRuntimeManager.shared

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

        print("✅ PlaygroundApp init completed")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        PlaygroundContainer()
    }
}
