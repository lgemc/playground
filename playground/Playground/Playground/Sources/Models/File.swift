import Foundation
import GRDB

/// File model for document management
struct File: Codable, Identifiable {
    var id: String
    var name: String
    var path: String
    var relativePath: String?
    var folderPath: String?
    var mimeType: String?
    var sizeBytes: Int64?
    var isFavorite: Bool
    var extractedText: String?
    var contentHash: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(id: String = UUID().uuidString,
         name: String,
         path: String,
         relativePath: String? = nil,
         folderPath: String? = nil,
         mimeType: String? = nil,
         sizeBytes: Int64? = nil,
         isFavorite: Bool = false,
         extractedText: String? = nil,
         contentHash: String? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.relativePath = relativePath
        self.folderPath = folderPath
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.isFavorite = isFavorite
        self.extractedText = extractedText
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

// GRDB conformance
extension File: FetchableRecord, PersistableRecord {
    static let databaseTableName = "files"

    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let path = Column("path")
        static let relativePath = Column("relative_path")
        static let folderPath = Column("folder_path")
        static let mimeType = Column("mime_type")
        static let sizeBytes = Column("size_bytes")
        static let isFavorite = Column("is_favorite")
        static let extractedText = Column("extracted_text")
        static let contentHash = Column("content_hash")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
        static let deletedAt = Column("deleted_at")
    }
}

// Computed properties
extension File {
    /// Human-readable file size
    var formattedSize: String {
        guard let bytes = sizeBytes else { return "Unknown" }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// File extension (e.g., "pdf", "txt")
    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    /// Icon name based on file type
    var iconName: String {
        switch fileExtension {
        case "pdf":
            return "doc.fill"
        case "txt", "md", "markdown":
            return "doc.text.fill"
        case "jpg", "jpeg", "png", "gif", "heic":
            return "photo.fill"
        case "mp3", "wav", "m4a":
            return "waveform"
        case "mp4", "mov", "avi":
            return "video.fill"
        case "zip", "tar", "gz":
            return "doc.zipper"
        default:
            return "doc.fill"
        }
    }
}
