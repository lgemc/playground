import '../../../file_system/models/file_item.dart';
import '../../../file_system/services/file_system_storage.dart';
import '../../../../core/database/crdt_database.dart';

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
      final results = await CrdtDatabase.instance.query(
        'SELECT * FROM files WHERE id = ? AND deleted_at IS NULL',
        [fileId],
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
      final results = await CrdtDatabase.instance.query(
        'SELECT * FROM files WHERE deleted_at IS NULL ORDER BY name COLLATE NOCASE',
        [],
      );

      return results.map((m) => FileItem.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get files filtered by mime type prefix (e.g., "image/", "video/", "audio/").
  Future<List<FileItem>> getFilesByMimeType(String mimeTypePrefix) async {
    try {
      final results = await CrdtDatabase.instance.query(
        '''
        SELECT * FROM files
        WHERE mime_type LIKE ? AND deleted_at IS NULL
        ORDER BY name COLLATE NOCASE
        ''',
        ['$mimeTypePrefix%'],
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

  /// Check if a file has derivatives.
  Future<bool> hasDerivatives(String fileId) async {
    return _storage.hasDerivatives(fileId);
  }

  /// Get derivatives for a file.
  Future<List<dynamic>> getDerivatives(String fileId) async {
    return _storage.getDerivatives(fileId);
  }

  /// Get FileItem object for use with FileDerivativesScreen.
  Future<FileItem?> getFileItemById(String fileId) async {
    return getFileById(fileId);
  }
}
