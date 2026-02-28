import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:mime/mime.dart';
import 'package:crypto/crypto.dart';
import '../models/file_item.dart';
import '../models/folder_item.dart';
import '../models/derivative_artifact.dart';
import '../../../core/database/crdt_database.dart';

class FileSystemStorage {
  static final instance = FileSystemStorage._();
  FileSystemStorage._();

  bool _initialized = false;
  Directory? _storageDir;
  Directory? _derivativesDir;

  Directory get storageDir {
    if (_storageDir == null) {
      throw StateError('FileSystemStorage not initialized. Call init() first.');
    }
    return _storageDir!;
  }

  Directory get derivativesDir {
    if (_derivativesDir == null) {
      throw StateError('FileSystemStorage not initialized. Call init() first.');
    }
    return _derivativesDir!;
  }

  /// Compute SHA-256 hash of a file's content
  Future<String> _computeFileHash(File file) async {
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> init() async {
    if (_initialized) return;

    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory(p.join(appDir.path, 'data', 'file_system'));
    await dataDir.create(recursive: true);

    _storageDir = Directory(p.join(dataDir.path, 'storage'));
    await _storageDir!.create(recursive: true);

    _derivativesDir = Directory(p.join(dataDir.path, 'derivatives'));
    await _derivativesDir!.create(recursive: true);

    // Use CRDT database for sync support
    await CrdtDatabase.instance.execute('''
      CREATE TABLE IF NOT EXISTS files (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        folder_path TEXT NOT NULL,
        mime_type TEXT,
        size INTEGER,
        is_favorite INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        content_hash TEXT
      )
    ''');

    await CrdtDatabase.instance.execute('''
      CREATE TABLE IF NOT EXISTS folders (
        path TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        parent_path TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');

    await CrdtDatabase.instance.execute('''
      CREATE TABLE IF NOT EXISTS derivatives (
        id TEXT PRIMARY KEY NOT NULL,
        file_id TEXT NOT NULL,
        type TEXT NOT NULL,
        derivative_path TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        completed_at INTEGER,
        error_message TEXT,
        content_hash TEXT,
        deleted_at INTEGER
      )
    ''');

    // Create indices
    await CrdtDatabase.instance.execute(
      'CREATE INDEX IF NOT EXISTS idx_files_folder ON files(folder_path)',
    );
    await CrdtDatabase.instance.execute(
      'CREATE INDEX IF NOT EXISTS idx_files_favorite ON files(is_favorite)',
    );
    await CrdtDatabase.instance.execute(
      'CREATE INDEX IF NOT EXISTS idx_files_name ON files(name COLLATE NOCASE)',
    );
    await CrdtDatabase.instance.execute(
      'CREATE INDEX IF NOT EXISTS idx_derivatives_file_id ON derivatives(file_id)',
    );
    await CrdtDatabase.instance.execute(
      'CREATE INDEX IF NOT EXISTS idx_derivatives_status ON derivatives(status)',
    );

    _initialized = true;
  }


  // === Helper Methods ===

  /// Ensure all folders in a path exist in the database
  Future<void> _ensureFolderPathExists(String folderPath) async {
    if (folderPath.isEmpty) return;

    final parts = folderPath.split('/').where((p) => p.isNotEmpty).toList();
    String currentPath = '';

    for (final part in parts) {
      final parentPath = currentPath;
      currentPath = currentPath.isEmpty ? '$part/' : '$currentPath$part/';

      // Check if folder exists in database
      final existing = await CrdtDatabase.instance.query(
        'SELECT * FROM folders WHERE path = ?',
        [currentPath],
      );

      if (existing.isEmpty) {
        // Create folder entry
        await CrdtDatabase.instance.execute(
          '''
          INSERT OR IGNORE INTO folders (path, name, parent_path, created_at)
          VALUES (?, ?, ?, ?)
          ''',
          [
            currentPath,
            part,
            parentPath,
            DateTime.now().millisecondsSinceEpoch,
          ],
        );
      }
    }
  }

  // === File Operations ===

  Future<FileItem> addFile(File sourceFile, String targetFolderPath) async {
    final folderDir = Directory(p.join(storageDir.path, targetFolderPath));
    await folderDir.create(recursive: true);

    // Ensure all parent folders exist in database
    if (targetFolderPath.isNotEmpty) {
      await _ensureFolderPathExists(targetFolderPath);
    }

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
      contentHash: contentHash,
    );

    // Insert into database using CRDT
    await CrdtDatabase.instance.execute(
      '''
      INSERT INTO files (id, name, relative_path, folder_path, mime_type, size, is_favorite, created_at, updated_at, content_hash)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        fileItem.id,
        fileItem.name,
        fileItem.relativePath,
        fileItem.folderPath,
        fileItem.mimeType,
        fileItem.size,
        fileItem.isFavorite ? 1 : 0,
        fileItem.createdAt.millisecondsSinceEpoch,
        fileItem.updatedAt.millisecondsSinceEpoch,
        fileItem.contentHash,
      ],
    );

    return fileItem;
  }

  Future<void> deleteFile(String id) async {
    final files = await CrdtDatabase.instance.query(
      'SELECT * FROM files WHERE id = ?',
      [id],
    );
    if (files.isEmpty) return;

    final fileItem = FileItem.fromMap(files.first);
    final now = DateTime.now();

    // Soft delete: mark as deleted instead of removing
    await CrdtDatabase.instance.execute(
      '''
      UPDATE files
      SET deleted_at = ?, updated_at = ?
      WHERE id = ?
      ''',
      [
        now.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
        id,
      ],
    );

    // Still delete the actual file from disk
    final filePath = p.join(storageDir.path, fileItem.relativePath);
    final file = File(filePath);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<void> renameFile(String id, String newName) async {
    final files = await CrdtDatabase.instance.query(
      'SELECT * FROM files WHERE id = ?',
      [id],
    );
    if (files.isEmpty) return;

    final fileItem = FileItem.fromMap(files.first);
    final oldPath = p.join(storageDir.path, fileItem.relativePath);
    final newPath = p.join(storageDir.path, fileItem.folderPath, newName);

    // Rename on filesystem only if file exists
    // (metadata may exist in database before physical files are synced)
    final oldFile = File(oldPath);
    if (oldFile.existsSync()) {
      await oldFile.rename(newPath);
    }

    // Update database
    final newRelativePath = fileItem.folderPath.isEmpty
        ? newName
        : '${fileItem.folderPath}$newName';

    await CrdtDatabase.instance.execute(
      '''
      UPDATE files
      SET name = ?, relative_path = ?, updated_at = ?
      WHERE id = ?
      ''',
      [
        newName,
        newRelativePath,
        DateTime.now().millisecondsSinceEpoch,
        id,
      ],
    );
  }

  Future<void> moveFile(String id, String newFolderPath) async {
    final files = await CrdtDatabase.instance.query(
      'SELECT * FROM files WHERE id = ?',
      [id],
    );
    if (files.isEmpty) return;

    final fileItem = FileItem.fromMap(files.first);
    final oldPath = p.join(storageDir.path, fileItem.relativePath);
    final newDir = Directory(p.join(storageDir.path, newFolderPath));
    await newDir.create(recursive: true);

    final newPath = p.join(newDir.path, fileItem.name);

    // Move on filesystem only if file exists
    // (metadata may exist in database before physical files are synced)
    final oldFile = File(oldPath);
    if (oldFile.existsSync()) {
      await oldFile.rename(newPath);
    }

    // Update database
    final newRelativePath = newFolderPath.isEmpty
        ? fileItem.name
        : '$newFolderPath${fileItem.name}';

    await CrdtDatabase.instance.execute(
      '''
      UPDATE files
      SET folder_path = ?, relative_path = ?, updated_at = ?
      WHERE id = ?
      ''',
      [
        newFolderPath,
        newRelativePath,
        DateTime.now().millisecondsSinceEpoch,
        id,
      ],
    );
  }

  Future<void> toggleFavorite(String id) async {
    final files = await CrdtDatabase.instance.query(
      'SELECT * FROM files WHERE id = ?',
      [id],
    );
    if (files.isEmpty) return;

    final fileItem = FileItem.fromMap(files.first);
    await CrdtDatabase.instance.execute(
      '''
      UPDATE files
      SET is_favorite = ?, updated_at = ?
      WHERE id = ?
      ''',
      [
        fileItem.isFavorite ? 0 : 1,
        DateTime.now().millisecondsSinceEpoch,
        id,
      ],
    );
  }

  // === Folder Operations ===

  Future<void> createFolder(String name, String parentPath) async {
    final folderPath = parentPath.isEmpty ? '$name/' : '$parentPath$name/';
    final dir = Directory(p.join(storageDir.path, folderPath));
    await dir.create(recursive: true);

    // Add to database
    final now = DateTime.now();
    await CrdtDatabase.instance.execute(
      '''
      INSERT OR REPLACE INTO folders (path, name, parent_path, created_at)
      VALUES (?, ?, ?, ?)
      ''',
      [
        folderPath,
        name,
        parentPath,
        now.millisecondsSinceEpoch,
      ],
    );
  }

  Future<void> deleteFolder(String path) async {
    // Check if folder has any non-deleted files in database
    final files = await CrdtDatabase.instance.query(
      'SELECT COUNT(*) as count FROM files WHERE folder_path = ? AND deleted_at IS NULL',
      [path],
    );

    final fileCount = files.first['count'] as int;
    if (fileCount > 0) {
      throw Exception('Folder is not empty');
    }

    // Check if folder has any non-deleted subfolders in database
    final subfolders = await CrdtDatabase.instance.query(
      'SELECT COUNT(*) as count FROM folders WHERE parent_path = ? AND deleted_at IS NULL',
      [path],
    );

    final subfolderCount = subfolders.first['count'] as int;
    if (subfolderCount > 0) {
      throw Exception('Folder is not empty');
    }

    // Delete the physical directory (use recursive to handle any leftover files from failed deletions)
    final dir = Directory(p.join(storageDir.path, path));
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }

    // Soft delete from database
    await CrdtDatabase.instance.execute(
      '''
      UPDATE folders
      SET deleted_at = ?
      WHERE path = ?
      ''',
      [
        DateTime.now().millisecondsSinceEpoch,
        path,
      ],
    );
  }

  Future<void> renameFolder(String oldPath, String newName) async {
    final oldDir = Directory(p.join(storageDir.path, oldPath));

    // Calculate new path
    final parts = oldPath.split('/').where((p) => p.isNotEmpty).toList();
    parts[parts.length - 1] = newName;
    final newPath = '${parts.join('/')}/';
    final newDir = Directory(p.join(storageDir.path, newPath));

    // Rename directory only if it exists on disk
    // (metadata may exist in database before physical files are synced)
    if (oldDir.existsSync()) {
      await oldDir.rename(newDir.path);
    } else {
      // If old directory doesn't exist, just ensure new directory exists
      await newDir.create(recursive: true);
    }

    // Update folder record in database
    final parentParts = parts.sublist(0, parts.length - 1);
    final parentPath = parentParts.isEmpty ? '' : '${parentParts.join('/')}/';

    await CrdtDatabase.instance.execute(
      '''
      UPDATE folders
      SET path = ?, name = ?, parent_path = ?
      WHERE path = ?
      ''',
      [
        newPath,
        newName,
        parentPath,
        oldPath,
      ],
    );

    // Update all files in this folder and subfolders
    final files = await CrdtDatabase.instance.query(
      'SELECT * FROM files WHERE folder_path LIKE ? OR folder_path = ?',
      ['$oldPath%', oldPath],
    );

    for (final fileMap in files) {
      final file = FileItem.fromMap(fileMap);
      final newFolderPath = file.folderPath.replaceFirst(oldPath, newPath);
      final newRelativePath = newFolderPath.isEmpty
          ? file.name
          : '$newFolderPath${file.name}';

      await CrdtDatabase.instance.execute(
        '''
        UPDATE files
        SET folder_path = ?, relative_path = ?, updated_at = ?
        WHERE id = ?
        ''',
        [
          newFolderPath,
          newRelativePath,
          DateTime.now().millisecondsSinceEpoch,
          file.id,
        ],
      );
    }

    // Update all subfolders
    final subfolders = await CrdtDatabase.instance.query(
      'SELECT * FROM folders WHERE path LIKE ? AND path != ?',
      ['$oldPath%', oldPath],
    );

    for (final folderMap in subfolders) {
      final subfolderPath = folderMap['path'] as String;
      final newSubfolderPath = subfolderPath.replaceFirst(oldPath, newPath);
      final subfolderParentPath = folderMap['parent_path'] as String;
      final newSubfolderParentPath = subfolderParentPath.replaceFirst(oldPath, newPath);

      await CrdtDatabase.instance.execute(
        '''
        UPDATE folders
        SET path = ?, parent_path = ?
        WHERE path = ?
        ''',
        [
          newSubfolderPath,
          newSubfolderParentPath,
          subfolderPath,
        ],
      );
    }
  }

  // === Queries ===

  Future<List<FileItem>> getFilesInFolder(String folderPath) async {
    final results = await CrdtDatabase.instance.query(
      '''
      SELECT * FROM files
      WHERE folder_path = ? AND is_deleted = 0 AND deleted_at IS NULL
      ORDER BY name COLLATE NOCASE
      ''',
      [folderPath],
    );

    return results.map((m) => FileItem.fromMap(m)).toList();
  }

  Future<List<FolderItem>> getFoldersInPath(String folderPath) async {
    // Query the folders table directly
    final results = await CrdtDatabase.instance.query(
      '''
      SELECT * FROM folders
      WHERE parent_path = ? AND deleted_at IS NULL
      ORDER BY name COLLATE NOCASE
      ''',
      [folderPath],
    );

    return results.map((row) {
      return FolderItem(
        name: row['name'] as String,
        path: row['path'] as String,
      );
    }).toList();
  }

  Future<List<FileItem>> getFavorites() async {
    final results = await CrdtDatabase.instance.query(
      '''
      SELECT * FROM files
      WHERE is_favorite = ? AND deleted_at IS NULL
      ORDER BY name COLLATE NOCASE
      ''',
      [1],
    );

    return results.map((m) => FileItem.fromMap(m)).toList();
  }

  Future<List<FileItem>> search(String query) async {
    final results = await CrdtDatabase.instance.query(
      '''
      SELECT * FROM files
      WHERE name LIKE ? AND deleted_at IS NULL
      ORDER BY name COLLATE NOCASE
      LIMIT 50
      ''',
      ['%$query%'],
    );

    return results.map((m) => FileItem.fromMap(m)).toList();
  }

  // === Export ===

  Future<File> getFileForExport(String id) async {
    final files = await CrdtDatabase.instance.query(
      'SELECT * FROM files WHERE id = ?',
      [id],
    );
    if (files.isEmpty) {
      throw Exception('File not found');
    }

    final fileItem = FileItem.fromMap(files.first);
    return File(p.join(storageDir.path, fileItem.relativePath));
  }

  String getAbsolutePath(FileItem file) {
    return p.join(storageDir.path, file.relativePath);
  }

  Future<FileItem?> getFileById(String id) async {
    final files = await CrdtDatabase.instance.query(
      'SELECT * FROM files WHERE id = ? AND deleted_at IS NULL',
      [id],
    );

    if (files.isEmpty) {
      return null;
    }

    return FileItem.fromMap(files.first);
  }

  // === Derivative Operations ===

  Future<List<DerivativeArtifact>> getDerivatives(String fileId) async {
    try {
      // Try with deleted_at column (new schema)
      final results = await CrdtDatabase.instance.query(
        '''
        SELECT * FROM derivatives
        WHERE file_id = ? AND deleted_at IS NULL
        ORDER BY created_at DESC
        ''',
        [fileId],
      );

      return results.map((m) => DerivativeArtifact.fromJson(m)).toList();
    } catch (e) {
      // Fall back to old schema without deleted_at column
      print('[FileSystem] Using old schema (no deleted_at column): $e');
      final results = await CrdtDatabase.instance.query(
        '''
        SELECT * FROM derivatives
        WHERE file_id = ?
        ORDER BY created_at DESC
        ''',
        [fileId],
      );

      return results.map((m) => DerivativeArtifact.fromJson(m)).toList();
    }
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

    await CrdtDatabase.instance.execute(
      '''
      INSERT INTO derivatives (id, file_id, type, derivative_path, status, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        derivative.id,
        derivative.fileId,
        derivative.type,
        derivative.derivativePath,
        derivative.status,
        derivative.createdAt.millisecondsSinceEpoch,
      ],
    );

    return derivative;
  }

  Future<void> updateDerivative(
    String id, {
    String? status,
    String? errorMessage,
  }) async {
    if (status == null && errorMessage == null) return;

    final setParts = <String>[];
    final values = <dynamic>[];

    if (status != null) {
      setParts.add('status = ?');
      values.add(status);
      if (status == 'completed') {
        setParts.add('completed_at = ?');
        values.add(DateTime.now().millisecondsSinceEpoch);

        // Compute and store content hash for sync (if column exists)
        final derivative = await getDerivative(id);
        if (derivative != null) {
          final file = File(derivative.derivativePath);
          if (file.existsSync()) {
            final hash = await _computeFileHash(file);
            setParts.add('content_hash = ?');
            values.add(hash);
          }
        }
      }
    }

    if (errorMessage != null) {
      setParts.add('error_message = ?');
      values.add(errorMessage);
    }

    values.add(id); // for WHERE clause

    try {
      await CrdtDatabase.instance.execute(
        '''
        UPDATE derivatives
        SET ${setParts.join(', ')}
        WHERE id = ?
        ''',
        values,
      );
    } catch (e) {
      // If update fails (likely due to content_hash column not existing),
      // retry without the hash
      if (setParts.contains('content_hash = ?')) {
        print('[FileSystem] Retrying update without content_hash (old schema)');
        setParts.removeWhere((s) => s == 'content_hash = ?');
        values.removeAt(values.length - 2); // Remove hash value (last before id)

        await CrdtDatabase.instance.execute(
          '''
          UPDATE derivatives
          SET ${setParts.join(', ')}
          WHERE id = ?
          ''',
          values,
        );
      } else {
        rethrow;
      }
    }
  }

  Future<void> deleteDerivative(String id) async {
    try {
      // Soft delete - mark as deleted instead of removing
      // This allows sync to propagate deletions across devices
      await CrdtDatabase.instance.execute(
        'UPDATE derivatives SET deleted_at = ? WHERE id = ?',
        [DateTime.now().millisecondsSinceEpoch, id],
      );
    } catch (e) {
      // Fall back to hard delete for old schema
      print('[FileSystem] Using hard delete (old schema): $e');
      final derivative = await getDerivative(id);
      if (derivative != null) {
        final file = File(derivative.derivativePath);
        if (file.existsSync()) {
          await file.delete();
        }
      }

      await CrdtDatabase.instance.execute(
        'DELETE FROM derivatives WHERE id = ?',
        [id],
      );
    }

    // Optionally delete the actual file (can be kept for recovery)
    // For now, keep files to allow undo/recovery
  }

  Future<bool> hasDerivatives(String fileId) async {
    try {
      final result = await CrdtDatabase.instance.query(
        'SELECT COUNT(*) as count FROM derivatives WHERE file_id = ? AND deleted_at IS NULL',
        [fileId],
      );

      final count = result.first['count'] as int;
      return count > 0;
    } catch (e) {
      // Fall back to old schema
      final result = await CrdtDatabase.instance.query(
        'SELECT COUNT(*) as count FROM derivatives WHERE file_id = ?',
        [fileId],
      );

      final count = result.first['count'] as int;
      return count > 0;
    }
  }

  Future<DerivativeArtifact?> getDerivative(String id) async {
    final results = await CrdtDatabase.instance.query(
      'SELECT * FROM derivatives WHERE id = ?',
      [id],
    );

    if (results.isEmpty) return null;
    return DerivativeArtifact.fromJson(results.first);
  }

  Future<String> getDerivativeContent(String id) async {
    final derivative = await getDerivative(id);
    if (derivative == null) {
      throw Exception('Derivative not found');
    }

    // Reconstruct local path
    final fileName = '${derivative.id}.md';
    final localPath = p.join(_derivativesDir!.path, fileName);
    final file = File(localPath);

    if (!file.existsSync()) {
      throw Exception(
        'Derivative file not found on disk. This derivative may have been '
        'synced from another device but the file content was not transferred. '
        'Try regenerating the derivative or enabling file content sync.'
      );
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
    // CRDT database is managed globally, no need to close
  }

  /// Clean up folders marked as deleted (useful after sync)
  Future<void> cleanupDeletedFolders() async {
    // Query folders marked as deleted
    final deletedFolders = await CrdtDatabase.instance.query(
      '''
      SELECT * FROM folders
      WHERE deleted_at IS NOT NULL
      ORDER BY path DESC
      ''', // DESC order ensures we delete deepest folders first
      [],
    );

    print('[FileSystem] Cleaning up ${deletedFolders.length} deleted folders');

    for (final folderMap in deletedFolders) {
      final path = folderMap['path'] as String;
      final dir = Directory(p.join(storageDir.path, path));

      if (dir.existsSync()) {
        try {
          // Delete recursively (even if not empty)
          await dir.delete(recursive: true);
          print('[FileSystem]   ✓ Deleted: $path');
        } catch (e) {
          print('[FileSystem]   ✗ Failed to delete $path: $e');
        }
      }
    }
  }

  /// Ensure all folders in the database have physical directories on disk
  Future<void> ensurePhysicalFoldersExist() async {
    // Query all non-deleted folders
    final folders = await CrdtDatabase.instance.query(
      '''
      SELECT * FROM folders
      WHERE deleted_at IS NULL
      ORDER BY path ASC
      ''', // ASC order ensures we create parent folders first
      [],
    );

    print('[FileSystem] Ensuring ${folders.length} folders exist on disk');

    int created = 0;
    for (final folderMap in folders) {
      final path = folderMap['path'] as String;
      final dir = Directory(p.join(storageDir.path, path));

      if (!dir.existsSync()) {
        try {
          await dir.create(recursive: true);
          print('[FileSystem]   ✓ Created: $path');
          created++;
        } catch (e) {
          print('[FileSystem]   ✗ Failed to create $path: $e');
        }
      }
    }

    if (created > 0) {
      print('[FileSystem] Created $created physical directories');
    }
  }

  // === Sync Operations ===

  /// Check if a file's content has changed by comparing its current hash
  Future<bool> hasFileContentChanged(String fileId) async {
    final files = await CrdtDatabase.instance.query(
      'SELECT * FROM files WHERE id = ?',
      [fileId],
    );
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
    final files = await CrdtDatabase.instance.query(
      'SELECT * FROM files WHERE id = ?',
      [fileId],
    );
    if (files.isEmpty) return;

    final fileItem = FileItem.fromMap(files.first);
    final filePath = p.join(storageDir.path, fileItem.relativePath);
    final file = File(filePath);
    if (!file.existsSync()) return;

    final newHash = await _computeFileHash(file);

    await CrdtDatabase.instance.execute(
      '''
      UPDATE files
      SET content_hash = ?, updated_at = ?
      WHERE id = ?
      ''',
      [
        newHash,
        DateTime.now().millisecondsSinceEpoch,
        fileId,
      ],
    );
  }

  /// Get file metadata changes since a given timestamp for sync
  Future<List<Map<String, dynamic>>> getChangesForSync(DateTime? since) async {
    if (since != null) {
      final results = await CrdtDatabase.instance.query(
        '''
        SELECT * FROM files
        WHERE updated_at > ?
        ORDER BY updated_at ASC
        ''',
        [since.millisecondsSinceEpoch],
      );
      return results;
    } else {
      // First sync - get all non-deleted files
      final results = await CrdtDatabase.instance.query(
        '''
        SELECT * FROM files
        WHERE deleted_at IS NULL
        ORDER BY updated_at ASC
        ''',
        [],
      );
      return results;
    }
  }

  /// Get files that exist in metadata but missing actual file content
  Future<List<FileItem>> getFilesNeedingContent() async {
    final results = await CrdtDatabase.instance.query(
      '''
      SELECT * FROM files
      WHERE deleted_at IS NULL
      ORDER BY updated_at DESC
      ''',
      [],
    );

    print('[FileSystem] getFilesNeedingContent: checking ${results.length} files in metadata');

    final filesNeedingContent = <FileItem>[];
    for (final fileMap in results) {
      final fileItem = FileItem.fromMap(fileMap);
      final filePath = p.join(storageDir.path, fileItem.relativePath);
      final file = File(filePath);

      // Check if file is missing on disk
      if (!file.existsSync()) {
        print('[FileSystem]   Missing: ${fileItem.name} (hash: ${fileItem.contentHash})');
        filesNeedingContent.add(fileItem);
      }
    }

    print('[FileSystem] Total files needing content: ${filesNeedingContent.length}');
    return filesNeedingContent;
  }

  /// Get file by content hash
  Future<FileItem?> getFileByHash(String hash) async {
    final results = await CrdtDatabase.instance.query(
      '''
      SELECT * FROM files
      WHERE content_hash = ? AND deleted_at IS NULL
      LIMIT 1
      ''',
      [hash],
    );

    return results.isNotEmpty ? FileItem.fromMap(results.first) : null;
  }

  /// Get relative path for a file by its content hash
  Future<String?> getRelativePathByHash(String hash) async {
    final file = await getFileByHash(hash);
    return file?.relativePath;
  }

  /// Get absolute disk path for a blob by content hash (without loading data)
  Future<String?> getAbsolutePathByHash(String hash) async {
    final file = await getFileByHash(hash);
    if (file == null) return null;
    final absolutePath = p.join(storageDir.path, file.relativePath);
    if (!File(absolutePath).existsSync()) return null;
    print('[FileSystem] getAbsolutePathByHash($hash): Found at ${file.relativePath}');
    return absolutePath;
  }

  /// Get blob bytes by content hash
  Future<List<int>?> getBlobByHash(String hash) async {
    final file = await getFileByHash(hash);
    if (file == null) {
      print('[FileSystem] getBlobByHash($hash): No file metadata found');
      return null;
    }

    final absolutePath = p.join(storageDir.path, file.relativePath);
    final ioFile = File(absolutePath);
    if (!ioFile.existsSync()) {
      print('[FileSystem] getBlobByHash($hash): File exists in DB but missing on disk');
      print('[FileSystem]   Expected path: $absolutePath');
      print('[FileSystem]   Storage dir: ${storageDir.path}');
      print('[FileSystem]   Relative path: ${file.relativePath}');

      // Check if the parent directory exists
      final parentDir = ioFile.parent;
      print('[FileSystem]   Parent dir exists: ${parentDir.existsSync()}');
      if (parentDir.existsSync()) {
        final filesInParent = parentDir.listSync();
        print('[FileSystem]   Files in parent: ${filesInParent.map((f) => p.basename(f.path)).toList()}');
      }

      return null;
    }

    print('[FileSystem] getBlobByHash($hash): Found at ${file.relativePath}');
    return ioFile.readAsBytes();
  }

  /// Store blob from remote device
  Future<void> storeBlobByHash(String hash, List<int> data, String relativePath) async {
    // Find ALL files with this hash (there might be duplicates)
    final results = await CrdtDatabase.instance.query(
      '''
      SELECT * FROM files
      WHERE content_hash = ? AND deleted_at IS NULL
      ''',
      [hash],
    );

    print('[FileSystem] Storing blob for hash $hash to ${results.length} file(s)');

    if (results.isEmpty) {
      print('[FileSystem] ⚠️ No files found with hash $hash, skipping');
      return;
    }

    // Verify the blob hash first (before writing to disk)
    final tempFile = File(p.join(storageDir.path, '.temp_$hash'));
    await tempFile.writeAsBytes(data);
    final actualHash = await _computeFileHash(tempFile);

    if (actualHash != hash) {
      await tempFile.delete();
      throw Exception('Hash mismatch: expected $hash, got $actualHash');
    }

    // Store blob to ALL files with this hash
    for (final fileMap in results) {
      final fileItem = FileItem.fromMap(fileMap);
      final filePath = p.join(storageDir.path, fileItem.relativePath);
      final file = File(filePath);

      print('[FileSystem]   → Storing to: ${fileItem.relativePath} (${data.length} bytes)');

      // Create parent directories
      await file.parent.create(recursive: true);

      // Copy the verified blob
      await tempFile.copy(filePath);
    }

    // Clean up temp file
    await tempFile.delete();

    print('[FileSystem] ✅ Blob stored and verified to ${results.length} location(s)');
  }

  /// Store blob from a temp file path (avoids loading full file into RAM)
  Future<void> storeBlobByPath(String hash, String tempFilePath, String relativePath) async {
    final tempFile = File(tempFilePath);
    if (!tempFile.existsSync()) {
      print('[FileSystem] ❌ Temp file not found: $tempFilePath');
      throw Exception('Temp file not found: $tempFilePath');
    }

    // Verify hash of the received file
    final actualHash = await _computeFileHash(tempFile);

    if (actualHash != hash) {
      print('[FileSystem] ⚠️ Hash mismatch: expected $hash, got $actualHash');
      print('[FileSystem] Attempting to regenerate stale hashes...');

      // Find files with the expected hash (stale)
      final staleResults = await CrdtDatabase.instance.query(
        '''
        SELECT * FROM files
        WHERE content_hash = ? AND deleted_at IS NULL
        ''',
        [hash],
      );

      if (staleResults.isNotEmpty) {
        print('[FileSystem] Found ${staleResults.length} file(s) with stale hash in database');

        // Check if any local files match the actual hash
        bool regenerated = false;
        List<String> updatedFileIds = [];

        for (final fileMap in staleResults) {
          final fileItem = FileItem.fromMap(fileMap);
          final localFile = File(p.join(storageDir.path, fileItem.relativePath));

          if (localFile.existsSync()) {
            // File exists locally - verify it matches the actual hash
            final localHash = await _computeFileHash(localFile);
            if (localHash == actualHash) {
              print('[FileSystem] ✓ Local file ${fileItem.relativePath} matches actual hash!');
              print('[FileSystem] Updating hash in database: $hash → $actualHash');
              await CrdtDatabase.instance.execute(
                'UPDATE files SET content_hash = ?, updated_at = ? WHERE id = ?',
                [actualHash, DateTime.now().millisecondsSinceEpoch, fileItem.id],
              );
              updatedFileIds.add(fileItem.id);
              regenerated = true;
            }
          } else {
            // File doesn't exist locally - this is a sync receive scenario
            // Accept the blob and update hash to match what was received
            print('[FileSystem] ✓ File ${fileItem.relativePath} missing locally, accepting blob with actual hash');
            print('[FileSystem] Updating hash in database: $hash → $actualHash');
            await CrdtDatabase.instance.execute(
              'UPDATE files SET content_hash = ?, updated_at = ? WHERE id = ?',
              [actualHash, DateTime.now().millisecondsSinceEpoch, fileItem.id],
            );
            updatedFileIds.add(fileItem.id);
            regenerated = true;
          }
        }

        if (regenerated) {
          print('[FileSystem] Hash(es) regenerated successfully for ${updatedFileIds.length} file(s)');

          // Store blob to the updated files
          for (final fileMap in staleResults) {
            final fileItem = FileItem.fromMap(fileMap);
            if (updatedFileIds.contains(fileItem.id)) {
              final filePath = p.join(storageDir.path, fileItem.relativePath);
              final file = File(filePath);

              await file.parent.create(recursive: true);
              await tempFile.copy(filePath);
              print('[FileSystem]   → Stored to: ${fileItem.relativePath}');
            }
          }

          print('[FileSystem] ✅ Blob stored to ${updatedFileIds.length} file(s) with regenerated hash');
          return;
        }
      }

      // Check if we have files expecting the actual hash
      final actualHashResults = await CrdtDatabase.instance.query(
        '''
        SELECT * FROM files
        WHERE content_hash = ? AND deleted_at IS NULL
        ''',
        [actualHash],
      );

      if (actualHashResults.isNotEmpty) {
        print('[FileSystem] Found ${actualHashResults.length} file(s) expecting actual hash $actualHash');

        for (final fileMap in actualHashResults) {
          final fileItem = FileItem.fromMap(fileMap);
          final filePath = p.join(storageDir.path, fileItem.relativePath);
          final file = File(filePath);

          await file.parent.create(recursive: true);
          await tempFile.copy(filePath);
          print('[FileSystem]   → Stored to: ${fileItem.relativePath}');
        }

        print('[FileSystem] ✅ Blob stored to ${actualHashResults.length} file(s) using actual hash');
        return;
      }

      // No matches found
      await tempFile.delete();
      throw Exception('Hash mismatch: expected $hash, got $actualHash. No matching files found.');
    }

    // Hash matches - store blob normally
    final results = await CrdtDatabase.instance.query(
      '''
      SELECT * FROM files
      WHERE content_hash = ? AND deleted_at IS NULL
      ''',
      [hash],
    );

    print('[FileSystem] Storing blob for hash $hash to ${results.length} file(s)');

    if (results.isEmpty) {
      print('[FileSystem] ⚠️ No files found with hash $hash, skipping');
      return;
    }

    for (final fileMap in results) {
      final fileItem = FileItem.fromMap(fileMap);
      final filePath = p.join(storageDir.path, fileItem.relativePath);
      final file = File(filePath);

      final fileSize = await tempFile.length();
      print('[FileSystem]   → Storing to: ${fileItem.relativePath} ($fileSize bytes)');

      await file.parent.create(recursive: true);
      await tempFile.copy(filePath);
    }

    print('[FileSystem] ✅ Blob stored and verified to ${results.length} location(s)');
  }

  /// Get list of hashes we need based on metadata
  Future<List<String>> getMissingBlobHashes() async {
    final files = await getFilesNeedingContent();
    final hashes = files
        .where((f) => f.contentHash != null)
        .map((f) => f.contentHash!)
        .toSet() // Deduplicate - multiple files may share the same content hash
        .toList();

    print('[FileSystem] getMissingBlobHashes: ${files.length} files need content, ${hashes.length} unique hashes');
    return hashes;
  }

  // === Derivative Blob Sync Methods ===

  /// Regenerate missing content hashes for completed derivatives
  Future<void> regenerateDerivativeHashes() async {
    print('[FileSystem] Checking for derivatives without content hashes...');

    List<Map<String, dynamic>> results;
    try {
      results = await CrdtDatabase.instance.query(
        '''
        SELECT * FROM derivatives
        WHERE status = 'completed' AND deleted_at IS NULL AND content_hash IS NULL
        ''',
        [],
      );
    } catch (e) {
      // Old schema without content_hash column
      print('[FileSystem] content_hash column not available, skipping regeneration');
      return;
    }

    if (results.isEmpty) {
      print('[FileSystem] All derivatives have content hashes');
      return;
    }

    print('[FileSystem] Found ${results.length} derivative(s) without content hash, generating...');

    int regenerated = 0;
    for (final derivativeMap in results) {
      final derivative = DerivativeArtifact.fromJson(derivativeMap);

      // Reconstruct local path
      final fileName = '${derivative.id}.md';
      final localPath = p.join(_derivativesDir!.path, fileName);
      final file = File(localPath);

      if (file.existsSync()) {
        try {
          final hash = await _computeFileHash(file);
          await CrdtDatabase.instance.execute(
            'UPDATE derivatives SET content_hash = ? WHERE id = ?',
            [hash, derivative.id],
          );
          print('[FileSystem]   ✓ Generated hash for ${derivative.type} (${derivative.id})');
          regenerated++;
        } catch (e) {
          print('[FileSystem]   ✗ Failed to generate hash for ${derivative.id}: $e');
        }
      } else {
        print('[FileSystem]   ⚠️ File missing for ${derivative.id}, skipping');
      }
    }

    print('[FileSystem] ✅ Regenerated hashes for $regenerated derivative(s)');
  }

  /// Get derivative by content hash
  Future<DerivativeArtifact?> getDerivativeByHash(String hash) async {
    try {
      final results = await CrdtDatabase.instance.query(
        '''
        SELECT * FROM derivatives
        WHERE content_hash = ? AND deleted_at IS NULL
        LIMIT 1
        ''',
        [hash],
      );

      return results.isNotEmpty ? DerivativeArtifact.fromJson(results.first) : null;
    } catch (e) {
      // Fall back to old schema
      final results = await CrdtDatabase.instance.query(
        '''
        SELECT * FROM derivatives
        WHERE content_hash = ?
        LIMIT 1
        ''',
        [hash],
      );

      return results.isNotEmpty ? DerivativeArtifact.fromJson(results.first) : null;
    }
  }

  /// Get absolute path for derivative by hash (for blob sending)
  Future<String?> getDerivativeAbsolutePathByHash(String hash) async {
    final derivative = await getDerivativeByHash(hash);
    if (derivative == null) return null;

    // Reconstruct local path
    final fileName = '${derivative.id}.md';
    final localPath = p.join(_derivativesDir!.path, fileName);
    final file = File(localPath);

    if (!file.existsSync()) return null;

    print('[FileSystem] getDerivativeAbsolutePathByHash($hash): Found at $localPath');
    return localPath;
  }

  /// Get relative path for derivative by hash (path within derivatives directory)
  Future<String?> getDerivativeRelativePathByHash(String hash) async {
    final derivative = await getDerivativeByHash(hash);
    if (derivative == null) return null;

    // Return the derivative ID as relative path (can reconstruct full path)
    return '${derivative.id}.md';
  }

  /// Get list of derivatives that need content (metadata exists but file missing)
  Future<List<DerivativeArtifact>> getDerivativesNeedingContent() async {
    List<Map<String, dynamic>> results;

    try {
      results = await CrdtDatabase.instance.query(
        '''
        SELECT * FROM derivatives
        WHERE status = 'completed' AND deleted_at IS NULL AND content_hash IS NOT NULL
        ORDER BY created_at DESC
        ''',
        [],
      );
    } catch (e) {
      // Fall back to old schema
      results = await CrdtDatabase.instance.query(
        '''
        SELECT * FROM derivatives
        WHERE status = 'completed' AND content_hash IS NOT NULL
        ORDER BY created_at DESC
        ''',
        [],
      );
    }

    print('[FileSystem] getDerivativesNeedingContent: checking ${results.length} derivatives with hashes');

    final derivatives = results.map((m) => DerivativeArtifact.fromJson(m)).toList();

    // Filter to only those where file is missing
    final needingContent = <DerivativeArtifact>[];
    for (final derivative in derivatives) {
      // Reconstruct local path (derivative.derivativePath might be from another device)
      final fileName = '${derivative.id}.md';
      final localPath = p.join(_derivativesDir!.path, fileName);
      final file = File(localPath);

      if (!file.existsSync()) {
        print('[FileSystem]   Missing: ${derivative.type} for file ${derivative.fileId} (hash: ${derivative.contentHash})');
        needingContent.add(derivative);
      }
    }

    print('[FileSystem] Total derivatives needing content: ${needingContent.length}');
    return needingContent;
  }

  /// Get list of derivative hashes we need
  Future<List<String>> getMissingDerivativeHashes() async {
    final derivatives = await getDerivativesNeedingContent();
    final hashes = derivatives
        .where((d) => d.contentHash != null)
        .map((d) => d.contentHash!)
        .toSet()
        .toList();

    print('[FileSystem] getMissingDerivativeHashes: ${derivatives.length} derivatives need content, ${hashes.length} unique hashes');
    return hashes;
  }

  /// Store a derivative blob from temp file
  Future<void> storeDerivativeBlob(String hash, String tempFilePath, String relativePath) async {
    print('[FileSystem] storeDerivativeBlob called: hash=$hash, relativePath=$relativePath');

    final tempFile = File(tempFilePath);
    if (!tempFile.existsSync()) {
      print('[FileSystem] ❌ Temp file not found: $tempFilePath');
      throw Exception('Temp file not found: $tempFilePath');
    }

    // Verify hash
    final actualHash = await _computeFileHash(tempFile);
    if (actualHash != hash) {
      await tempFile.delete();
      throw Exception('Hash mismatch: expected $hash, got $actualHash');
    }

    // Find all derivatives with this hash
    List<Map<String, dynamic>> results;
    try {
      results = await CrdtDatabase.instance.query(
        '''
        SELECT * FROM derivatives
        WHERE content_hash = ? AND deleted_at IS NULL
        ''',
        [hash],
      );
    } catch (e) {
      // Fall back to old schema
      results = await CrdtDatabase.instance.query(
        '''
        SELECT * FROM derivatives
        WHERE content_hash = ?
        ''',
        [hash],
      );
    }

    print('[FileSystem] Storing derivative blob for hash $hash to ${results.length} derivative(s)');

    if (results.isEmpty) {
      print('[FileSystem] ⚠️ No derivatives found with hash $hash, skipping');
      return;
    }

    // Store blob to ALL derivatives with this hash
    for (final derivativeMap in results) {
      final derivative = DerivativeArtifact.fromJson(derivativeMap);

      // Reconstruct path using local derivatives directory
      // The derivative path in DB might be from another device
      final fileName = '${derivative.id}.md';
      final localPath = p.join(_derivativesDir!.path, fileName);
      final file = File(localPath);

      final fileSize = await tempFile.length();
      print('[FileSystem]   → Storing to: $localPath ($fileSize bytes)');

      // Create parent directories
      await file.parent.create(recursive: true);

      // Copy the verified blob
      await tempFile.copy(localPath);
    }

    print('[FileSystem] ✅ Derivative blob stored and verified to ${results.length} location(s)');
  }

  /// Get all local derivatives with content (for sending to remote device)
  Future<List<String>> getAllDerivativeHashes() async {
    List<Map<String, dynamic>> results;

    try {
      results = await CrdtDatabase.instance.query(
        '''
        SELECT DISTINCT content_hash FROM derivatives
        WHERE content_hash IS NOT NULL AND deleted_at IS NULL AND status = 'completed'
        ''',
        [],
      );
    } catch (e) {
      // Fall back to old schema
      results = await CrdtDatabase.instance.query(
        '''
        SELECT DISTINCT content_hash FROM derivatives
        WHERE content_hash IS NOT NULL AND status = 'completed'
        ''',
        [],
      );
    }

    return results
        .map((r) => r['content_hash'] as String)
        .toList();
  }
}
