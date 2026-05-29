import Foundation
import AVFoundation

/// Native on-device text-to-speech service using AVFoundation
/// Uses AVSpeechSynthesizer with AVAudioEngine for file export
class MLXTTSService {
    static let shared = MLXTTSService()
    private let config = ConfigService.shared

    private init() {}

    // MARK: - Text-to-Speech

    /// Generate speech from text (non-streaming)
    /// Returns audio data in M4A format using AVSpeechSynthesizer.write()
    @MainActor
    func synthesize(text: String,
                   model: MLXModelConfig.TTSModel? = nil,
                   voice: String? = nil,
                   language: String? = nil,
                   speed: Double = 1.0) async throws -> Data {

        print("✅ Generating audio with AVSpeechSynthesizer.write() (SILENT)")

        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)

        // Configure voice
        if let language = language {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        utterance.rate = Float(speed * 0.5)

        // Create temporary CAF file (uncompressed PCM)
        let cafURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var audioFile: AVAudioFile?
            var bufferCount = 0

            synthesizer.write(utterance) { (buffer: AVAudioBuffer) in
                // Cast to PCM buffer
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    return
                }

                // Check if this is an empty buffer (completion signal)
                if pcmBuffer.frameLength == 0 {
                    if !hasResumed {
                        hasResumed = true
                        print("✅ Wrote \(bufferCount) audio buffers to CAF")

                        Task {
                            do {
                                // Convert CAF to M4A
                                let m4aURL = cafURL.deletingPathExtension().appendingPathExtension("m4a")
                                try await self.convertCAFToM4A(from: cafURL, to: m4aURL)

                                let audioData = try Data(contentsOf: m4aURL)
                                try? FileManager.default.removeItem(at: cafURL)
                                try? FileManager.default.removeItem(at: m4aURL)

                                print("✅ Successfully converted to M4A (\(audioData.count) bytes)")
                                continuation.resume(returning: audioData)
                            } catch {
                                print("❌ Conversion failed: \(error)")
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                    return
                }

                // Write buffer to CAF file (uncompressed)
                do {
                    if audioFile == nil {
                        audioFile = try AVAudioFile(
                            forWriting: cafURL,
                            settings: pcmBuffer.format.settings
                        )
                        print("📝 Created CAF file: sampleRate=\(pcmBuffer.format.sampleRate), channels=\(pcmBuffer.format.channelCount)")
                    }
                    try audioFile?.write(from: pcmBuffer)
                    bufferCount += 1
                } catch {
                    if !hasResumed {
                        hasResumed = true
                        print("❌ Failed to write audio buffer: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Convert CAF (uncompressed) to M4A (compressed AAC)
    private func convertCAFToM4A(from cafURL: URL, to m4aURL: URL) async throws {
        let asset = AVURLAsset(url: cafURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MLXTTSError.synthesizeFailed
        }

        exportSession.outputURL = m4aURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        guard exportSession.status == .completed else {
            if let error = exportSession.error {
                print("❌ Export failed: \(error)")
                throw error
            }
            throw MLXTTSError.synthesizeFailed
        }

        print("✅ CAF → M4A conversion completed")
    }

    /// Generate speech from text and save to file
    func synthesizeToFile(text: String,
                         outputURL: URL,
                         model: MLXModelConfig.TTSModel? = nil,
                         voice: String? = nil,
                         language: String? = nil,
                         speed: Double = 1.0) async throws {

        // Simple implementation: just get audio data and write to file
        let audioData = try await synthesize(
            text: text,
            model: model,
            voice: voice,
            language: language,
            speed: speed
        )

        try audioData.write(to: outputURL)
    }

    /// Speak directly (convenience method)
    func speak(text: String,
              model: MLXModelConfig.TTSModel? = nil,
              voice: String? = nil,
              language: String? = nil,
              speed: Double = 1.0) async throws {

        return try await withCheckedThrowingContinuation { continuation in
            let synthesizer = AVSpeechSynthesizer()
            let utterance = AVSpeechUtterance(string: text)

            // Configure voice
            if let language = language {
                utterance.voice = AVSpeechSynthesisVoice(language: language)
            } else if let voiceId = voice {
                utterance.voice = AVSpeechSynthesisVoice(identifier: voiceId)
            }

            utterance.rate = Float(speed * 0.5)

            // Create delegate to handle completion
            let delegate = SpeechDelegate {
                continuation.resume()
            }

            synthesizer.delegate = delegate
            synthesizer.speak(utterance)

            // Keep delegate alive
            objc_setAssociatedObject(
                synthesizer,
                "delegate",
                delegate,
                .OBJC_ASSOCIATION_RETAIN
            )
        }
    }

    /// Streaming text-to-speech (for real-time playback)
    /// Note: AVSpeechSynthesizer doesn't support true streaming
    /// This is a placeholder for future mlx-audio-swift integration
    func synthesizeStream(text: String,
                         model: MLXModelConfig.TTSModel? = nil,
                         voice: String? = nil,
                         language: String? = nil,
                         speed: Double = 1.0) -> AsyncThrowingStream<Data, Error> {

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // For now, just return the full audio as a single chunk
                    let audioData = try await synthesize(
                        text: text,
                        model: model,
                        voice: voice,
                        language: language,
                        speed: speed
                    )

                    continuation.yield(audioData)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Get available voices
    func getAvailableVoices(model: MLXModelConfig.TTSModel? = nil) async throws -> [String] {
        // Return all available AVSpeechSynthesisVoices
        let voices = AVSpeechSynthesisVoice.speechVoices()
        return voices.map { voice in
            "\(voice.name) (\(voice.language)) - \(voice.identifier)"
        }
    }

    /// Stop current speech (not implemented for stateless service)
    func stop() {
        // No-op - each synthesize call creates its own synthesizer
        // In a real implementation, we'd need to track active synthesizers
    }
}

// MARK: - Speech Delegate

private class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onComplete()
    }
}

// MARK: - Speech Capture Delegate (for audio capture)

private class SpeechCaptureDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let audioEngine: AVAudioEngine?
    let onComplete: () -> Void
    let onError: (Error) -> Void

    init(audioEngine: AVAudioEngine?, onComplete: @escaping () -> Void, onError: @escaping (Error) -> Void) {
        self.audioEngine = audioEngine
        self.onComplete = onComplete
        self.onError = onError
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onComplete()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onError(MLXTTSError.synthesizeFailed)
    }
}

// MARK: - Errors

enum MLXTTSError: Error {
    case invalidResponse
    case invalidAudioData
    case synthesizeFailed
    case playbackFailed
}

// MARK: - Note on Future Integration

/*
 TODO: Integrate mlx-audio-swift for native TTS

 When mlx-audio-swift becomes available for iOS, replace AVSpeechSynthesizer with:

 import MLXAudio

 let tts = try await MLXAudio.TTS(
     model: "kokoro-82m",  // or other mlx-community TTS models
     voice: "af_bella"
 )

 let audioData = try await tts.synthesize(
     text: text,
     speed: speed
 )

 Benefits:
 - Much higher quality voices
 - Multilingual support (54 voices for Kokoro)
 - Faster generation
 - Offline support with mlx-community models
 - Full control over voice characteristics
 */
