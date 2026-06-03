import Foundation
import AVFoundation
import MLX
import MLXAudioTTS
import MLXAudioCore

/// True on-device TTS using MLX Audio Swift
/// This will replace AVSpeechSynthesizer once mlx-audio-swift package is added
class MLXAudioTTSService {
    static let shared = MLXAudioTTSService()

    private init() {}

    private(set) var isLoading = false
    private(set) var loadProgress: Double = 0.0
    private var loadTask: Task<Void, Error>?

    // MARK: - Installation Instructions

    /*
     To use this service:

     1. Open Xcode project
     2. Go to File > Add Package Dependencies
     3. Add: https://github.com/Blaizzy/mlx-audio-swift.git
     4. Select branch: main
     5. Add products: MLXAudioTTS, MLXAudioCore
     6. Uncomment the imports at the top of this file
     7. Uncomment the implementation below
     8. Update AudioGenerationService to use this instead of MLXTTSService
     */

    // MARK: - MLX TTS Implementation

    private var model: FishSpeechModel?

    /// Load the TTS model (call this during app initialization)
    func loadModel() async throws {
        // If already loaded, return
        if model != nil {
            return
        }

        // If currently loading, wait for it
        if let task = loadTask {
            return try await task.value
        }

        // Start loading
        isLoading = true
        loadProgress = 0.0

        let task = Task {
            // Get the configured model ID from ConfigService
            let config = ConfigService.shared
            let modelId: String? = config.getConfig(key: "mlx.tts_model")
            let actualModelId = modelId ?? "mlx-community/fish-audio-s2-pro-8bit"

            print("📦 Loading MLX TTS model (Fish Audio S2 Pro)...")
            print("   This may take a moment on first run (downloading ~300MB)...")

            // Load Fish Audio S2 Pro model (#1 ranked open-weight TTS)
            // Note: fromPretrained doesn't provide progress callbacks, download happens internally
            model = try await FishSpeechModel.fromPretrained(actualModelId)

            print("✅ MLX TTS model loaded successfully")
            self.loadProgress = 1.0

            // Mark as downloaded in ModelRegistry
            do {
                try await ModelRegistry.shared.markAsDownloaded(
                    modelId: actualModelId,
                    sizeMB: 300
                )
                print("✅ Model '\(actualModelId)' marked as downloaded in registry")
            } catch {
                print("⚠️ Failed to mark model as downloaded: \(error)")
            }
        }

        loadTask = task
        try await task.value
        loadTask = nil
        isLoading = false
    }

    // MARK: - Text Preprocessing

    /// Preprocess text for optimal TTS quality
    /// Fish Audio S2 Pro works best with natural sentence structure.
    private func preprocessTextForTTS(_ text: String) -> String {
        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // Single word: add minimal context to reach optimal TTS length
        if words.count == 1 {
            // Using ellipsis for gentle padding (works well with TTS)
            // This prevents syllable cut-off issues common with isolated words
            return "..., \(text)."
        }

        return text
    }

    // MARK: - Speech Synthesis

    /// Generate speech from text
    /// - Parameters:
    ///   - text: Text to convert to speech
    ///   - speed: Speech speed (default: 1.0)
    /// - Returns: Audio data in M4A format
    func synthesize(text: String,
                   model: MLXModelConfig.TTSModel? = nil,
                   voice: String? = nil,
                   language: String? = nil,
                   speed: Double = 1.0) async throws -> Data {
        // Ensure model is loaded (will wait if loading)
        try await loadModel()

        guard let model = self.model else {
            throw MLXAudioTTSError.modelNotLoaded
        }

        print("🎵 Generating audio with MLX TTS (silent): \(text.prefix(50))...")

        // Preprocess text for better quality with single words
        let processedText = preprocessTextForTTS(text)
        if processedText != text {
            print("   Preprocessed single word: '\(text)' -> '\(processedText)'")
        }

        // Generate audio array with required parameters
        let audioMLXArray = try await model.generate(
            text: processedText,
            voice: voice ?? "en-US-Standard-A",
            refAudio: nil,
            refText: nil,
            language: language ?? "en"
        )

        // Convert MLXArray to [Float]
        let audioArray = audioMLXArray.asArray(Float.self)

        // Convert audio array to Data (WAV/CAF format - works directly with PCM)
        let audioData = try convertAudioArrayToWAV(
            audioArray: audioArray,
            sampleRate: Double(model.sampleRate)
        )

        print("✅ Generated \(audioData.count) bytes of audio (silently)")

        return audioData
    }

    /// Convert MLX audio array to WAV/CAF data
    private func convertAudioArrayToWAV(audioArray: [Float], sampleRate: Double) throws -> Data {
        // Add silence padding for single-word inputs (prevents cut-offs)
        let silenceDuration = 0.25  // 250ms before and after
        let silenceSamples = Int(sampleRate * silenceDuration)
        let silence = [Float](repeating: 0.0, count: silenceSamples)

        // Pad audio: silence + audio + silence
        let paddedArray = silence + audioArray + silence

        // Create audio format (PCM Float32)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw MLXAudioTTSError.bufferCreationFailed
        }

        // Create PCM buffer with padded length
        let frameCount = AVAudioFrameCount(paddedArray.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw MLXAudioTTSError.bufferCreationFailed
        }

        buffer.frameLength = frameCount

        // Copy padded audio data
        guard let channelData = buffer.floatChannelData else {
            throw MLXAudioTTSError.bufferCreationFailed
        }

        for (index, sample) in paddedArray.enumerated() {
            channelData[0][index] = sample
        }

        // Write to CAF file (Core Audio Format - native, uncompressed)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")

        let audioFile = try AVAudioFile(
            forWriting: tempURL,
            settings: format.settings
        )

        try audioFile.write(from: buffer)

        let data = try Data(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)

        return data
    }
}

// MARK: - Errors

enum MLXAudioTTSError: Error, LocalizedError {
    case modelNotLoaded
    case bufferCreationFailed
    case synthesizeFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "MLX TTS model not loaded. Call loadModel() first."
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .synthesizeFailed:
            return "Failed to synthesize audio"
        }
    }
}

// MARK: - Installation Guide

/*
 INSTALLATION GUIDE:

 1. Open your Xcode project

 2. Add Swift Package:
    - File > Add Package Dependencies
    - URL: https://github.com/Blaizzy/mlx-audio-swift.git
    - Branch: main
    - Products to add:
      ✓ MLXAudioTTS
      ✓ MLXAudioCore

 3. Uncomment the code in this file:
    - Uncomment the imports at the top
    - Uncomment the implementation section

 4. Initialize the model in your app:
    ```swift
    Task {
        try? await MLXAudioTTSService.shared.loadModel()
    }
    ```

 5. Update AudioGenerationService.swift:
    Replace the mlxTTS initialization:
    ```swift
    private let mlxTTS = MLXAudioTTSService.shared
    ```

 6. Benefits:
    ✅ True on-device inference with MLX
    ✅ Silent audio generation (no playback)
    ✅ High-quality neural TTS
    ✅ No server required
    ✅ Works offline
    ✅ Fast on Apple Silicon
 */
