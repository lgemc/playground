import Foundation
import GRDB

/// Storage service for chats and messages
class ChatStorage {
    static let shared = ChatStorage()
    private let database = PlaygroundDatabase.shared

    private init() {}

    // MARK: - Chat CRUD

    func createChat(title: String = "New Chat") -> Result<Chat, Error> {
        return Result {
            let chat = Chat(title: title)
            try database.execute { db in
                try chat.insert(db)
            }
            return chat
        }
    }

    func getChat(id: String) -> Result<Chat?, Error> {
        return Result {
            try database.read { db in
                try Chat.fetchOne(db, key: id)
            }
        }
    }

    func getAllChats(includeDeleted: Bool = false) -> Result<[Chat], Error> {
        return Result {
            try database.read { db in
                var query = Chat.order(Chat.Columns.updatedAt.desc)
                if !includeDeleted {
                    query = query.filter(Chat.Columns.deletedAt == nil)
                }
                return try query.fetchAll(db)
            }
        }
    }

    func updateChat(id: String, title: String) -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                try db.execute(
                    sql: "UPDATE chats SET title = ?, updated_at = ? WHERE id = ?",
                    arguments: [title, Date(), id]
                )
            }
        }
    }

    func deleteChat(id: String, soft: Bool = true) -> Result<Void, Error> {
        return Result {
            if soft {
                try database.execute { db in
                    try db.execute(
                        sql: "UPDATE chats SET deleted_at = ? WHERE id = ?",
                        arguments: [Date(), id]
                    )
                }
            } else {
                try database.execute { db in
                    _ = try Chat.deleteOne(db, key: id)
                }
            }
        }
    }

    // MARK: - Message CRUD

    func createMessage(chatId: String, role: Message.Role, content: String) -> Result<Message, Error> {
        return Result {
            let message = Message(chatId: chatId, role: role, content: content)
            try database.execute { db in
                try message.insert(db)

                // Update chat's updatedAt timestamp
                try db.execute(
                    sql: "UPDATE chats SET updated_at = ? WHERE id = ?",
                    arguments: [Date(), chatId]
                )
            }
            return message
        }
    }

    func getMessages(chatId: String, includeDeleted: Bool = false) -> Result<[Message], Error> {
        return Result {
            try database.read { db in
                var query = Message
                    .filter(Message.Columns.chatId == chatId)
                    .order(Message.Columns.createdAt.asc)

                if !includeDeleted {
                    query = query.filter(Message.Columns.deletedAt == nil)
                }

                return try query.fetchAll(db)
            }
        }
    }

    func deleteMessage(id: String, soft: Bool = true) -> Result<Void, Error> {
        return Result {
            if soft {
                try database.execute { db in
                    try db.execute(
                        sql: "UPDATE messages SET deleted_at = ? WHERE id = ?",
                        arguments: [Date(), id]
                    )
                }
            } else {
                try database.execute { db in
                    _ = try Message.deleteOne(db, key: id)
                }
            }
        }
    }

    // MARK: - Search

    func searchMessages(query: String, limit: Int = 50) -> Result<[Message], Error> {
        return Result {
            try database.read { db in
                try Message
                    .filter(Message.Columns.content.like("%\(query)%"))
                    .filter(Message.Columns.deletedAt == nil)
                    .order(Message.Columns.createdAt.desc)
                    .limit(limit)
                    .fetchAll(db)
            }
        }
    }

    func searchChats(query: String, limit: Int = 50) -> Result<[Chat], Error> {
        return Result {
            try database.read { db in
                try Chat
                    .filter(Chat.Columns.title.like("%\(query)%"))
                    .filter(Chat.Columns.deletedAt == nil)
                    .order(Chat.Columns.updatedAt.desc)
                    .limit(limit)
                    .fetchAll(db)
            }
        }
    }
}
