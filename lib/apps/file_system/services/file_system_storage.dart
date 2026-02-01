import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:mime/mime.dart';
import 'package:crypto/crypto.dart';
import '../models/file_item.dart';
import '../models/folder_item.dart';
import '../models/derivative_artifact.dart';
import '../../../core/sync/services/device_id_service.dart';

class FileSystemStorage {
  static final instance = FileSystemStorage._();
  FileSystemStorage._();

  Database? _db;
  Directory? _storageDir;
  Directory? _derivativesDir;
  String? _cachedDeviceId;

  Database get db {
    if (_db == null) {
      throw StateError('FileSystemStorage not initialized. Call init() first.');
    }
    return _db!;
  }

  Directory get storageDir {
    if (_storageDir == null) {
      throw StateError('FileSystemStorage not initialized. Call init() first.');
    }
    return _storageDir!;
  }

  Future<String> _getDeviceId() async {
    _cachedDeviceId ??= await DeviceIdService.instance.getDeviceId();
    return _cachedDeviceId!;
  }

  /// Compute SHA-256 hash of a file's content
  Future<String> _computeFileHash(File file) async {
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory(p.join(appDir.path, 'data', 'file_system'));
    await dataDir.create(recursive: true);

    _storageDir = Directory(p.join(dataDir.path, 'storage'));
    await _storageDir!.create(recursive: true);

    _derivativesDir = Directory(p.join(dataDir.path, 'derivatives'));
    await _derivativesDir!.create(recursive: true);

    final dbPath = p.join(dataDir.path, 'file_system.db');
    _db = await openDatabase(
      dbPath,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE files (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            relative_path TEXT NOT NULL UNIQUE,
            folder_path TEXT NOT NULL,
            mime_type TEXT,
            size INTEGER,
            is_favorite INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT,
            device_id TEXT DEFAULT '',
            sync_version INTEGER DEFAULT 1,
            content_hash TEXT
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_files_folder ON files(folder_path)',
        );
        await db.execute(
          'CREATE INDEX idx_files_favorite ON files(is_favorite)',
        );
        await db.execute(
          'CREATE INDEX idx_files_name ON files(name COLLATE NOCASE)',
        );
        await db.execute(
          'CREATE INDEX idx_files_updated_at ON files(updated_at)',
        );
        await db.execute(
          'CREATE INDEX idx_files_device_id ON files(device_id)',
        );

        await db.execute('''
          CREATE TABLE derivatives (
            id TEXT PRIMARY KEY,
            file_id TEXT NOT NULL,
            type TEXT NOT NULL,
            derivative_path TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            completed_at TEXT,
            error_message TEXT,
            FOREIGN KEY (file_id) REFERENCES files (id) ON DELETE CASCADE
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_derivatives_file_id ON derivatives(file_id)',
        );
        await db.execute(
          'CREATE INDEX idx_derivatives_status ON derivatives(status)',
        );

        await db.execute('''
          CREATE TABLE migration_status (
            id TEXT PRIMARY KEY,
            completed_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE derivatives (
              id TEXT PRIMARY KEY,
              file_id TEXT NOT NULL,
              type TEXT NOT NULL,
              derivative_path TEXT NOT NULL,
              status TEXT NOT NULL,
              created_at TEXT NOT NULL,
              completed_at TEXT,
              error_message TEXT,
              FOREIGN KEY (file_id) REFERENCES files (id) ON DELETE CASCADE
            )
          ''');

          await db.execute(
            'CREATE INDEX idx_derivatives_file_id ON derivatives(file_id)',
          );
          await db.execute(
            'CREATE INDEX idx_derivatives_status ON derivatives(status)',
          );

          await db.execute('''
            CREATE TABLE migration_status (
              id TEXT PRIMARY KEY,
              completed_at TEXT NOT NULL
            )
          ''');

          // Run migration from summaries app
          await _migrateSummariesToDerivatives(appDir, db);
        }

        if (oldVersion < 3) {
          // Add sync fields to files table
          await db.execute('ALTER TABLE files ADD COLUMN deleted_at TEXT');
          await db.execute('ALTER TABLE files ADD COLUMN device_id TEXT DEFAULT \'\'');
          await db.execute('ALTER TABLE files ADD COLUMN sync_version INTEGER DEFAULT 1');

          // Add indices for sync fields
          await db.execute(
            'CREATE INDEX idx_files_updated_at ON files(updated_at)',
          );
          await db.execute(
            'CREATE INDEX idx_files_device_id ON files(device_id)',
          );
        }

        if (oldVersion < 4) {
          // Add content hash field for file change detection
          await db.execute('ALTER TABLE files ADD COLUMN content_hash TEXT');
        }
      },
    );
  }

  Future<void> _migrateSummariesToDerivatives(
    Directory appDir,
    Database db,
  ) async {
    try {
      // Check if migration already ran
      final migrationCheck = await db.query(
        'migration_status',
        where: 'id = ?',
        whereArgs: ['summaries_to_derivatives'],
      );

      if (migrationCheck.isNotEmpty) {
        return; // Already migrated
      }

      // Open summaries database
      final summariesDbPath =
          p.join(appDir.path, 'data', 'summaries', 'summaries.db');
      final summariesDbFile = File(summariesDbPath);

      if (!await summariesDbFile.exists()) {
        // No summaries to migrate
        await db.insert('migration_status', {
          'id': 'summaries_to_derivatives',
          'completed_at': DateTime.now().toIso8601String(),
        });
        return;
      }

      final summariesDb = await openDatabase(summariesDbPath);

      try {
        // Get all summaries
        final summaries = await summariesDb.query('summaries');

        for (final summary in summaries) {
          final fileId = summary['file_id'] as String;
          final status = summary['status'] as String;
          final createdAt = summary['created_at'] as String;
          final completedAt = summary['completed_at'] as String?;
          final errorMessage = summary['error_message'] as String?;
          final summaryId = summary['id'] as String;

          // Create derivative record
          final derivativeId = summaryId;
          final derivativePath =
              p.join(_derivativesDir!.path, '$derivativeId.md');

          await db.insert('derivatives', {
            'id': derivativeId,
            'file_id': fileId,
            'type': 'summary',
            'derivative_path': derivativePath,
            'status': status,
            'created_at': createdAt,
            'completed_at': completedAt,
            'error_message': errorMessage,
          });

          // Copy summary file if it exists
          final oldSummaryPath = p.join(
            appDir.path,
            'data',
            'summaries',
            'summaries',
            '$summaryId.md',
          );
          final oldFile = File(oldSummaryPath);

          if (await oldFile.exists()) {
            await oldFile.copy(derivativePath);
          }
        }
      } finally {
        await summariesDb.close();
      }

      // Mark migration as complete
      await db.insert('migration_status', {
        'id': 'summaries_to_derivatives',
        'completed_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Log error but don't fail initialization
      print('Error migrating summaries: $e');
    }
  }

  // === File Operations ===

  Future<FileItem> addFile(File sourceFile, String targetFolderPath) async {
    final folderDir = Directory(p.join(storageDir.path, targetFolderPath));
    await folderDir.create(recursive: true);

    String fileName = p.basename(sourceFile.path);
    String targetPath = p.join(folderDir.path, fileName);

    // Handle name conflicts
    int counter = 1;
    while (File(targetPath).existsSync()) {
      final nameWithoutExt = p.basenameWithoutExtension(fileName);
      final ext = p.extension(fileName);
      fileName = '$nameWithoutExt ($counter)$ext';
      targetPath = p.join(folderDir.path, fileName);
      counter++;
    }

    // Copy file
    await sourceFile.copy(targetPath);

    // Get file info
    final targetFile = File(targetPath);
    final fileStats = await targetFile.stat();
    final mimeType = lookupMimeType(targetPath);

    // Create file item
    final now = DateTime.now();
    final id = '${now.millisecondsSinceEpoch}_${fileName.hashCode}';
    final relativePath = targetFolderPath.isEmpty
        ? fileName
        : '$targetFolderPath$fileName';
    final deviceId = await _getDeviceId();
    final contentHash = await _computeFileHash(targetFile);

    final fileItem = FileItem(
      id: id,
      name: fileName,
      relativePath: relativePath,
      folderPath: targetFolderPath,
      mimeType: mimeType,
      size: fileStats.size,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
      deviceId: deviceId,
      syncVersion: 1,
      contentHash: contentHash,
    );

    // Insert into database
    await db.insert('files', fileItem.toMap());

    return fileItem;
  }

  Future<void> deleteFile(String id) async {
    final files = await db.query('files', where: 'id = ?', whereArgs: [id]);
    if (files.isEmpty) return;

    final fileItem = FileItem.fromMap(files.first);
    final deviceId = await _getDeviceId();

    // Soft delete: mark as deleted instead of removing
    await db.update(
      'files',
      {
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'device_id': deviceId,
        'sync_version': fileItem.syncVersion + 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    // Still delete the actual file from disk
    final filePath = p.join(storageDir.path, fileItem.relativePath);
    final file = File(filePath);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<void> renameFile(String id, String newName) async {
    final files = await db.query('files', where: 'id = ?', whereArgs: [id]);
    if (files.isEmpty) return;

    final fileItem = FileItem.fromMap(files.first);
    final oldPath = p.join(storageDir.path, fileItem.relativePath);
    final newPath = p.join(storageDir.path, fileItem.folderPath, newName);

    // Rename on filesystem
    await File(oldPath).rename(newPath);

    // Update database
    final newRelativePath = fileItem.folderPath.isEmpty
        ? newName
        : '${fileItem.folderPath}$newName';

    await db.update(
      'files',
      {
        'name': newName,
        'relative_path': newRelativePath,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> moveFile(String id, String newFolderPath) async {
    final files = await db.query('files', where: 'id = ?', whereArgs: [id]);
    if (files.isEmpty) return;

    final fileItem = FileItem.fromMap(files.first);
    final oldPath = p.join(storageDir.path, fileItem.relativePath);
    final newDir = Directory(p.join(storageDir.path, newFolderPath));
    await newDir.create(recursive: true);

    final newPath = p.join(newDir.path, fileItem.name);

    // Move on filesystem
    await File(oldPath).rename(newPath);

    // Update database
    final newRelativePath = newFolderPath.isEmpty
        ? fileItem.name
        : '$newFolderPath${fileItem.name}';

    await db.update(
      'files',
      {
        'folder_path': newFolderPath,
        'relative_path': newRelativePath,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> toggleFavorite(String id) async {
    final files = await db.query('files', where: 'id = ?', whereArgs: [id]);
    if (files.isEmpty) return;

    final fileItem = FileItem.fromMap(files.first);
    await db.update(
      'files',
      {
        'is_favorite': fileItem.isFavorite ? 0 : 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // === Folder Operations ===

  Future<void> createFolder(String name, String parentPath) async {
    final folderPath = parentPath.isEmpty ? '$name/' : '$parentPath$name/';
    final dir = Directory(p.join(storageDir.path, folderPath));
    await dir.create(recursive: true);
  }

  Future<void> deleteFolder(String path) async {
    final dir = Directory(p.join(storageDir.path, path));

    // Check if folder is empty
    final contents = await dir.list().toList();
    if (contents.isNotEmpty) {
      throw Exception('Folder is not empty');
    }

    await dir.delete();
  }

  Future<void> renameFolder(String oldPath, String newName) async {
    final oldDir = Directory(p.join(storageDir.path, oldPath));

    // Calculate new path
    final parts = oldPath.split('/').where((p) => p.isNotEmpty).toList();
    parts[parts.length - 1] = newName;
    final newPath = '${parts.join('/')}/';
    final newDir = Directory(p.join(storageDir.path, newPath));

    // Rename directory
    await oldDir.rename(newDir.path);

    // Update all files in this folder and subfolders
    final files = await db.query(
      'files',
      where: 'folder_path LIKE ? OR folder_path = ?',
      whereArgs: ['$oldPath%', oldPath],
    );

    for (final fileMap in files) {
      final file = FileItem.fromMap(fileMap);
      final newFolderPath = file.folderPath.replaceFirst(oldPath, newPath);
      final newRelativePath = newFolderPath.isEmpty
          ? file.name
          : '$newFolderPath${file.name}';

      await db.update(
        'files',
        {
          'folder_path': newFolderPath,
          'relative_path': newRelativePath,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [file.id],
      );
    }
  }

  // === Queries ===

  Future<List<FileItem>> getFilesInFolder(String folderPath) async {
    final results = await db.query(
      'files',
      where: 'folder_path = ? AND deleted_at IS NULL',
      whereArgs: [folderPath],
      orderBy: 'name COLLATE NOCASE',
    );

    return results.map((m) => FileItem.fromMap(m)).toList();
  }

  Future<List<FolderItem>> getFoldersInPath(String folderPath) async {
    final dir = Directory(p.join(storageDir.path, folderPath));

    if (!dir.existsSync()) {
      return [];
    }

    final folders = <FolderItem>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final name = p.basename(entity.path);
        final path = folderPath.isEmpty ? '$name/' : '$folderPath$name/';
        folders.add(FolderItem(name: name, path: path));
      }
    }

    folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return folders;
  }

  Future<List<FileItem>> getFavorites() async {
    final results = await db.query(
      'files',
      where: 'is_favorite = ? AND deleted_at IS NULL',
      whereArgs: [1],
      orderBy: 'name COLLATE NOCASE',
    );

    return results.map((m) => FileItem.fromMap(m)).toList();
  }

  Future<List<FileItem>> search(String query) async {
    final results = await db.query(
      'files',
      where: 'name LIKE ? AND deleted_at IS NULL',
      whereArgs: ['%$query%'],
      orderBy: 'name COLLATE NOCASE',
      limit: 50,
    );

    return results.map((m) => FileItem.fromMap(m)).toList();
  }

  // === Export ===

  Future<File> getFileForExport(String id) async {
    final files = await db.query('files', where: 'id = ?', whereArgs: [id]);
    if (files.isEmpty) {
      throw Exception('File not found');
    }

    final fileItem = FileItem.fromMap(files.first);
    return File(p.join(storageDir.path, fileItem.relativePath));
  }

  String getAbsolutePath(FileItem file) {
    return p.join(storageDir.path, file.relativePath);
  }

  // === Derivative Operations ===

  Future<List<DerivativeArtifact>> getDerivatives(String fileId) async {
    final results = await db.query(
      'derivatives',
      where: 'file_id = ?',
      whereArgs: [fileId],
      orderBy: 'created_at DESC',
    );

    return results.map((m) => DerivativeArtifact.fromJson(m)).toList();
  }

  Future<DerivativeArtifact> createDerivative(
    String fileId,
    String type,
  ) async {
    final now = DateTime.now();
    final id = '${now.millisecondsSinceEpoch}_${fileId.hashCode}_$type';
    final derivativePath = p.join(_derivativesDir!.path, '$id.md');

    final derivative = DerivativeArtifact(
      id: id,
      fileId: fileId,
      type: type,
      derivativePath: derivativePath,
      status: 'pending',
      createdAt: now,
    );

    await db.insert('derivatives', derivative.toJson());

    return derivative;
  }

  Future<void> updateDerivative(
    String id, {
    String? status,
    String? errorMessage,
  }) async {
    final updates = <String, dynamic>{};

    if (status != null) {
      updates['status'] = status;
      if (status == 'completed') {
        updates['completed_at'] = DateTime.now().toIso8601String();
      }
    }

    if (errorMessage != null) {
      updates['error_message'] = errorMessage;
    }

    if (updates.isNotEmpty) {
      await db.update(
        'derivatives',
        updates,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> deleteDerivative(String id) async {
    // Get derivative info
    final results = await db.query(
      'derivatives',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (results.isEmpty) return;

    final derivative = DerivativeArtifact.fromJson(results.first);

    // Delete file if it exists
    final file = File(derivative.derivativePath);
    if (file.existsSync()) {
      await file.delete();
    }

    // Delete from database
    await db.delete('derivatives', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> hasDerivatives(String fileId) async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM derivatives WHERE file_id = ?',
      [fileId],
    );

    final count = result.first['count'] as int;
    return count > 0;
  }

  Future<DerivativeArtifact?> getDerivative(String id) async {
    final results = await db.query(
      'derivatives',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (results.isEmpty) return null;
    return DerivativeArtifact.fromJson(results.first);
  }

  Future<String> getDerivativeContent(String id) async {
    final derivative = await getDerivative(id);
    if (derivative == null) {
      throw Exception('Derivative not found');
    }

    final file = File(derivative.derivativePath);
    if (!file.existsSync()) {
      return '';
    }

    return await file.readAsString();
  }

  Future<void> setDerivativeContent(String id, String content) async {
    final derivative = await getDerivative(id);
    if (derivative == null) {
      throw Exception('Derivative not found');
    }

    final file = File(derivative.derivativePath);
    await file.writeAsString(content);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // === Sync Operations ===

  /// Check if a file's content has changed by comparing its current hash
  Future<bool> hasFileContentChanged(String fileId) async {
    final files = await db.query('files', where: 'id = ?', whereArgs: [fileId]);
    if (files.isEmpty) return false;

    final fileItem = FileItem.fromMap(files.first);
    if (fileItem.contentHash == null) return true; // No hash, assume changed

    final filePath = p.join(storageDir.path, fileItem.relativePath);
    final file = File(filePath);
    if (!file.existsSync()) return true; // File missing, needs sync

    final currentHash = await _computeFileHash(file);
    return currentHash != fileItem.contentHash;
  }

  /// Update the content hash for a file (call after file content changes)
  Future<void> updateFileHash(String fileId) async {
    final files = await db.query('files', where: 'id = ?', whereArgs: [fileId]);
    if (files.isEmpty) return;

    final fileItem = FileItem.fromMap(files.first);
    final filePath = p.join(storageDir.path, fileItem.relativePath);
    final file = File(filePath);
    if (!file.existsSync()) return;

    final newHash = await _computeFileHash(file);
    final deviceId = await _getDeviceId();

    await db.update(
      'files',
      {
        'content_hash': newHash,
        'updated_at': DateTime.now().toIso8601String(),
        'device_id': deviceId,
        'sync_version': fileItem.syncVersion + 1,
      },
      where: 'id = ?',
      whereArgs: [fileId],
    );
  }

  /// Get file metadata changes since a given timestamp for sync
  Future<List<Map<String, dynamic>>> getChangesForSync(DateTime? since) async {
    String whereClause;
    List<dynamic> whereArgs;

    if (since != null) {
      whereClause = 'updated_at > ?';
      whereArgs = [since.toIso8601String()];
    } else {
      // First sync - get all non-deleted files
      whereClause = 'deleted_at IS NULL';
      whereArgs = [];
    }

    final results = await db.query(
      'files',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'updated_at ASC',
    );

    return results;
  }

  /// Apply file metadata changes from remote device
  Future<void> applyChangesFromSync(List<Map<String, dynamic>> entities) async {
    for (final entity in entities) {
      await _upsertFileMetadata(entity);
    }
  }

  /// Insert or update file metadata (for sync, without actual file content)
  Future<void> _upsertFileMetadata(Map<String, dynamic> metadata) async {
    final id = metadata['id'] as String;
    final existing = await db.query('files', where: 'id = ?', whereArgs: [id]);

    if (existing.isEmpty) {
      // New file - insert metadata
      await db.insert('files', metadata);
    } else {
      // Existing file - use content-based conflict resolution
      final localFile = FileItem.fromMap(existing.first);
      final remoteVersion = metadata['sync_version'] as int? ?? 1;
      final remoteHash = metadata['content_hash'] as String?;
      final remoteUpdatedAt = metadata['updated_at'] as String?;

      // Content-based strategy: Check if actual content differs
      bool shouldUpdate = false;

      if (remoteHash != null && localFile.contentHash != null) {
        // Both have hashes - compare them
        if (remoteHash != localFile.contentHash) {
          // Content differs - use timestamp to decide
          if (remoteUpdatedAt != null) {
            final remoteTime = DateTime.parse(remoteUpdatedAt);
            shouldUpdate = remoteTime.isAfter(localFile.updatedAt);
          } else {
            shouldUpdate = remoteVersion > localFile.syncVersion;
          }
        }
        // If hashes match, no update needed (same content)
      } else {
        // Fall back to version-based resolution
        shouldUpdate = remoteVersion > localFile.syncVersion;
      }

      if (shouldUpdate) {
        await db.update(
          'files',
          metadata,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  /// Get files that exist in metadata but missing actual file content
  Future<List<FileItem>> getFilesNeedingContent() async {
    final results = await db.query(
      'files',
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at DESC',
    );

    final filesNeedingContent = <FileItem>[];
    for (final fileMap in results) {
      final fileItem = FileItem.fromMap(fileMap);
      final filePath = p.join(storageDir.path, fileItem.relativePath);
      final file = File(filePath);

      // Check if file is missing on disk
      if (!file.existsSync()) {
        filesNeedingContent.add(fileItem);
      }
    }

    return filesNeedingContent;
  }
}
