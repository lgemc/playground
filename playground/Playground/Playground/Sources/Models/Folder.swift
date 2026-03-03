import Foundation
import GRDB

/// Folder model for organizing files in a hierarchical structure
struct Folder: Codable, Identifiable {
    var id: String
    var name: String
    var path: String
    var parentPath: String
    var createdAt: Date
    var deletedAt: Date?

    init(id: String = UUID().uuidString,
         name: String,
         path: String,
         parentPath: String,
         createdAt: Date = Date(),
         deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.parentPath = parentPath
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}

// GRDB conformance
extension Folder: FetchableRecord, PersistableRecord {
    static let databaseTableName = "folders"

    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let path = Column("path")
        static let parentPath = Column("parent_path")
        static let createdAt = Column("created_at")
        static let deletedAt = Column("deleted_at")
    }
}

// Computed properties
extension Folder {
    /// Check if this is a root folder (no parent)
    var isRoot: Bool {
        return parentPath.isEmpty
    }

    /// Get the depth level of this folder (0 for root, 1 for first level, etc.)
    var depth: Int {
        if parentPath.isEmpty { return 0 }
        return parentPath.split(separator: "/").count
    }

    /// Get the display name with indentation based on depth
    func displayName(withIndentation: Bool = true) -> String {
        if withIndentation {
            let indent = String(repeating: "  ", count: depth)
            return "\(indent)\(name)"
        }
        return name
    }
}
