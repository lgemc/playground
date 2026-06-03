import Foundation
import SQLite3

// MARK: - Model Registry Entry

struct RegisteredModel: Identifiable {
    let id: String
    let modelId: String  // HuggingFace repo ID
    let type: ModelType
    let name: String
    var sizeMB: Int?
    var isDownloaded: Bool
    var downloadProgress: Double?
    var downloadStartedAt: Date?
    var downloadCompletedAt: Date?
    var lastUsedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    enum ModelType: String {
        case chat
        case whisper
        case tts
        case image
        case flux
    }
}

// MARK: - Model Registry Service

actor ModelRegistry {
    static let shared = ModelRegistry()

    private var db: OpaquePointer?
    private var isInitialized = false
    private let dbQueue = DispatchQueue(label: "com.playground.modelregistry", qos: .userInitiated)

    private init() {
        // Don't initialize in init - let first caller trigger it
    }

    // MARK: - Database Initialization

    private func ensureInitialized() async throws {
        guard !isInitialized else { return }
        try await initializeDatabase()
        isInitialized = true
    }

    private func initializeDatabase() async throws {
        let dbPath = try getDatabasePath()

        // Open database
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw NSError(domain: "ModelRegistry", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to open database"])
        }

        // Create table
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS mlx_models (
            id TEXT PRIMARY KEY,
            model_id TEXT NOT NULL,
            type TEXT NOT NULL,
            name TEXT NOT NULL,
            size_mb INTEGER,
            is_downloaded INTEGER DEFAULT 0,
            download_progress REAL,
            download_started_at TEXT,
            download_completed_at TEXT,
            last_used_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """

        guard sqlite3_exec(db, createTableSQL, nil, nil, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            throw NSError(domain: "ModelRegistry", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create table: \(errmsg)"])
        }

        // Drop old non-unique index if it exists and create unique one
        sqlite3_exec(db, "DROP INDEX IF EXISTS idx_model_id", nil, nil, nil)

        // Try to create unique index - if it fails due to duplicates, clean them up
        let createIndexSQL = "CREATE UNIQUE INDEX idx_model_id ON mlx_models(model_id)"
        if sqlite3_exec(db, createIndexSQL, nil, nil, nil) != SQLITE_OK {
            // Index creation failed - likely due to duplicate model_ids
            // Clean up duplicates by keeping only the first entry for each model_id
            print("⚠️ Cleaning up duplicate model_id entries...")
            let cleanupSQL = """
            DELETE FROM mlx_models
            WHERE rowid NOT IN (
                SELECT MIN(rowid)
                FROM mlx_models
                GROUP BY model_id
            )
            """
            sqlite3_exec(db, cleanupSQL, nil, nil, nil)

            // Try creating unique index again
            if sqlite3_exec(db, createIndexSQL, nil, nil, nil) != SQLITE_OK {
                let errmsg = String(cString: sqlite3_errmsg(db)!)
                throw NSError(domain: "ModelRegistry", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create unique index: \(errmsg)"])
            }
        }

        print("ModelRegistry: Database initialized at \(dbPath)")
    }

    private func getDatabasePath() throws -> String {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw NSError(domain: "ModelRegistry", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not find application support directory"])
        }

        let dbDir = appSupport.appendingPathComponent("Playground", isDirectory: true)
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        return dbDir.appendingPathComponent("model_registry.db").path
    }

    // MARK: - Public API

    func registerModel(
        id: String,
        modelId: String,
        type: RegisteredModel.ModelType,
        name: String,
        sizeMB: Int? = nil
    ) async throws {
        try await ensureInitialized()

        let now = ISO8601DateFormatter().string(from: Date())

        // Use INSERT with ON CONFLICT to preserve is_downloaded
        // COALESCE keeps existing is_downloaded value, defaults to 0 for new rows
        let sql = """
        INSERT INTO mlx_models (id, model_id, type, name, size_mb, is_downloaded, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, 0, ?, ?)
        ON CONFLICT(model_id) DO UPDATE SET
            name = excluded.name,
            size_mb = excluded.size_mb,
            type = excluded.type,
            updated_at = excluded.updated_at
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            throw NSError(domain: "ModelRegistry", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare: \(errmsg)"])
        }

        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, nil)
        sqlite3_bind_text(stmt, 2, modelId, -1, nil)
        sqlite3_bind_text(stmt, 3, type.rawValue, -1, nil)
        sqlite3_bind_text(stmt, 4, name, -1, nil)
        if let sizeMB = sizeMB {
            sqlite3_bind_int(stmt, 5, Int32(sizeMB))
        }
        sqlite3_bind_text(stmt, 6, now, -1, nil)
        sqlite3_bind_text(stmt, 7, now, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            throw NSError(domain: "ModelRegistry", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to execute: \(errmsg)"])
        }
    }

    func markAsDownloaded(modelId: String, sizeMB: Int) async throws {
        try await ensureInitialized()

        let now = ISO8601DateFormatter().string(from: Date())

        let sql = """
        UPDATE mlx_models
        SET is_downloaded = 1,
            size_mb = ?,
            download_completed_at = ?,
            download_progress = 1.0,
            updated_at = ?
        WHERE model_id = ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            throw NSError(domain: "ModelRegistry", code: 1, userInfo: [NSLocalizedDescriptionKey: errmsg])
        }

        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(sizeMB))
        sqlite3_bind_text(stmt, 2, now, -1, nil)
        sqlite3_bind_text(stmt, 3, now, -1, nil)
        sqlite3_bind_text(stmt, 4, modelId, -1, nil)

        sqlite3_step(stmt)
    }

    func updateLastUsed(modelId: String) async throws {
        try await ensureInitialized()

        let now = ISO8601DateFormatter().string(from: Date())

        let sql = "UPDATE mlx_models SET last_used_at = ?, updated_at = ? WHERE model_id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }

        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, now, -1, nil)
        sqlite3_bind_text(stmt, 2, now, -1, nil)
        sqlite3_bind_text(stmt, 3, modelId, -1, nil)

        sqlite3_step(stmt)
    }

    func getAllModels() async throws -> [RegisteredModel] {
        try await ensureInitialized()

        var models: [RegisteredModel] = []

        let sql = "SELECT * FROM mlx_models ORDER BY last_used_at DESC, name ASC"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            throw NSError(domain: "ModelRegistry", code: 3, userInfo: [NSLocalizedDescriptionKey: errmsg])
        }

        defer { sqlite3_finalize(stmt) }

        let dateFormatter = ISO8601DateFormatter()

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let modelId = String(cString: sqlite3_column_text(stmt, 1))
            let typeString = String(cString: sqlite3_column_text(stmt, 2))
            let name = String(cString: sqlite3_column_text(stmt, 3))
            let sizeMB = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 4)) : nil
            let isDownloaded = sqlite3_column_int(stmt, 5) == 1
            let downloadProgress = sqlite3_column_type(stmt, 6) != SQLITE_NULL ? Double(sqlite3_column_double(stmt, 6)) : nil

            let downloadStartedAt: Date? = {
                guard sqlite3_column_type(stmt, 7) != SQLITE_NULL,
                      let text = sqlite3_column_text(stmt, 7) else { return nil }
                return dateFormatter.date(from: String(cString: text))
            }()

            let downloadCompletedAt: Date? = {
                guard sqlite3_column_type(stmt, 8) != SQLITE_NULL,
                      let text = sqlite3_column_text(stmt, 8) else { return nil }
                return dateFormatter.date(from: String(cString: text))
            }()

            let lastUsedAt: Date? = {
                guard sqlite3_column_type(stmt, 9) != SQLITE_NULL,
                      let text = sqlite3_column_text(stmt, 9) else { return nil }
                return dateFormatter.date(from: String(cString: text))
            }()

            let createdAt = dateFormatter.date(from: String(cString: sqlite3_column_text(stmt, 10))) ?? Date()
            let updatedAt = dateFormatter.date(from: String(cString: sqlite3_column_text(stmt, 11))) ?? Date()

            let model = RegisteredModel(
                id: id,
                modelId: modelId,
                type: RegisteredModel.ModelType(rawValue: typeString) ?? .chat,
                name: name,
                sizeMB: sizeMB,
                isDownloaded: isDownloaded,
                downloadProgress: downloadProgress,
                downloadStartedAt: downloadStartedAt,
                downloadCompletedAt: downloadCompletedAt,
                lastUsedAt: lastUsedAt,
                createdAt: createdAt,
                updatedAt: updatedAt
            )

            models.append(model)
        }

        return models
    }

    func getDownloadedModels() async throws -> [RegisteredModel] {
        let allModels = try await getAllModels()
        return allModels.filter { $0.isDownloaded }
    }

    func deleteModel(modelId: String) async throws {
        try await ensureInitialized()

        // Delete from database
        let sql = "DELETE FROM mlx_models WHERE model_id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            throw NSError(domain: "ModelRegistry", code: 4, userInfo: [NSLocalizedDescriptionKey: errmsg])
        }

        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, modelId, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let errmsg = String(cString: sqlite3_errmsg(db)!)
            throw NSError(domain: "ModelRegistry", code: 5, userInfo: [NSLocalizedDescriptionKey: errmsg])
        }

        // Attempt to delete model files from cache
        // Note: MLX Swift manages model cache internally, so this is best-effort
        try await deleteModelFiles(modelId: modelId)
    }

    private func deleteModelFiles(modelId: String) async throws {
        // Try to find and delete model files in common cache locations
        let fileManager = FileManager.default

        // Common HuggingFace cache locations on iOS
        let possibleCachePaths = [
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("huggingface")
                .appendingPathComponent("hub"),
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent(".cache")
                .appendingPathComponent("huggingface")
                .appendingPathComponent("hub")
        ].compactMap { $0 }

        for cachePath in possibleCachePaths {
            guard fileManager.fileExists(atPath: cachePath.path) else { continue }

            // Convert modelId to directory name format (e.g., "mlx-community/Qwen3-4B-4bit" -> "models--mlx-community--Qwen3-4B-4bit")
            let dirName = "models--" + modelId.replacingOccurrences(of: "/", with: "--")
            let modelPath = cachePath.appendingPathComponent(dirName)

            if fileManager.fileExists(atPath: modelPath.path) {
                try fileManager.removeItem(at: modelPath)
                print("Deleted model files at: \(modelPath.path)")
            }
        }
    }

    func getTotalSizeMB() async throws -> Int {
        let models = try await getDownloadedModels()
        return models.compactMap { $0.sizeMB }.reduce(0, +)
    }

    func getModelByModelId(modelId: String) async throws -> RegisteredModel? {
        try await ensureInitialized()

        let sql = "SELECT * FROM mlx_models WHERE model_id = ? LIMIT 1"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }

        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, modelId, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        let dateFormatter = ISO8601DateFormatter()

        let id = String(cString: sqlite3_column_text(stmt, 0))
        let modelId = String(cString: sqlite3_column_text(stmt, 1))
        let typeString = String(cString: sqlite3_column_text(stmt, 2))
        let name = String(cString: sqlite3_column_text(stmt, 3))
        let sizeMB = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 4)) : nil
        let isDownloaded = sqlite3_column_int(stmt, 5) == 1
        let downloadProgress = sqlite3_column_type(stmt, 6) != SQLITE_NULL ? Double(sqlite3_column_double(stmt, 6)) : nil

        let downloadStartedAt: Date? = {
            guard sqlite3_column_type(stmt, 7) != SQLITE_NULL,
                  let text = sqlite3_column_text(stmt, 7) else { return nil }
            return dateFormatter.date(from: String(cString: text))
        }()

        let downloadCompletedAt: Date? = {
            guard sqlite3_column_type(stmt, 8) != SQLITE_NULL,
                  let text = sqlite3_column_text(stmt, 8) else { return nil }
            return dateFormatter.date(from: String(cString: text))
        }()

        let lastUsedAt: Date? = {
            guard sqlite3_column_type(stmt, 9) != SQLITE_NULL,
                  let text = sqlite3_column_text(stmt, 9) else { return nil }
            return dateFormatter.date(from: String(cString: text))
        }()

        let createdAt = dateFormatter.date(from: String(cString: sqlite3_column_text(stmt, 10)))!
        let updatedAt = dateFormatter.date(from: String(cString: sqlite3_column_text(stmt, 11)))!

        return RegisteredModel(
            id: id,
            modelId: modelId,
            type: RegisteredModel.ModelType(rawValue: typeString) ?? .chat,
            name: name,
            sizeMB: sizeMB,
            isDownloaded: isDownloaded,
            downloadProgress: downloadProgress,
            downloadStartedAt: downloadStartedAt,
            downloadCompletedAt: downloadCompletedAt,
            lastUsedAt: lastUsedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
