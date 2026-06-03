import SwiftUI

/// Settings view for AI Conversions app
struct ConversionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deviceStatus: DeviceStatus?
    @State private var cacheSize: String = "Calculating..."
    @State private var showingClearCacheAlert = false
    @State private var downloadingModelType: MLXModelMetadata.ModelType? = nil
    @State private var downloadProgress: Double = 0.0
    @State private var downloadedModels: [String: Bool] = [:] // Track downloaded models by modelId

    private let config = ConfigService.shared
    private let mlx = MLXService.shared

    var body: some View {
        List {
            Section {
                modelsSection
            } header: {
                Text("AI Models")
            } footer: {
                Text("All models run locally on your device using MLX Swift. No data is sent to external servers.")
                    .font(.caption)
            }

            Section {
                storageSection
            } header: {
                Text("Storage")
            } footer: {
                Text("Models are cached in the app's directory. Clear cache to remove old/unused models and free up space.")
                    .font(.caption)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .alert("Clear Model Cache?", isPresented: $showingClearCacheAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Cache", role: .destructive) {
                clearModelCache()
            }
        } message: {
            Text("This will delete all downloaded AI models. They will be re-downloaded when needed. Current cache: \(cacheSize)")
        }
        .task {
            await loadDeviceStatus()
            await loadDownloadedModels()
            calculateCacheSize()
        }
        .onAppear {
            Task {
                await loadDeviceStatus()
                await loadDownloadedModels()
            }
            calculateCacheSize()
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Model Cache")
                    .font(.body)
                Text(cacheSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Clear") {
                showingClearCacheAlert = true
            }
            .foregroundColor(.red)
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        // Text Model (Chat/Completion)
        ModelRow(
            title: "Text Model",
            modelName: getModelDisplayName(for: .chat),
            modelId: getModelId(for: .chat),
            architecture: getModelArchitecture(for: .chat),
            sizeMB: getModelSize(for: .chat),
            isDownloaded: isModelDownloaded(type: .chat),
            isDownloading: downloadingModelType == .chat,
            downloadProgress: downloadingModelType == .chat ? downloadProgress : 0,
            onDownload: {
                downloadModel(type: .chat)
            },
            onDelete: {
                deleteModel(type: .chat)
            }
        )

        // Audio/Video to Text (Whisper)
        ModelRow(
            title: "Audio/Video → Text",
            modelName: getModelDisplayName(for: .whisper),
            modelId: getModelId(for: .whisper),
            architecture: getModelArchitecture(for: .whisper),
            sizeMB: getModelSize(for: .whisper),
            isDownloaded: isModelDownloaded(type: .whisper),
            isDownloading: downloadingModelType == .whisper,
            downloadProgress: downloadingModelType == .whisper ? downloadProgress : 0,
            onDownload: {
                downloadModel(type: .whisper)
            },
            onDelete: {
                deleteModel(type: .whisper)
            }
        )

        // Text to Audio (TTS)
        ModelRow(
            title: "Text → Audio",
            modelName: getModelDisplayName(for: .tts),
            modelId: getModelId(for: .tts),
            architecture: getModelArchitecture(for: .tts),
            sizeMB: getModelSize(for: .tts),
            isDownloaded: isModelDownloaded(type: .tts),
            isDownloading: downloadingModelType == .tts,
            downloadProgress: downloadingModelType == .tts ? downloadProgress : 0,
            onDownload: {
                downloadModel(type: .tts)
            },
            onDelete: {
                deleteModel(type: .tts)
            }
        )
    }

    // MARK: - Helpers

    private func loadDeviceStatus() async {
        deviceStatus = await mlx.getDeviceStatus()
    }

    private func loadDownloadedModels() async {
        do {
            let models = try await ModelRegistry.shared.getAllModels()
            var downloadedMap: [String: Bool] = [:]
            for model in models where model.isDownloaded {
                downloadedMap[model.modelId] = true
            }
            await MainActor.run {
                self.downloadedModels = downloadedMap
            }
        } catch {
            print("Failed to load downloaded models: \(error)")
        }
    }

    private func getModelId(for type: MLXModelMetadata.ModelType) -> String {
        switch type {
        case .chat:
            let modelId: String? = config.getConfig(key: "mlx.chat_model")
            return modelId ?? ""
        case .whisper:
            let modelId: String? = config.getConfig(key: "mlx.whisper_model")
            return modelId ?? ""
        case .tts:
            let modelId: String? = config.getConfig(key: "mlx.tts_model")
            return modelId ?? ""
        case .image:
            return ""
        }
    }

    private func getModelDisplayName(for type: MLXModelMetadata.ModelType) -> String {
        let modelId = getModelId(for: type)
        return modelId.components(separatedBy: "/").last ?? "Unknown"
    }

    private func getModelArchitecture(for type: MLXModelMetadata.ModelType) -> String {
        switch type {
        case .chat:
            return "Qwen 3.5 (6-bit quantized)"
        case .whisper:
            let modelId: String? = config.getConfig(key: "mlx.whisper_model")
            if let modelId = modelId {
                if modelId.contains("tiny") {
                    return "Whisper Tiny (39M params)"
                } else if modelId.contains("base") {
                    return "Whisper Base (244M params)"
                } else if modelId.contains("small") {
                    return "Whisper Small (769M params)"
                } else if modelId.contains("distil") {
                    return "Whisper Distil Large V3"
                }
            }
            return "Whisper"
        case .tts:
            let modelId: String? = config.getConfig(key: "mlx.tts_model")
            if let modelId = modelId {
                if modelId.contains("fish-audio") {
                    return "Fish Audio S2 Pro"
                } else if modelId.contains("qwen3") {
                    return "Qwen3 TTS (0.6B, 4-bit)"
                } else if modelId.contains("cosyvoice") {
                    return "CosyVoice (DiT flow)"
                }
            }
            return "TTS"
        case .image:
            return "N/A"
        }
    }

    private func getModelSize(for type: MLXModelMetadata.ModelType) -> Int {
        switch type {
        case .chat:
            return MLXModelConfig.ChatModel.qwen3_5_2b_6bit.estimatedMemoryMB
        case .whisper:
            let modelId: String? = config.getConfig(key: "mlx.whisper_model")
            if let modelId = modelId {
                if modelId.contains("tiny") {
                    return MLXModelConfig.WhisperModel.tiny.estimatedMemoryMB
                } else if modelId.contains("base") {
                    return MLXModelConfig.WhisperModel.base.estimatedMemoryMB
                } else if modelId.contains("small") {
                    return MLXModelConfig.WhisperModel.small.estimatedMemoryMB
                } else if modelId.contains("distil") {
                    return MLXModelConfig.WhisperModel.distilLargeV3.estimatedMemoryMB
                }
            }
            return 500
        case .tts:
            let modelId: String? = config.getConfig(key: "mlx.tts_model")
            if let modelId = modelId {
                if modelId.contains("fish-audio") {
                    return MLXModelConfig.TTSModel.fishAudio.estimatedMemoryMB
                } else if modelId.contains("qwen3") {
                    return MLXModelConfig.TTSModel.qwen3.estimatedMemoryMB
                } else if modelId.contains("cosyvoice") {
                    return MLXModelConfig.TTSModel.cosyvoice.estimatedMemoryMB
                }
            }
            return 350
        case .image:
            return 0
        }
    }

    private func isModelDownloaded(type: MLXModelMetadata.ModelType) -> Bool {
        let modelId = getModelId(for: type)
        return downloadedModels[modelId] == true
    }

    private func calculateCacheSize() {
        Task {
            // Check both cache locations that MLX uses
            let fileManager = FileManager.default
            var totalSize: Int64 = 0

            // Location 1: Library/Caches/huggingface/hub
            if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
                let hfCachePath = cachesURL
                    .appendingPathComponent("huggingface")
                    .appendingPathComponent("hub")
                totalSize += getDirectorySize(url: hfCachePath)
            }

            // Location 2: Library/Application Support/.cache/huggingface/hub
            if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let hfAppSupportPath = appSupportURL
                    .appendingPathComponent(".cache")
                    .appendingPathComponent("huggingface")
                    .appendingPathComponent("hub")
                totalSize += getDirectorySize(url: hfAppSupportPath)
            }

            await MainActor.run {
                self.cacheSize = self.formatBytes(totalSize)
            }
        }
    }

    private func getDirectorySize(url: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0

        guard fileManager.fileExists(atPath: url.path) else {
            return 0
        }

        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(resourceValues.fileSize ?? 0)
            } catch {
                // Skip files we can't access
            }
        }

        return totalSize
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func clearModelCache() {
        Task {
            let fileManager = FileManager.default

            // Location 1: Library/Caches/huggingface
            if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
                let hfCachePath = cachesURL.appendingPathComponent("huggingface")
                if fileManager.fileExists(atPath: hfCachePath.path) {
                    do {
                        try fileManager.removeItem(at: hfCachePath)
                        print("✅ Cleared cache at: \(hfCachePath.path)")
                    } catch {
                        print("❌ Failed to clear cache at \(hfCachePath.path): \(error)")
                    }
                }
            }

            // Location 2: Library/Application Support/.cache/huggingface
            if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let hfAppSupportPath = appSupportURL.appendingPathComponent(".cache").appendingPathComponent("huggingface")
                if fileManager.fileExists(atPath: hfAppSupportPath.path) {
                    do {
                        try fileManager.removeItem(at: hfAppSupportPath)
                        print("✅ Cleared cache at: \(hfAppSupportPath.path)")
                    } catch {
                        print("❌ Failed to clear cache at \(hfAppSupportPath.path): \(error)")
                    }
                }
            }

            // Clear model registry database (safely)
            // Note: We just deleted the files above, so we don't need to call
            // ModelRegistry.deleteModel which tries to delete files again
            // Just clear the registry records directly would be safer
            print("✅ Model cache cleared (files deleted)")

            // Refresh downloaded models list and recalculate cache size
            await loadDownloadedModels()
            calculateCacheSize()
        }
    }

    private func downloadModel(type: MLXModelMetadata.ModelType) {
        let modelId = getModelId(for: type)
        guard !modelId.isEmpty else { return }

        // Approve the model download
        let _ = ModelPermissionService.shared.approve(modelId: modelId, modelType: type.typeString)

        print("✅ Starting download for: \(modelId)")

        downloadingModelType = type
        downloadProgress = 0.0

        Task {
            do {
                switch type {
                case .chat:
                    // Trigger actual download by loading the model
                    let chatModel = MLXModelConfig.ChatModel.qwen3_5_2b_6bit
                    _ = try await mlx.chat.loadModel(chatModel)

                    // Monitor progress
                    while mlx.chat.isLoading {
                        await MainActor.run {
                            downloadProgress = mlx.chat.loadProgress
                        }
                        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 sec
                    }

                case .whisper:
                    let whisperModel = MLXModelConfig.WhisperModel.small
                    _ = try await mlx.whisper.loadModel(whisperModel)

                case .tts:
                    // TTS uses MLXAudioTTSService - monitor progress
                    _ = try await MLXAudioTTSService.shared.loadModel()

                    // Monitor progress (though TTS downloads don't report granular progress)
                    while MLXAudioTTSService.shared.isLoading {
                        await MainActor.run {
                            // TTS doesn't provide real-time progress, so show indeterminate
                            downloadProgress = MLXAudioTTSService.shared.loadProgress
                        }
                        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 sec
                    }

                case .image:
                    break
                }

                print("✅ Download complete for: \(modelId)")

                // Reset downloading state
                await MainActor.run {
                    downloadingModelType = nil
                    downloadProgress = 0.0
                }

                // Refresh status and downloaded models list
                await loadDeviceStatus()
                await loadDownloadedModels()
            } catch {
                print("❌ Download failed: \(error)")
                await MainActor.run {
                    downloadingModelType = nil
                    downloadProgress = 0.0
                }
            }
        }
    }

    private func deleteModel(type: MLXModelMetadata.ModelType) {
        let modelId = getModelId(for: type)
        guard !modelId.isEmpty else { return }

        Task {
            do {
                // Delete from ModelRegistry (also deletes files)
                try await ModelRegistry.shared.deleteModel(modelId: modelId)

                // Reset permission
                let _ = ModelPermissionService.shared.resetPermission(modelId: modelId)

                print("✅ Deleted model: \(modelId)")

                // Refresh
                await loadDeviceStatus()
                await loadDownloadedModels()
                calculateCacheSize()
            } catch {
                print("❌ Failed to delete model: \(error)")
            }
        }
    }
}

// MARK: - Model Row Component

struct ModelRow: View {
    let title: String
    let modelName: String
    let modelId: String
    let architecture: String
    let sizeMB: Int
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let onDownload: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Model:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(modelName)
                        .font(.caption)
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Architecture:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(architecture)
                        .font(.caption)
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Size:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatSize(sizeMB))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }

            // Progress bar
            if isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Downloading...")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Spacer()
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)
                }
            }

            // Action buttons
            if !isDownloading {
                HStack(spacing: 12) {
                    if isDownloaded {
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            Label("Delete", systemImage: "trash")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Button(action: onDownload) {
                            Label("Download", systemImage: "arrow.down.circle")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .alert("Delete Model?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This will delete \(modelName) (\(formatSize(sizeMB))). It will be re-downloaded when needed.")
        }
    }

    private func formatSize(_ mb: Int) -> String {
        if mb >= 1000 {
            return String(format: "%.1f GB", Double(mb) / 1024.0)
        } else {
            return "\(mb) MB"
        }
    }
}

// MARK: - Extension for ModelType

extension MLXModelMetadata.ModelType {
    var typeString: String {
        switch self {
        case .chat: return "chat"
        case .whisper: return "whisper"
        case .tts: return "tts"
        case .image: return "image"
        }
    }
}

#Preview {
    NavigationStack {
        ConversionSettingsView()
    }
}
