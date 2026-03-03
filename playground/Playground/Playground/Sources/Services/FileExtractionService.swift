import Foundation

/// Service for extracting text content from files
class FileExtractionService {
    static let shared = FileExtractionService()

    private init() {}

    /// Supported text-based file extensions
    private let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "xml", "html", "css", "js", "swift",
        "py", "java", "cpp", "c", "h", "rs", "go", "yaml", "yml", "toml",
        "sh", "bash", "zsh", "fish", "log", "conf", "ini", "csv"
    ]

    // MARK: - Extraction

    /// Extract text from a file at the given path
    func extractText(from filePath: String) throws -> String {
        let url = URL(fileURLWithPath: filePath)
        let fileExtension = url.pathExtension.lowercased()

        // Check if file is a supported text file
        guard textExtensions.contains(fileExtension) else {
            throw ExtractionError.unsupportedFileType
        }

        // Check if file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ExtractionError.fileNotFound
        }

        // Read file contents
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            return contents
        } catch {
            throw ExtractionError.readFailed(underlyingError: error)
        }
    }

    /// Extract text and update file in storage
    func extractAndUpdateFile(fileId: String) async throws {
        // Get file from storage
        let fileResult = FileStorage.shared.getFile(id: fileId)
        guard let file = try fileResult.get() else {
            throw ExtractionError.fileNotFound
        }

        // Extract text using absolute path
        let extractedText = try extractText(from: file.absolutePath)

        // Update file with extracted text
        let updateResult = FileStorage.shared.updateFile(id: fileId, extractedText: extractedText)
        try updateResult.get()

        print("✅ Extracted \(extractedText.count) characters from \(file.name)")
    }

    /// Check if a file type is supported for extraction
    func isSupported(fileExtension: String) -> Bool {
        return textExtensions.contains(fileExtension.lowercased())
    }

    /// Check if a file type is supported by MIME type
    func isSupported(mimeType: String) -> Bool {
        return mimeType.hasPrefix("text/") ||
               mimeType == "application/json" ||
               mimeType == "application/xml"
    }

    // MARK: - File Information

    /// Get basic file information
    func getFileInfo(at path: String) throws -> FileInfo {
        let url = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw ExtractionError.fileNotFound
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let size = attributes[.size] as? Int64 ?? 0
        let creationDate = attributes[.creationDate] as? Date ?? Date()
        let modificationDate = attributes[.modificationDate] as? Date ?? Date()

        return FileInfo(
            name: url.lastPathComponent,
            path: path,
            size: size,
            creationDate: creationDate,
            modificationDate: modificationDate,
            fileExtension: url.pathExtension
        )
    }
}

// MARK: - Supporting Types

struct FileInfo {
    let name: String
    let path: String
    let size: Int64
    let creationDate: Date
    let modificationDate: Date
    let fileExtension: String

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

enum ExtractionError: LocalizedError {
    case fileNotFound
    case unsupportedFileType
    case readFailed(underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File not found"
        case .unsupportedFileType:
            return "Unsupported file type for text extraction"
        case .readFailed(let error):
            return "Failed to read file: \(error.localizedDescription)"
        }
    }
}
