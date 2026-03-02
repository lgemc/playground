import Foundation
import Alamofire

/// Service for generating audio using both remote TTS API and on-device MLX
/// Supports automatic fallback: MLX (on-device) -> Remote API -> AVSpeechSynthesizer
class AudioGenerationService {
    static let shared = AudioGenerationService()
    private let config = ConfigService.shared
    private let mlxTTS = MLXAudioTTSService.shared

    // Config keys
    private let configKeyUrl = "audio_generation.api_url"
    private let configKeyVoice = "audio_generation.voice"
    private let configKeyModel = "audio_generation.model"
    private let configKeyUseMLX = "audio_generation.use_mlx"
    private let configKeyMLXModel = "audio_generation.mlx_model"
    private let configKeyMLXVoice = "audio_generation.mlx_voice"

    private init() {
        initializeDefaults()
    }

    // MARK: - Configuration

    private func initializeDefaults() {
        config.defineConfig(key: configKeyUrl, value: "http://192.168.0.7:8000")
        config.defineConfig(key: configKeyVoice, value: "alloy")
        config.defineConfig(key: configKeyModel, value: "tts-1")
        config.defineConfig(key: configKeyUseMLX, value: "true")  // Enable MLX Audio Swift TTS
        config.defineConfig(key: configKeyMLXModel, value: "soprano")
        config.defineConfig(key: configKeyMLXVoice, value: "default")

        // Load MLX model in background
        Task {
            do {
                try await mlxTTS.loadModel()
            } catch {
                print("⚠️ Failed to load MLX TTS model: \(error)")
                print("   Will fallback to API if MLX is enabled")
            }
        }
    }

    var apiUrl: String {
        config.getConfig(key: configKeyUrl) ?? ""
    }

    var voice: String {
        config.getConfig(key: configKeyVoice) ?? "alloy"
    }

    var model: String {
        config.getConfig(key: configKeyModel) ?? "tts-1"
    }

    var useMLX: Bool {
        (config.getConfig(key: configKeyUseMLX) ?? "true") == "true"
    }

    var mlxModel: MLXModelConfig.TTSModel {
        let modelName = config.getConfig(key: configKeyMLXModel) ?? "kokoro"
        return MLXModelConfig.TTSModel(rawValue: "mlx-community/\(modelName)") ?? .kokoro
    }

    var mlxVoice: String {
        config.getConfig(key: configKeyMLXVoice) ?? "af_bella"
    }

    var isConfigured: Bool {
        useMLX || !apiUrl.isEmpty
    }

    // MARK: - Audio Generation

    /// Generate audio from text and save to file system
    /// - Parameters:
    ///   - text: Text to convert to speech
    ///   - filename: Desired filename (without extension)
    ///   - customVoice: Optional custom voice (overrides default)
    ///   - customModel: Optional custom model (overrides default)
    /// - Returns: URL of the saved audio file
    func generateAudio(
        text: String,
        filename: String,
        customVoice: String? = nil,
        customModel: String? = nil
    ) async throws -> URL {
        guard isConfigured else {
            throw AudioGenerationError.notConfigured
        }

        let sanitizedFilename = sanitizeFilename(filename)

        // Try MLX first if enabled
        if useMLX {
            do {
                print("🎵 Generating audio with MLX: \(sanitizedFilename)")
                print("   Model: \(mlxModel.rawValue)")
                print("   Voice: \(mlxVoice)")
                print("   Text: \(text.prefix(50))...")

                let audioData = try await mlxTTS.synthesize(
                    text: text,
                    model: mlxModel,
                    voice: mlxVoice,
                    speed: 1.0
                )

                let fileURL = try saveAudioToFile(
                    audioData: audioData,
                    filename: sanitizedFilename
                )

                print("✅ Audio saved (MLX): \(fileURL.path)")
                return fileURL
            } catch {
                print("⚠️ MLX TTS failed, falling back to remote API: \(error)")
                // Fall through to remote API
            }
        }

        // Fallback to remote API
        if !apiUrl.isEmpty {
            return try await generateAudioViaAPI(
                text: text,
                filename: sanitizedFilename,
                customVoice: customVoice,
                customModel: customModel
            )
        }

        throw AudioGenerationError.notConfigured
    }

    /// Generate audio using remote API
    private func generateAudioViaAPI(
        text: String,
        filename: String,
        customVoice: String? = nil,
        customModel: String? = nil
    ) async throws -> URL {
        // Prepare request body (OpenAI-compatible TTS API format)
        let requestBody: [String: Any] = [
            "model": customModel ?? model,
            "input": text,
            "voice": customVoice ?? voice,
            "response_format": "mp3"
        ]

        let url = "\(apiUrl)/v1/audio/speech"

        print("🎵 Generating audio via API: \(filename)")
        print("   API: \(url)")
        print("   Text: \(text.prefix(50))...")

        // Make API request
        return try await withCheckedThrowingContinuation { continuation in
            AF.request(
                url,
                method: .post,
                parameters: requestBody,
                encoding: JSONEncoding.default,
                headers: ["Content-Type": "application/json"]
            )
            .validate()
            .responseData { response in
                switch response.result {
                case .success(let audioData):
                    do {
                        // Save to app documents directory
                        let fileURL = try self.saveAudioToFile(
                            audioData: audioData,
                            filename: filename
                        )

                        print("✅ Audio saved (API): \(fileURL.path)")
                        continuation.resume(returning: fileURL)
                    } catch {
                        print("❌ Failed to save audio: \(error)")
                        continuation.resume(throwing: error)
                    }

                case .failure(let error):
                    print("❌ API request failed: \(error)")
                    if let data = response.data, let errorMessage = String(data: data, encoding: .utf8) {
                        print("   Error response: \(errorMessage)")
                    }
                    continuation.resume(throwing: AudioGenerationError.apiRequestFailed(error))
                }
            }
        }
    }

    // MARK: - File Management

    /// Save audio data to file in generated/audio/vocabulary/ folder
    private func saveAudioToFile(audioData: Data, filename: String) throws -> URL {
        let documentsDirectory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        // Create data/file_system/storage directory structure
        let dataDirectory = documentsDirectory
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("file_system", isDirectory: true)
            .appendingPathComponent("storage", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

        // Create generated/audio/vocabulary folder structure
        let audioDirectory = dataDirectory
            .appendingPathComponent("generated", isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("vocabulary", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let fileURL = audioDirectory.appendingPathComponent(filename)
        try audioData.write(to: fileURL)

        return fileURL
    }

    /// Sanitize filename to ensure it's valid
    private func sanitizeFilename(_ filename: String) -> String {
        // Remove extension if present
        var cleanName = filename.replacingOccurrences(of: #"\.(mp3|wav|ogg|m4a)$"#, with: "", options: .regularExpression)

        // Replace spaces with underscores
        cleanName = cleanName.replacingOccurrences(of: " ", with: "_")

        // Remove non-alphanumeric characters (except underscores and hyphens)
        cleanName = cleanName.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "", options: .regularExpression)

        // Limit length
        if cleanName.count > 100 {
            cleanName = String(cleanName.prefix(100))
        }

        // Add timestamp to ensure uniqueness
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)

        return "\(cleanName)_\(timestamp).caf"
    }

    /// Get relative path for storing in database (relative to data/file_system/storage)
    func getRelativePath(for fileURL: URL) -> String {
        guard let documentsDirectory = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return fileURL.lastPathComponent
        }

        let storageDirectory = documentsDirectory
            .appendingPathComponent("data")
            .appendingPathComponent("file_system")
            .appendingPathComponent("storage")

        let relativePath = fileURL.path.replacingOccurrences(
            of: storageDirectory.path + "/",
            with: ""
        )

        return relativePath
    }

    /// Get absolute URL from relative path (relative to data/file_system/storage)
    func getAbsoluteURL(from relativePath: String) -> URL? {
        guard let documentsDirectory = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return nil
        }

        let storageDirectory = documentsDirectory
            .appendingPathComponent("data")
            .appendingPathComponent("file_system")
            .appendingPathComponent("storage")

        return storageDirectory.appendingPathComponent(relativePath)
    }
}

// MARK: - Errors

enum AudioGenerationError: Error, LocalizedError {
    case notConfigured
    case apiRequestFailed(Error)
    case invalidResponse
    case fileSaveFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Audio generation API not configured"
        case .apiRequestFailed(let error):
            return "API request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from TTS API"
        case .fileSaveFailed:
            return "Failed to save audio file"
        }
    }
}
