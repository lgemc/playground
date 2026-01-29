import '../../../file_system/models/file_item.dart';
import '../../../file_system/services/file_system_storage.dart';

/// Bridge service for LMS apps to interact with the file system app.
/// This provides a clean interface for querying files by ID.
class FileSystemBridge {
  static FileSystemBridge? _instance;
  static FileSystemBridge get instance => _instance ??= FileSystemBridge._();

  FileSystemBridge._();

  FileSystemStorage get _storage => FileSystemStorage.instance;

  /// Get a file by its ID.
  Future<FileItem?> getFileById(String fileId) async {
    try {
      final results = await _storage.db.query(
        'files',
        where: 'id = ?',
        whereArgs: [fileId],
      );

      if (results.isEmpty) return null;

      return FileItem.fromMap(results.first);
    } catch (_) {
      return null;
    }
  }

  /// Get the absolute path for a file by its ID.
  Future<String?> getFilePathById(String fileId) async {
    final file = await getFileById(fileId);
    if (file == null) return null;

    return _storage.getAbsolutePath(file);
  }

  /// Get all available files for selection.
  Future<List<FileItem>> getAvailableFiles() async {
    try {
      final results = await _storage.db.query(
        'files',
        orderBy: 'name COLLATE NOCASE',
      );

      return results.map((m) => FileItem.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get files filtered by mime type prefix (e.g., "image/", "video/", "audio/").
  Future<List<FileItem>> getFilesByMimeType(String mimeTypePrefix) async {
    try {
      final results = await _storage.db.query(
        'files',
        where: 'mime_type LIKE ?',
        whereArgs: ['$mimeTypePrefix%'],
        orderBy: 'name COLLATE NOCASE',
      );

      return results.map((m) => FileItem.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Search files by name.
  Future<List<FileItem>> searchFiles(String query) async {
    return _storage.search(query);
  }
}
