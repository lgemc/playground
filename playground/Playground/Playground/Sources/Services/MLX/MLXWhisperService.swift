import Foundation
import AVFoundation
import WhisperKit

/// Native on-device speech-to-text service using WhisperKit
/// Runs entirely on-device with Apple's Neural Engine - no server required!
class MLXWhisperService {
    static let shared = MLXWhisperService()
    private let config = ConfigService.shared

    // Currently loaded Whisper model
    private var whisperKit: WhisperKit?
    private var currentModelId: String?

    private init() {}

    // MARK: - Model Loading

    /// Load a Whisper model (lazy loading)
    func loadModel(_ modelConfig: MLXModelConfig.WhisperModel) async throws -> WhisperKit {
        // Check if already loaded
        if let current = whisperKit,
           currentModelId == modelConfig.rawValue {
            return current
        }

        print("Loading Whisper model: \(modelConfig.whisperKitName)")

        // Initialize WhisperKit with specified model
        let whisper = try await WhisperKit(
            WhisperKitConfig(
                model: modelConfig.whisperKitName,
                verbose: true,
                logLevel: .info
            )
        )

        whisperKit = whisper
        currentModelId = modelConfig.rawValue

        print("Whisper model loaded successfully!")
        return whisper
    }

    // MARK: - Speech-to-Text

    /// Transcribe audio file to text
    func transcribe(audioURL: URL,
                   model: MLXModelConfig.WhisperModel? = nil,
                   language: String? = nil) async throws -> TranscriptionResponse {

        let modelToUse = model ?? getDefaultWhisperModel()
        let whisper = try await loadModel(modelToUse)

        // Transcribe audio using WhisperKit
        let results = try await whisper.transcribe(audioPath: audioURL.path)

        guard let transcriptionResult = results.first else {
            throw MLXWhisperError.invalidResponse
        }

        // Convert to our response format
        return TranscriptionResponse(
            text: transcriptionResult.text,
            language: language ?? transcriptionResult.language,
            duration: nil,
            segments: transcriptionResult.segments.map { segment in
                TranscriptionResponse.Segment(
                    id: segment.id,
                    start: Double(segment.start),
                    end: Double(segment.end),
                    text: segment.text
                )
            }
        )
    }

    /// Transcribe audio data directly
    func transcribe(audioData: Data,
                   model: MLXModelConfig.WhisperModel? = nil,
                   language: String? = nil) async throws -> TranscriptionResponse {

        // Create temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        try audioData.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        return try await transcribe(
            audioURL: tempURL,
            model: model,
            language: language
        )
    }

    /// Real-time streaming transcription (for live audio)
    func transcribeStream(audioStream: AsyncStream<Data>,
                         model: MLXModelConfig.WhisperModel? = nil,
                         language: String? = nil) -> AsyncThrowingStream<String, Error> {

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Load model once
                    _ = try await loadModel(model ?? getDefaultWhisperModel())

                    var audioBuffer = Data()
                    let chunkDuration: TimeInterval = 30.0  // 30 seconds
                    let sampleRate: Double = 16000
                    let bytesPerChunk = Int(chunkDuration * sampleRate * 2)  // 16-bit audio

                    for await chunk in audioStream {
                        audioBuffer.append(chunk)

                        // Process when we have enough data
                        if audioBuffer.count >= bytesPerChunk {
                            let result = try await transcribe(
                                audioData: audioBuffer,
                                model: model,
                                language: language
                            )

                            continuation.yield(result.text)
                            audioBuffer.removeAll()
                        }
                    }

                    // Process remaining audio
                    if !audioBuffer.isEmpty {
                        let result = try await transcribe(
                            audioData: audioBuffer,
                            model: model,
                            language: language
                        )
                        continuation.yield(result.text)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Transcribe from microphone (convenience method)
    func transcribeFromMicrophone(
        duration: TimeInterval = 5.0,
        model: MLXModelConfig.WhisperModel? = nil,
        language: String? = nil
    ) async throws -> TranscriptionResponse {

        // Record audio
        let audioURL = try await recordAudio(duration: duration)

        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }

        return try await transcribe(
            audioURL: audioURL,
            model: model,
            language: language
        )
    }

    // MARK: - Helper Methods

    private func getDefaultWhisperModel() -> MLXModelConfig.WhisperModel {
        let availableMemoryGB = MLXChatService.shared.getAvailableMemoryGB()
        return MLXModelConfig.recommendedWhisperModel(availableMemoryGB: availableMemoryGB)
    }

    /// Record audio from microphone
    private func recordAudio(duration: TimeInterval) async throws -> URL {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        #if os(iOS)
        // Configure audio session (iOS only)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default)
        try audioSession.setActive(true)
        #endif

        // Configure recording settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        // Create and start recorder
        let recorder = try AVAudioRecorder(url: audioURL, settings: settings)
        recorder.record(forDuration: duration)

        // Wait for recording to finish
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

        recorder.stop()

        return audioURL
    }

    /// Unload current model to free memory
    func unloadModel() {
        whisperKit = nil
        currentModelId = nil
    }
}

// MARK: - Supporting Types

struct TranscriptionResponse: Codable {
    let text: String
    let language: String?
    let duration: Double?
    let segments: [Segment]?

    struct Segment: Codable {
        let id: Int
        let start: Double
        let end: Double
        let text: String
    }
}

// MARK: - WhisperKit Extensions

extension MLXModelConfig.WhisperModel {
    /// Map to WhisperKit model names
    var whisperKitName: String {
        switch self {
        case .tiny:
            return "tiny"
        case .base:
            return "base"
        case .small:
            return "small"
        case .distilLargeV3:
            return "distil-large-v3"
        }
    }
}

enum MLXWhisperError: Error {
    case invalidResponse
    case audioLoadFailed
    case modelLoadFailed(Error)
    case recordingFailed(Error)
}
