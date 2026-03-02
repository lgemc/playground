import Foundation
import GRDB

/// Chat conversation model
struct Chat: Codable, Identifiable {
    var id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(id: String = UUID().uuidString,
         title: String = "New Chat",
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         deletedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

// GRDB conformance
extension Chat: FetchableRecord, PersistableRecord {
    static let databaseTableName = "chats"

    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    enum Columns {
        static let id = Column("id")
        static let title = Column("title")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
        static let deletedAt = Column("deleted_at")
    }
}

/// Chat message model
struct Message: Codable, Identifiable {
    var id: String
    var chatId: String
    var role: Role
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    init(id: String = UUID().uuidString,
         chatId: String,
         role: Role,
         content: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         deletedAt: Date? = nil) {
        self.id = id
        self.chatId = chatId
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

// GRDB conformance
extension Message: FetchableRecord, PersistableRecord {
    static let databaseTableName = "messages"

    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    enum Columns {
        static let id = Column("id")
        static let chatId = Column("chat_id")
        static let role = Column("role")
        static let content = Column("content")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
        static let deletedAt = Column("deleted_at")
    }
}
