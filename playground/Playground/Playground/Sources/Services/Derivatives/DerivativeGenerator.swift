import Foundation

/// File metadata for derivative generation
struct FileItem {
    let id: String
    let path: String
    let name: String
    let mimeType: String?
    let size: Int64?
    let createdAt: Date
    let updatedAt: Date
}

/// Abstract protocol for generating derivatives from files
/// Matches the Dart DerivativeGenerator interface
protocol DerivativeGenerator {
    /// Unique identifier for this generator type (e.g., "transcript", "thumbnail")
    var type: String { get }

    /// Display name for UI
    var displayName: String { get }

    /// Icon name (SF Symbol)
    var icon: String { get }

    /// Check if this generator can process the given file
    func canProcess(file: FileItem) -> Bool

    /// Generate derivative and return the output file path
    /// Throws if generation fails
    func generate(file: FileItem) async throws -> String
}

/// Errors that can occur during derivative generation
enum DerivativeGeneratorError: Error, LocalizedError {
    case fileNotFound(String)
    case unsupportedFileType(String)
    case generationFailed(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .unsupportedFileType(let type):
            return "Unsupported file type: \(type)"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .invalidOutput(let reason):
            return "Invalid output: \(reason)"
        }
    }
}
