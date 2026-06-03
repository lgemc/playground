import Foundation

/// Initializes the ModelRegistry with all available MLX models
actor ModelRegistryInitializer {
    static let shared = ModelRegistryInitializer()

    private var hasInitialized = false

    private init() {}

    func initializeModels() async {
        guard !hasInitialized else { return }

        do {
            // Chat models
            try await registerChatModels()

            // Whisper models
            try await registerWhisperModels()

            // TTS models
            try await registerTTSModels()

            // Image models
            try await registerImageModels()

            // Flux models
            try await registerFluxModels()

            hasInitialized = true
            print("ModelRegistryInitializer: All models registered")
        } catch {
            print("ModelRegistryInitializer: Failed to register models: \(error)")
        }
    }

    private func registerChatModels() async throws {
        let chatModels: [(id: String, name: String, sizeMB: Int)] = [
            ("mlx-community/LFM2.5-1.2B-4bit", "LFM 2.5 1.2B (4-bit)", 800),
            ("mlx-community/Qwen3.5-2B-6bit", "Qwen 3.5 2B (6-bit)", 1600),
            ("mlx-community/Llama-3.2-3B-Instruct-4bit", "Llama 3.2 3B Instruct (4-bit)", 1850),
            ("mlx-community/Qwen3-4B-4bit", "Qwen 3 4B (4-bit)", 2800)
        ]

        for (modelId, name, sizeMB) in chatModels {
            try await ModelRegistry.shared.registerModel(
                id: UUID().uuidString,
                modelId: modelId,
                type: .chat,
                name: name,
                sizeMB: sizeMB
            )
        }
    }

    private func registerWhisperModels() async throws {
        let whisperModels: [(id: String, name: String, sizeMB: Int)] = [
            ("mlx-community/whisper-tiny", "Whisper Tiny", 150),
            ("mlx-community/whisper-base", "Whisper Base", 290),
            ("mlx-community/whisper-small", "Whisper Small", 970),
            ("mlx-community/distil-whisper-large-v3", "Distil Whisper Large v3", 1560)
        ]

        for (modelId, name, sizeMB) in whisperModels {
            try await ModelRegistry.shared.registerModel(
                id: UUID().uuidString,
                modelId: modelId,
                type: .whisper,
                name: name,
                sizeMB: sizeMB
            )
        }
    }

    private func registerTTSModels() async throws {
        let ttsModels: [(id: String, name: String, sizeMB: Int)] = [
            ("mlx-community/fish-audio-s2-pro-8bit", "Fish Audio S2 Pro", 300),
            ("mlx-community/qwen3-tts", "Qwen 3 TTS", 800),
            ("mlx-community/cosyvoice-300m-sft", "CosyVoice 300M SFT", 600)
        ]

        for (modelId, name, sizeMB) in ttsModels {
            try await ModelRegistry.shared.registerModel(
                id: UUID().uuidString,
                modelId: modelId,
                type: .tts,
                name: name,
                sizeMB: sizeMB
            )
        }
    }

    private func registerImageModels() async throws {
        let imageModels: [(id: String, name: String, sizeMB: Int)] = [
            ("mlx-community/stable-diffusion-v1-5-4bit", "Stable Diffusion 1.5 (4-bit)", 1700),
            ("mlx-community/stable-diffusion-2-1-4bit", "Stable Diffusion 2.1 (4-bit)", 2200),
            ("mlx-community/sdxl-turbo-4bit", "SDXL Turbo (4-bit)", 3200)
        ]

        for (modelId, name, sizeMB) in imageModels {
            try await ModelRegistry.shared.registerModel(
                id: UUID().uuidString,
                modelId: modelId,
                type: .image,
                name: name,
                sizeMB: sizeMB
            )
        }
    }

    private func registerFluxModels() async throws {
        let fluxModels: [(id: String, name: String, sizeMB: Int)] = [
            ("mlx-community/FLUX.1-schnell-4bit", "FLUX.1 Schnell (4-bit)", 11000),
            ("mlx-community/FLUX.1-dev-4bit", "FLUX.1 Dev (4-bit)", 11000),
            ("mlx-community/FLUX.1-Kontext-4bit", "FLUX.1 Kontext (4-bit)", 11000)
        ]

        for (modelId, name, sizeMB) in fluxModels {
            try await ModelRegistry.shared.registerModel(
                id: UUID().uuidString,
                modelId: modelId,
                type: .flux,
                name: name,
                sizeMB: sizeMB
            )
        }
    }
}
