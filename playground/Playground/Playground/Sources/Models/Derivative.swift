import Foundation
import GRDB

/// Status of a derivative
enum DerivativeStatus: String, Codable {
    case pending = "pending"
    case complete = "complete"
    case failed = "failed"
}

/// Derivative model - tracks generated file derivatives
struct Derivative: Codable, Identifiable {
    var id: String
    var fileId: String
    var type: String
    var status: DerivativeStatus
    var outputPath: String?
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(id: String = UUID().uuidString,
         fileId: String,
         type: String,
         status: DerivativeStatus = .pending,
         outputPath: String? = nil,
         errorMessage: String? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         completedAt: Date? = nil) {
        self.id = id
        self.fileId = fileId
        self.type = type
        self.status = status
        self.outputPath = outputPath
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

// GRDB conformance
extension Derivative: FetchableRecord, PersistableRecord {
    static let databaseTableName = "derivatives"

    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    enum Columns {
        static let id = Column("id")
        static let fileId = Column("file_id")
        static let type = Column("type")
        static let status = Column("status")
        static let outputPath = Column("output_path")
        static let errorMessage = Column("error_message")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
        static let completedAt = Column("completed_at")
    }
}

// Computed properties
extension Derivative {
    /// Icon based on derivative type
    var icon: String {
        switch type {
        case "transcript":
            return "text.bubble"
        case "summary":
            return "doc.text"
        case "thumbnail":
            return "photo"
        default:
            return "doc.fill"
        }
    }

    /// Display name based on type
    var displayName: String {
        switch type {
        case "transcript":
            return "Transcript"
        case "summary":
            return "Summary"
        case "thumbnail":
            return "Thumbnail"
        default:
            return type.capitalized
        }
    }

    /// Status icon for UI
    var statusIcon: String {
        switch status {
        case .pending:
            return "clock"
        case .complete:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    /// Status color for UI
    var statusColor: String {
        switch status {
        case .pending:
            return "orange"
        case .complete:
            return "green"
        case .failed:
            return "red"
        }
    }
}
