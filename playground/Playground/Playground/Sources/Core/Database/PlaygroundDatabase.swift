import Foundation
import GRDB

/// Main database for the Playground app
/// Manages SQLite connection and schema migrations
class PlaygroundDatabase {
    static let shared = PlaygroundDatabase()

    private var dbQueue: DatabaseQueue?

    private init() {
        do {
            let dbPath = try getDatabasePath()
            dbQueue = try DatabaseQueue(path: dbPath)
            try migrate()
            print("✅ Database initialized at: \(dbPath)")
        } catch {
            print("❌ Database initialization failed: \(error)")
        }
    }

    /// Get database queue for queries
    var queue: DatabaseQueue {
        guard let queue = dbQueue else {
            fatalError("Database not initialized")
        }
        return queue
    }

    // MARK: - Database Path

    private func getDatabasePath() throws -> String {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let dbDir = appSupport.appendingPathComponent("Playground", isDirectory: true)
        try fileManager.createDirectory(at: dbDir, withIntermediateDirectories: true)

        return dbDir.appendingPathComponent("playground.db").path
    }

    // MARK: - Migrations

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        // Migration v1: Core tables
        migrator.registerMigration("v1_core_tables") { db in
            // App Bus Events
            try db.create(table: "app_bus_events") { t in
                t.column("id", .text).primaryKey()
                t.column("type", .text).notNull().indexed()
                t.column("app_id", .text).indexed()
                t.column("payload", .text) // JSON
                t.column("timestamp", .datetime).notNull().indexed()
            }

            // Chats
            try db.create(table: "chats") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("deleted_at", .datetime)
            }

            // Messages
            try db.create(table: "messages") { t in
                t.column("id", .text).primaryKey()
                t.column("chat_id", .text).notNull()
                    .indexed()
                    .references("chats", onDelete: .cascade)
                t.column("role", .text).notNull() // "user", "assistant", "system"
                t.column("content", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("deleted_at", .datetime)
            }

            // Vocabulary Words (simple version, no spaced repetition)
            try db.create(table: "vocabulary_words") { t in
                t.column("id", .text).primaryKey()
                t.column("word", .text).notNull()
                t.column("meaning", .text).notNull()
                t.column("sample_phrases", .text).notNull() // JSON array
                t.column("word_audio_path", .text)
                t.column("sample_audio_paths", .text).notNull() // JSON array
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            // Files
            try db.create(table: "files") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("path", .text).notNull()
                t.column("mime_type", .text)
                t.column("size_bytes", .integer)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("deleted_at", .datetime)
            }
        }

        // Migration v2: LMS tables (courses, modules, activities)
        migrator.registerMigration("v2_lms_tables") { db in
            // Courses
            try db.create(table: "lms_courses") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("deleted_at", .datetime)
            }

            // Modules
            try db.create(table: "lms_modules") { t in
                t.column("id", .text).primaryKey()
                t.column("course_id", .text).notNull()
                    .indexed()
                    .references("lms_courses", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("order_index", .integer).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("deleted_at", .datetime)
            }

            // Activities
            try db.create(table: "lms_activities") { t in
                t.column("id", .text).primaryKey()
                t.column("module_id", .text).notNull()
                    .indexed()
                    .references("lms_modules", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("type", .text).notNull() // "text", "video", "quiz", "audio"
                t.column("content", .text) // JSON
                t.column("order_index", .integer).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("deleted_at", .datetime)
            }

            // Quizzes
            try db.create(table: "quizzes") { t in
                t.column("id", .text).primaryKey()
                t.column("activity_id", .text).notNull()
                    .indexed()
                    .references("lms_activities", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("questions", .text).notNull() // JSON array
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
        }

        // Migration v3: Add extracted_text column to files table
        migrator.registerMigration("v3_files_extracted_text") { db in
            try db.alter(table: "files") { t in
                t.add(column: "extracted_text", .text)
            }
        }

        // Migration v4: Remove spaced repetition, simplify to match Dart
        // Just drop and recreate - simple and clean
        migrator.registerMigration("v4_remove_spaced_repetition") { db in
            print("🗑️ Dropping old vocabulary tables...")

            // Drop everything and start fresh
            try db.execute(sql: "DROP TABLE IF EXISTS review_schedules")
            try db.execute(sql: "DROP TABLE IF EXISTS vocabulary_words")

            // Create new simple schema
            try db.execute(sql: """
                CREATE TABLE vocabulary_words (
                    id TEXT PRIMARY KEY,
                    word TEXT NOT NULL,
                    meaning TEXT NOT NULL DEFAULT '',
                    sample_phrases TEXT NOT NULL DEFAULT '[]',
                    word_audio_path TEXT,
                    sample_audio_paths TEXT NOT NULL DEFAULT '[]',
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL
                )
                """)

            print("✅ Created new vocabulary_words table")
        }

        // Migration v5: Queue Service tables
        migrator.registerMigration("v5_queue_service") { db in
            print("📦 Creating queue service tables...")

            // Queue messages table
            try db.create(table: "queue_messages") { t in
                t.column("id", .text).primaryKey()
                t.column("queueId", .text).notNull().indexed()
                t.column("eventType", .text).notNull().indexed()
                t.column("appId", .text).notNull()
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("payload", .text)
                t.column("deliveryCount", .integer).notNull().defaults(to: 0)
                t.column("lastDeliveredAt", .datetime)
                t.column("lockedBy", .text).indexed()
                t.column("lockExpiresAt", .datetime).indexed()
                t.column("visibleAfter", .datetime).indexed()
            }

            // Dead Letter Queue table
            try db.create(table: "dlq_messages") { t in
                t.column("id", .text).primaryKey()
                t.column("queueId", .text).notNull().indexed()
                t.column("eventType", .text).notNull()
                t.column("appId", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("payload", .text)
                t.column("deliveryCount", .integer).notNull().defaults(to: 0)
                t.column("lastDeliveredAt", .datetime)
                t.column("movedToDlqAt", .datetime).notNull().indexed()
                t.column("errorReason", .text)
            }

            print("✅ Created queue service tables")
        }

        // Migration v6: Logs table
        migrator.registerMigration("v6_logs") { db in
            print("📝 Creating logs table...")

            try db.create(table: "logs") { t in
                t.column("id", .text).primaryKey()
                t.column("appId", .text).notNull().indexed()
                t.column("appName", .text).notNull()
                t.column("message", .text).notNull()
                t.column("severity", .text).notNull().indexed()
                t.column("eventType", .text).notNull().indexed()
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("metadata", .text) // JSON
            }

            print("✅ Created logs table")
        }

        // Migration v7: Folders table and file hierarchy
        migrator.registerMigration("v7_folders_hierarchy") { db in
            print("📁 Creating folders table and updating files schema...")

            // Create folders table
            try db.create(table: "folders") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("path", .text).notNull().unique()
                t.column("parent_path", .text).notNull().indexed()
                t.column("created_at", .datetime).notNull()
                t.column("deleted_at", .datetime)
            }

            // Add folder-related columns to files table
            try db.alter(table: "files") { t in
                t.add(column: "relative_path", .text)
                t.add(column: "folder_path", .text)
                t.add(column: "is_favorite", .boolean).defaults(to: false)
                t.add(column: "content_hash", .text)
            }

            // Create index on folder_path for faster queries
            try db.create(index: "idx_files_folder_path", on: "files", columns: ["folder_path"])
            try db.create(index: "idx_files_is_favorite", on: "files", columns: ["is_favorite"])

            print("✅ Created folders table and updated files schema")
        }

        // Migration v8: Derivatives table
        migrator.registerMigration("v8_derivatives") { db in
            print("🔄 Creating derivatives table...")

            try db.create(table: "derivatives") { t in
                t.column("id", .text).primaryKey()
                t.column("file_id", .text).notNull()
                    .indexed()
                    .references("files", onDelete: .cascade)
                t.column("type", .text).notNull().indexed()
                t.column("status", .text).notNull().indexed()
                t.column("output_path", .text)
                t.column("error_message", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("completed_at", .datetime)
            }

            // Create composite index for efficient queries
            try db.create(index: "idx_derivatives_file_type", on: "derivatives", columns: ["file_id", "type"])

            print("✅ Created derivatives table")
        }

        try migrator.migrate(queue)
    }

    // MARK: - Helpers

    /// Execute a database operation
    func execute<T>(_ operation: (Database) throws -> T) throws -> T {
        return try queue.write(operation)
    }

    /// Execute a read operation
    func read<T>(_ operation: (Database) throws -> T) throws -> T {
        return try queue.read(operation)
    }

    /// Execute an async database operation
    func execute<T>(_ operation: @escaping (Database) throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let result = try queue.write(operation)
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Execute an async read operation
    func read<T>(_ operation: @escaping (Database) throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let result = try queue.read(operation)
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
