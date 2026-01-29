import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:mime/mime.dart';
import '../models/file_item.dart';
import '../models/folder_item.dart';

class FileSystemStorage {
  static final instance = FileSystemStorage._();
  FileSystemStorage._();

  Database? _db;
  Directory? _storageDir;

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

  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory(p.join(appDir.path, 'data', 'file_system'));
    await dataDir.create(recursive: true);

    _storageDir = Directory(p.join(dataDir.path, 'storage'));
    await _storageDir!.create(recursive: true);

    final dbPath = p.join(dataDir.path, 'file_system.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
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
            updated_at TEXT NOT NULL
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
      },
    );
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
    final fileStats = await File(targetPath).stat();
    final mimeType = lookupMimeType(targetPath);

    // Create file item
    final now = DateTime.now();
    final id = '${now.millisecondsSinceEpoch}_${fileName.hashCode}';
    final relativePath = targetFolderPath.isEmpty
        ? fileName
        : '$targetFolderPath$fileName';

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
    );

    // Insert into database
    await db.insert('files', fileItem.toMap());

    return fileItem;
  }

  Future<void> deleteFile(String id) async {
    final files = await db.query('files', where: 'id = ?', whereArgs: [id]);
    if (files.isEmpty) return;

    final fileItem = FileItem.fromMap(files.first);
    final filePath = p.join(storageDir.path, fileItem.relativePath);
    final file = File(filePath);

    if (file.existsSync()) {
      await file.delete();
    }

    await db.delete('files', where: 'id = ?', whereArgs: [id]);
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
      where: 'folder_path = ?',
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
      where: 'is_favorite = ?',
      whereArgs: [1],
      orderBy: 'name COLLATE NOCASE',
    );

    return results.map((m) => FileItem.fromMap(m)).toList();
  }

  Future<List<FileItem>> search(String query) async {
    final results = await db.query(
      'files',
      where: 'name LIKE ?',
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

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
