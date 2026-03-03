import Foundation

/// Generates summary derivatives for files with text content using MLX
class SummaryDerivativeGenerator: DerivativeGenerator {
    private let mlxService = MLXService.shared
    private let logger: Logger

    // Supported file types for summarization
    private let supportedExtensions: Set<String> = [
        "txt", "md", "markdown",
        "json", "xml", "html", "htm",
        "log", "csv",
        "swift", "py", "js", "ts", "java", "cpp", "c", "h"
    ]

    init() {
        self.logger = Logger(appId: "file_system", appName: "File System")
    }

    // MARK: - DerivativeGenerator Protocol

    var type: String {
        return "summary"
    }

    var displayName: String {
        return "Text Summary"
    }

    var icon: String {
        return "text.alignleft"
    }

    func canProcess(file: FileItem) -> Bool {
        // Check if file has text content
        let fileURL = URL(fileURLWithPath: file.path)
        let ext = fileURL.pathExtension.lowercased()

        // Support files with extracted text or known text formats
        return supportedExtensions.contains(ext)
    }

    func generate(file: FileItem) async throws -> String {
        logger.info(
            "Starting summary generation for file: \(file.name)",
            eventType: "derivative.summary.start",
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
                eventType: "derivative.summary.error",
                metadata: ["file_id": file.id]
            )
            throw DerivativeGeneratorError.fileNotFound(file.path)
        }

        // Read file content
        let content: String
        do {
            let data = try Data(contentsOf: fileURL)
            if let text = String(data: data, encoding: .utf8) {
                content = text
            } else if let text = String(data: data, encoding: .ascii) {
                content = text
            } else {
                throw DerivativeGeneratorError.unsupportedFileType("Cannot decode text content")
            }
        } catch {
            logger.error(
                "Failed to read file content: \(error.localizedDescription)",
                eventType: "derivative.summary.error",
                metadata: ["file_id": file.id]
            )
            throw DerivativeGeneratorError.generationFailed("Cannot read file: \(error.localizedDescription)")
        }

        // Check if content is too short
        guard content.count > 50 else {
            throw DerivativeGeneratorError.generationFailed("Content too short to summarize")
        }

        // Truncate content if too long (MLX has token limits)
        let maxChars = 10000  // ~2500 tokens
        let truncatedContent = content.count > maxChars
            ? String(content.prefix(maxChars)) + "\n\n[Content truncated...]"
            : content

        do {
            // Generate summary using MLX
            let summary = try await generateSummary(content: truncatedContent, fileName: file.name)

            // Create output directory (derivatives/{file_id}/)
            let derivativesDir = getDerivativesDirectory(for: file.id)
            try FileManager.default.createDirectory(
                at: derivativesDir,
                withIntermediateDirectories: true
            )

            // Save summary as JSON
            let outputURL = derivativesDir.appendingPathComponent("summary.json")
            let summaryData = SummaryData(
                summary: summary,
                sourceFile: file.name,
                contentLength: content.count,
                wasTruncated: truncatedContent.count < content.count,
                generatedAt: Date()
            )

            let jsonData = try summaryData.toFormattedJSON()
            try jsonData.write(to: outputURL)

            logger.info(
                "Summary generated successfully",
                eventType: "derivative.summary.complete",
                metadata: [
                    "file_id": file.id,
                    "output_path": outputURL.path,
                    "summary_length": summary.count,
                    "content_length": content.count
                ]
            )

            // Return relative path
            return getRelativePath(for: outputURL)
        } catch {
            logger.error(
                "Summary generation failed: \(error.localizedDescription)",
                eventType: "derivative.summary.error",
                metadata: [
                    "file_id": file.id,
                    "error": error.localizedDescription
                ]
            )
            throw DerivativeGeneratorError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Summary Generation

    private func generateSummary(content: String, fileName: String) async throws -> String {
        let systemPrompt = """
        You are a document summarization assistant. Generate a concise, clear summary of the provided text.

        Guidelines:
        - Capture the main topics and key points
        - Use bullet points for clarity
        - Keep it under 200 words
        - Focus on factual information
        - Mention the document type if identifiable (e.g., code, log, article)

        Output only the summary. No preamble or conclusion.
        """

        let userPrompt = """
        File: \(fileName)

        Content:
        \(content)

        Please provide a summary of this document.
        """

        // Use MLX service with fallback to OpenAI
        let summary = try await mlxService.prompt(
            userPrompt,
            systemPrompt: systemPrompt,
            temperature: 0.3,
            maxTokens: 500
        )

        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - File Path Helpers

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

// MARK: - Supporting Types

struct SummaryData: Codable {
    let summary: String
    let sourceFile: String
    let contentLength: Int
    let wasTruncated: Bool
    let generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case summary
        case sourceFile = "source_file"
        case contentLength = "content_length"
        case wasTruncated = "was_truncated"
        case generatedAt = "generated_at"
    }

    func toFormattedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
