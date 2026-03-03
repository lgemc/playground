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
            // Use the provided path as relativePath since AddFileView calculates it correctly
            // The path parameter from AddFileView includes "Files/" prefix
            let relativePath = path

            let file = File(
                name: name,
                path: path,
                relativePath: relativePath,
                folderPath: folderPath,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                extractedText: extractedText
            )

            // Debug logging
            print("💾 FileStorage.createFile:")
            print("   name: \(name)")
            print("   path: \(path)")
            print("   relativePath: \(relativePath)")
            print("   folderPath: \(folderPath)")

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
                    let absolutePath = file.absolutePath
                    let fileURL = URL(fileURLWithPath: absolutePath)
                    if FileManager.default.fileExists(atPath: absolutePath) {
                        try FileManager.default.removeItem(at: fileURL)
                        print("✅ Deleted file from disk: \(absolutePath)")
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

    // MARK: - Maintenance

    /// Clean up orphaned files (physical files that don't exist in database)
    /// and remove old Files directory if it exists
    func cleanupOrphanedFiles() -> Result<CleanupReport, Error> {
        return Result {
            var report = CleanupReport()
            let fileManager = FileManager.default
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

            // 1. Clean up OLD storage location (Documents/Files/)
            let oldStorageURL = documentsURL.appendingPathComponent("Files")
            if fileManager.fileExists(atPath: oldStorageURL.path) {
                print("🧹 Found old storage location: \(oldStorageURL.path)")
                do {
                    try fileManager.removeItem(at: oldStorageURL)
                    report.oldDirectoryRemoved = true
                    print("✅ Removed old Files directory")
                } catch {
                    print("⚠️ Failed to remove old Files directory: \(error)")
                    report.errors.append("Failed to remove old Files directory: \(error.localizedDescription)")
                }
            }

            // 2. Get all files from database
            let allFiles = try database.read { db in
                try File.filter(File.Columns.deletedAt == nil).fetchAll(db)
            }

            let databasePaths = Set(allFiles.compactMap { file -> String? in
                return file.absolutePath
            })

            print("📊 Database has \(databasePaths.count) files")

            // 3. Scan physical storage directory
            let storageDirectory = documentsURL
                .appendingPathComponent("data", isDirectory: true)
                .appendingPathComponent("file_system", isDirectory: true)
                .appendingPathComponent("storage", isDirectory: true)

            guard fileManager.fileExists(atPath: storageDirectory.path) else {
                print("⚠️ Storage directory doesn't exist: \(storageDirectory.path)")
                return report
            }

            // Recursively find all files in storage
            if let enumerator = fileManager.enumerator(
                at: storageDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                          let isRegularFile = resourceValues.isRegularFile,
                          isRegularFile else {
                        continue
                    }

                    let physicalPath = fileURL.path

                    // Check if this physical file exists in database
                    if !databasePaths.contains(physicalPath) {
                        print("🗑️ Orphaned file found: \(physicalPath)")
                        do {
                            try fileManager.removeItem(at: fileURL)
                            report.orphanedFilesRemoved += 1
                            print("✅ Removed orphaned file: \(fileURL.lastPathComponent)")
                        } catch {
                            print("⚠️ Failed to remove orphaned file: \(error)")
                            report.errors.append("Failed to remove \(fileURL.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                }
            }

            // 4. Clean up empty directories
            try cleanupEmptyDirectories(at: storageDirectory, report: &report)

            print("🧹 Cleanup complete:")
            print("   - Orphaned files removed: \(report.orphanedFilesRemoved)")
            print("   - Empty directories removed: \(report.emptyDirectoriesRemoved)")
            print("   - Old directory removed: \(report.oldDirectoryRemoved)")
            print("   - Errors: \(report.errors.count)")

            return report
        }
    }

    private func cleanupEmptyDirectories(at url: URL, report: inout CleanupReport) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        // Collect directories (deepest first by sorting in reverse)
        var directories: [URL] = []
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                  let isDirectory = resourceValues.isDirectory,
                  isDirectory else {
                continue
            }
            directories.append(fileURL)
        }

        // Sort by path depth (deepest first) to delete from bottom up
        directories.sort { $0.path.components(separatedBy: "/").count > $1.path.components(separatedBy: "/").count }

        for directory in directories {
            // Check if directory is empty
            let contents = try fileManager.contentsOfDirectory(atPath: directory.path)
            if contents.isEmpty {
                try fileManager.removeItem(at: directory)
                report.emptyDirectoriesRemoved += 1
                print("✅ Removed empty directory: \(directory.lastPathComponent)")
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

struct CleanupReport {
    var orphanedFilesRemoved: Int = 0
    var emptyDirectoriesRemoved: Int = 0
    var oldDirectoryRemoved: Bool = false
    var errors: [String] = []

    var summary: String {
        var lines: [String] = []
        if orphanedFilesRemoved > 0 {
            lines.append("Removed \(orphanedFilesRemoved) orphaned file(s)")
        }
        if emptyDirectoriesRemoved > 0 {
            lines.append("Removed \(emptyDirectoriesRemoved) empty director(ies)")
        }
        if oldDirectoryRemoved {
            lines.append("Removed old Files directory")
        }
        if errors.isEmpty && lines.isEmpty {
            return "No cleanup needed - storage is clean"
        }
        if !errors.isEmpty {
            lines.append("\(errors.count) error(s) occurred")
        }
        return lines.joined(separator: "\n")
    }
}

enum FileStorageError: Error {
    case fileNotFound
    case invalidPath
    case extractionFailed
    case folderNotEmpty
}
