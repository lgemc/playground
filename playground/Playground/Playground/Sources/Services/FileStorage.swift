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
                   folderPath: String = "",
                   mimeType: String? = nil,
                   sizeBytes: Int64? = nil,
                   extractedText: String? = nil) -> Result<File, Error> {
        return Result {
            // Calculate relative path
            let relativePath = folderPath.isEmpty ? name : "\(folderPath)\(name)"

            let file = File(
                name: name,
                path: path,
                relativePath: relativePath,
                folderPath: folderPath,
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
            // Get file info before deletion to access the file path
            let fileToDelete = try database.read { db in
                try File.fetchOne(db, key: id)
            }

            if soft {
                try database.execute { db in
                    try db.execute(
                        sql: "UPDATE files SET deleted_at = ? WHERE id = ?",
                        arguments: [Date(), id]
                    )
                }
            } else {
                // For hard delete, also remove the physical file
                if let file = fileToDelete {
                    let fileURL = URL(fileURLWithPath: file.path)
                    if FileManager.default.fileExists(atPath: file.path) {
                        try FileManager.default.removeItem(at: fileURL)
                        print("✅ Deleted file from disk: \(file.path)")
                    }
                }

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

    // MARK: - Folder Operations

    /// Create a new folder in the virtual drive
    func createFolder(name: String, parentPath: String = "") -> Result<Folder, Error> {
        return Result {
            let folderPath = parentPath.isEmpty ? "\(name)/" : "\(parentPath)\(name)/"

            let folder = Folder(
                name: name,
                path: folderPath,
                parentPath: parentPath
            )

            try database.execute { db in
                try folder.insert(db)
            }

            // Emit event
            AppBus.shared.emit(
                type: "folder.created",
                appId: "fileSystem",
                payload: [
                    "folderId": folder.id,
                    "name": folder.name,
                    "path": folder.path
                ]
            )

            return folder
        }
    }

    /// Get all folders in a specific path
    func getFoldersInPath(parentPath: String = "") -> Result<[Folder], Error> {
        return Result {
            try database.read { db in
                try Folder
                    .filter(Folder.Columns.parentPath == parentPath)
                    .filter(Folder.Columns.deletedAt == nil)
                    .order(Folder.Columns.name.collating(.nocase))
                    .fetchAll(db)
            }
        }
    }

    /// Get all files in a specific folder
    func getFilesInFolder(folderPath: String = "") -> Result<[File], Error> {
        return Result {
            try database.read { db in
                try File
                    .filter(File.Columns.folderPath == folderPath)
                    .filter(File.Columns.deletedAt == nil)
                    .order(File.Columns.name.collating(.nocase))
                    .fetchAll(db)
            }
        }
    }

    /// Rename a folder
    func renameFolder(id: String, newName: String) -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                guard let folder = try Folder.fetchOne(db, key: id) else {
                    throw FileStorageError.fileNotFound
                }

                // Calculate new path
                let pathComponents = folder.path.split(separator: "/").map(String.init)
                var newComponents = pathComponents
                if !newComponents.isEmpty {
                    newComponents[newComponents.count - 1] = newName
                }
                let newPath = newComponents.joined(separator: "/") + "/"

                // Calculate parent path
                let parentComponents = newComponents.dropLast()
                let parentPath = parentComponents.isEmpty ? "" : parentComponents.joined(separator: "/") + "/"

                // Update folder
                var updatedFolder = folder
                updatedFolder.name = newName
                updatedFolder.path = newPath
                updatedFolder.parentPath = parentPath
                try updatedFolder.update(db)

                // Update all files in this folder and subfolders
                let files = try File
                    .filter(File.Columns.folderPath.like("\(folder.path)%") || File.Columns.folderPath == folder.path)
                    .fetchAll(db)

                for var file in files {
                    let newFolderPath = file.folderPath?.replacingOccurrences(of: folder.path, with: newPath) ?? ""
                    let newRelativePath = newFolderPath.isEmpty ? file.name : "\(newFolderPath)\(file.name)"

                    file.folderPath = newFolderPath
                    file.relativePath = newRelativePath
                    file.updatedAt = Date()
                    try file.update(db)
                }

                // Update all subfolders
                let subfolders = try Folder
                    .filter(Folder.Columns.path.like("\(folder.path)%"))
                    .filter(Folder.Columns.path != folder.path)
                    .fetchAll(db)

                for var subfolder in subfolders {
                    let newSubfolderPath = subfolder.path.replacingOccurrences(of: folder.path, with: newPath)
                    let newSubfolderParentPath = subfolder.parentPath.replacingOccurrences(of: folder.path, with: newPath)

                    subfolder.path = newSubfolderPath
                    subfolder.parentPath = newSubfolderParentPath
                    try subfolder.update(db)
                }

                // Emit event
                AppBus.shared.emit(
                    type: "folder.renamed",
                    appId: "fileSystem",
                    payload: [
                        "folderId": id,
                        "oldPath": folder.path,
                        "newPath": newPath
                    ]
                )
            }
        }
    }

    /// Delete a folder (must be empty)
    func deleteFolder(id: String, soft: Bool = true) -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                guard let folder = try Folder.fetchOne(db, key: id) else {
                    throw FileStorageError.fileNotFound
                }

                // Check if folder has any non-deleted files
                let fileCount = try File
                    .filter(File.Columns.folderPath == folder.path)
                    .filter(File.Columns.deletedAt == nil)
                    .fetchCount(db)

                if fileCount > 0 {
                    throw FileStorageError.folderNotEmpty
                }

                // Check if folder has any non-deleted subfolders
                let subfolderCount = try Folder
                    .filter(Folder.Columns.parentPath == folder.path)
                    .filter(Folder.Columns.deletedAt == nil)
                    .fetchCount(db)

                if subfolderCount > 0 {
                    throw FileStorageError.folderNotEmpty
                }

                if soft {
                    // Soft delete
                    var updatedFolder = folder
                    updatedFolder.deletedAt = Date()
                    try updatedFolder.update(db)
                } else {
                    // Hard delete
                    _ = try Folder.deleteOne(db, key: id)
                }

                // Emit event
                AppBus.shared.emit(
                    type: "folder.deleted",
                    appId: "fileSystem",
                    payload: [
                        "folderId": id,
                        "path": folder.path,
                        "soft": soft
                    ]
                )
            }
        }
    }

    /// Toggle favorite status for a file
    func toggleFavorite(id: String) -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                guard var file = try File.fetchOne(db, key: id) else {
                    throw FileStorageError.fileNotFound
                }

                file.isFavorite = !file.isFavorite
                file.updatedAt = Date()
                try file.update(db)

                // Emit event
                AppBus.shared.emit(
                    type: "file.favoriteToggled",
                    appId: "fileSystem",
                    payload: [
                        "fileId": id,
                        "isFavorite": file.isFavorite
                    ]
                )
            }
        }
    }

    /// Get all favorite files
    func getFavorites() -> Result<[File], Error> {
        return Result {
            try database.read { db in
                try File
                    .filter(File.Columns.isFavorite == true)
                    .filter(File.Columns.deletedAt == nil)
                    .order(File.Columns.name.collating(.nocase))
                    .fetchAll(db)
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
    case folderNotEmpty
}
