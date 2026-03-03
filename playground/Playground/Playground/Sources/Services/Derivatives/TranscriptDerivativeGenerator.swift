import Foundation

/// Generates transcript derivatives for video and audio files using MLX Whisper
class TranscriptDerivativeGenerator: DerivativeGenerator {
    private let transcriptService = VideoTranscriptService.shared
    private let logger: Logger

    init() {
        self.logger = Logger(appId: "file_system", appName: "File System")
    }

    // MARK: - DerivativeGenerator Protocol

    var type: String {
        return "transcript"
    }

    var displayName: String {
        return "Video Transcript"
    }

    var icon: String {
        return "text.bubble"
    }

    func canProcess(file: FileItem) -> Bool {
        let fileURL = URL(fileURLWithPath: file.path)
        return transcriptService.canProcess(fileURL: fileURL, mimeType: file.mimeType)
    }

    func generate(file: FileItem) async throws -> String {
        logger.info(
            "Starting transcript generation for file: \(file.name)",
            eventType: "derivative.transcript.start",
            metadata: [
                "file_id": file.id,
                "file_name": file.name,
                "file_size": file.size ?? 0
            ]
        )

        let fileURL = URL(fileURLWithPath: file.path)

        // Verify file exists
        guard FileManager.default.fileExists(atPath: file.path) else {
            logger.error(
                "File not found: \(file.path)",
                eventType: "derivative.transcript.error",
                metadata: ["file_id": file.id]
            )
            throw DerivativeGeneratorError.fileNotFound(file.path)
        }

        // Verify we can process this file type
        guard canProcess(file: file) else {
            logger.error(
                "Unsupported file type: \(file.mimeType ?? "unknown")",
                eventType: "derivative.transcript.error",
                metadata: ["file_id": file.id, "mime_type": file.mimeType ?? ""]
            )
            throw DerivativeGeneratorError.unsupportedFileType(file.mimeType ?? "unknown")
        }

        do {
            // Generate transcript
            let transcriptData = try await transcriptService.generateTranscript(fileURL: fileURL)

            // Create output directory (derivatives/{file_id}/)
            let derivativesDir = getDerivativesDirectory(for: file.id)
            try FileManager.default.createDirectory(
                at: derivativesDir,
                withIntermediateDirectories: true
            )

            // Save transcript JSON
            let outputURL = derivativesDir.appendingPathComponent("transcript.json")
            let jsonData = try transcriptData.toFormattedJSON()
            try jsonData.write(to: outputURL)

            logger.info(
                "Transcript generated successfully",
                eventType: "derivative.transcript.complete",
                metadata: [
                    "file_id": file.id,
                    "output_path": outputURL.path,
                    "text_length": transcriptData.text.count,
                    "segments": transcriptData.segments?.count ?? 0,
                    "language": transcriptData.language
                ]
            )

            // Return relative path
            return getRelativePath(for: outputURL)
        } catch {
            logger.error(
                "Transcript generation failed: \(error.localizedDescription)",
                eventType: "derivative.transcript.error",
                metadata: [
                    "file_id": file.id,
                    "error": error.localizedDescription
                ]
            )
            throw DerivativeGeneratorError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - File Path Helpers

    /// Get the derivatives directory for a file
    private func getDerivativesDirectory(for fileId: String) -> URL {
        guard let documentsDirectory = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            fatalError("Could not access documents directory")
        }

        return documentsDirectory
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("file_system", isDirectory: true)
            .appendingPathComponent("storage", isDirectory: true)
            .appendingPathComponent("derivatives", isDirectory: true)
            .appendingPathComponent(fileId, isDirectory: true)
    }

    /// Get relative path for storing in database (relative to data/file_system/storage)
    private func getRelativePath(for fileURL: URL) -> String {
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
}
