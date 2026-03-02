import Foundation
import GRDB

/// Storage service for file management
class FileStorage {
    static let shared = FileStorage()
    private let database = PlaygroundDatabase.shared

    private init() {}

    // MARK: - File CRUD

    func createFile(name: String,
                   path: String,
                   mimeType: String? = nil,
                   sizeBytes: Int64? = nil,
                   extractedText: String? = nil) -> Result<File, Error> {
        return Result {
            let file = File(
                name: name,
                path: path,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                extractedText: extractedText
            )

            try database.execute { db in
                try file.insert(db)
            }

            // Emit event
            AppBus.shared.emit(
                type: "file.created",
                appId: "fileSystem",
                payload: [
                    "fileId": file.id,
                    "name": file.name,
                    "mimeType": file.mimeType ?? "unknown"
                ]
            )

            return file
        }
    }

    func getFile(id: String) -> Result<File?, Error> {
        return Result {
            try database.read { db in
                try File.fetchOne(db, key: id)
            }
        }
    }

    func getAllFiles(includeDeleted: Bool = false) -> Result<[File], Error> {
        return Result {
            try database.read { db in
                var query = File.order(File.Columns.createdAt.desc)
                if !includeDeleted {
                    query = query.filter(File.Columns.deletedAt == nil)
                }
                return try query.fetchAll(db)
            }
        }
    }

    func updateFile(id: String,
                   name: String? = nil,
                   path: String? = nil,
                   extractedText: String? = nil) -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                if let existingFile = try File.fetchOne(db, key: id) {
                    var updatedFile = existingFile
                    if let name = name { updatedFile.name = name }
                    if let path = path { updatedFile.path = path }
                    if let extractedText = extractedText { updatedFile.extractedText = extractedText }
                    updatedFile.updatedAt = Date()

                    try updatedFile.update(db)

                    // Emit event
                    AppBus.shared.emit(
                        type: "file.updated",
                        appId: "fileSystem",
                        payload: [
                            "fileId": id,
                            "name": updatedFile.name
                        ]
                    )
                }
            }
        }
    }

    func deleteFile(id: String, soft: Bool = true) -> Result<Void, Error> {
        return Result {
            if soft {
                try database.execute { db in
                    try db.execute(
                        sql: "UPDATE files SET deleted_at = ? WHERE id = ?",
                        arguments: [Date(), id]
                    )
                }
            } else {
                try database.execute { db in
                    _ = try File.deleteOne(db, key: id)
                }
            }

            // Emit event
            AppBus.shared.emit(
                type: "file.deleted",
                appId: "fileSystem",
                payload: [
                    "fileId": id,
                    "soft": soft
                ]
            )
        }
    }

    // MARK: - Search

    func searchFiles(query: String, limit: Int = 50) -> Result<[File], Error> {
        return Result {
            try database.read { db in
                try File
                    .filter(
                        File.Columns.name.like("%\(query)%") ||
                        File.Columns.extractedText.like("%\(query)%")
                    )
                    .filter(File.Columns.deletedAt == nil)
                    .order(File.Columns.createdAt.desc)
                    .limit(limit)
                    .fetchAll(db)
            }
        }
    }

    // MARK: - File Type Queries

    func getFilesByType(mimeType: String) -> Result<[File], Error> {
        return Result {
            try database.read { db in
                try File
                    .filter(File.Columns.mimeType == mimeType)
                    .filter(File.Columns.deletedAt == nil)
                    .order(File.Columns.createdAt.desc)
                    .fetchAll(db)
            }
        }
    }

    func getFilesByExtension(extension: String) -> Result<[File], Error> {
        return Result {
            try database.read { db in
                try File
                    .filter(File.Columns.name.like("%.\(`extension`)"))
                    .filter(File.Columns.deletedAt == nil)
                    .order(File.Columns.createdAt.desc)
                    .fetchAll(db)
            }
        }
    }

    // MARK: - Statistics

    func getStatistics() -> Result<FileStatistics, Error> {
        return Result {
            try database.read { db in
                let totalFiles = try File
                    .filter(File.Columns.deletedAt == nil)
                    .fetchCount(db)

                let totalSizeResult = try Row.fetchOne(db,
                    sql: "SELECT SUM(size_bytes) as total FROM files WHERE deleted_at IS NULL")
                let totalSize = totalSizeResult?["total"] as? Int64 ?? 0

                let filesWithText = try File
                    .filter(File.Columns.deletedAt == nil)
                    .filter(File.Columns.extractedText != nil)
                    .fetchCount(db)

                return FileStatistics(
                    totalFiles: totalFiles,
                    totalSizeBytes: totalSize,
                    filesWithExtractedText: filesWithText
                )
            }
        }
    }
}

// MARK: - Supporting Types

struct FileStatistics {
    let totalFiles: Int
    let totalSizeBytes: Int64
    let filesWithExtractedText: Int

    var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSizeBytes)
    }
}

enum FileStorageError: Error {
    case fileNotFound
    case invalidPath
    case extractionFailed
}
