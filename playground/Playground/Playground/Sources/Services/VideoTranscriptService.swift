import Foundation
import AVFoundation

/// Service that transcribes video and audio files using MLX Whisper (on-device)
/// Matches the Dart TranscriptGenerator implementation
class VideoTranscriptService {
    static let shared = VideoTranscriptService()

    private let whisperService = MLXWhisperService.shared

    // Supported video/audio MIME types
    private let supportedMimeTypes: Set<String> = [
        "video/mp4",
        "video/mpeg",
        "video/quicktime",
        "video/x-msvideo",
        "video/webm",
        "audio/mpeg",
        "audio/mp3",
        "audio/wav",
        "audio/ogg",
        "audio/flac",
        "audio/m4a",
        "audio/x-m4a",
        "audio/aac"
    ]

    // Supported extensions (fallback when MIME type unavailable)
    private let supportedExtensions: Set<String> = [
        "mp4", "mpeg", "mpg", "mov", "avi", "webm",
        "mp3", "wav", "ogg", "flac", "m4a", "aac"
    ]

    private init() {}

    // MARK: - Public API

    /// Check if a file can be transcribed
    func canProcess(fileURL: URL, mimeType: String? = nil) -> Bool {
        // Check MIME type first
        if let mime = mimeType {
            if supportedMimeTypes.contains(mime) {
                return true
            }
            // Also check partial MIME type matches
            for supportedMime in supportedMimeTypes {
                if mime.contains(supportedMime.components(separatedBy: "/").last ?? "") {
                    return true
                }
            }
        }

        // Fallback to extension check
        let ext = fileURL.pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    /// Generate transcript for a video or audio file
    /// - Parameters:
    ///   - fileURL: URL to the video/audio file
    ///   - model: Whisper model to use (optional, will use recommended)
    ///   - language: Expected language (optional)
    /// - Returns: Transcript data as JSON
    func generateTranscript(
        fileURL: URL,
        model: MLXModelConfig.WhisperModel? = nil,
        language: String? = nil
    ) async throws -> TranscriptData {
        print("📝 [VideoTranscriptService] Starting transcription...")
        print("   File: \(fileURL.lastPathComponent)")
        print("   Path: \(fileURL.path)")

        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw VideoTranscriptError.fileNotFound(fileURL.path)
        }

        // Extract audio if it's a video file
        let audioURL: URL
        let isVideo = fileURL.pathExtension.lowercased().starts(with: "mp") ||
                     ["mov", "avi", "webm"].contains(fileURL.pathExtension.lowercased())

        if isVideo {
            print("   Extracting audio from video...")
            audioURL = try await extractAudio(from: fileURL)
        } else {
            audioURL = fileURL
        }

        defer {
            // Clean up extracted audio
            if isVideo {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }

        // Transcribe using Whisper
        print("   Transcribing with Whisper...")
        let result = try await whisperService.transcribe(
            audioURL: audioURL,
            model: model,
            language: language
        )

        // Build transcript data
        let transcriptData = TranscriptData(
            text: result.text,
            language: result.language ?? "unknown",
            duration: result.duration,
            segments: result.segments?.map { segment in
                TranscriptData.Segment(
                    id: segment.id,
                    start: segment.start,
                    end: segment.end,
                    text: segment.text
                )
            },
            sourceFile: fileURL.lastPathComponent,
            generatedAt: Date()
        )

        print("✅ [VideoTranscriptService] Transcription complete!")
        print("   Text length: \(result.text.count) characters")
        print("   Segments: \(result.segments?.count ?? 0)")

        return transcriptData
    }

    /// Generate transcript and save to JSON file
    func generateAndSave(
        fileURL: URL,
        outputURL: URL,
        model: MLXModelConfig.WhisperModel? = nil,
        language: String? = nil
    ) async throws {
        let transcriptData = try await generateTranscript(
            fileURL: fileURL,
            model: model,
            language: language
        )

        // Save as formatted JSON
        let jsonData = try transcriptData.toFormattedJSON()
        try jsonData.write(to: outputURL)

        print("💾 Transcript saved to: \(outputURL.lastPathComponent)")
    }

    // MARK: - Audio Extraction

    /// Extract audio from video file
    private func extractAudio(from videoURL: URL) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let asset = AVAsset(url: videoURL)

        // Get audio track
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw VideoTranscriptError.noAudioTrack
        }

        // Create export session with a compatible preset
        // Use AppleM4A preset which is compatible with m4a output
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw VideoTranscriptError.exportFailed("Could not create export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        // Export audio
        await exportSession.export()

        guard exportSession.status == .completed else {
            let error = exportSession.error?.localizedDescription ?? "Unknown error"
            throw VideoTranscriptError.exportFailed(error)
        }

        return outputURL
    }
}

// MARK: - Supporting Types

struct TranscriptData: Codable {
    let text: String
    let language: String
    let duration: Double?
    let segments: [Segment]?
    let sourceFile: String
    let generatedAt: Date

    struct Segment: Codable {
        let id: Int
        let start: Double
        let end: Double
        let text: String
    }

    /// Convert to formatted JSON string
    func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Convert to formatted JSON data
    func toFormattedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

// MARK: - Errors

enum VideoTranscriptError: Error, LocalizedError {
    case fileNotFound(String)
    case noAudioTrack
    case exportFailed(String)
    case transcriptionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .noAudioTrack:
            return "Video has no audio track"
        case .exportFailed(let reason):
            return "Audio export failed: \(reason)"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        }
    }
}
