import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Service for handling files shared with the app from external sources
class SharedFilesService {
  static final SharedFilesService _instance = SharedFilesService._internal();
  factory SharedFilesService() => _instance;
  SharedFilesService._internal();

  /// Directory where shared files are stored
  Future<Directory> get sharedFilesDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final sharedDir = Directory(path.join(appDir.path, 'data', 'shared_files'));
    if (!await sharedDir.exists()) {
      await sharedDir.create(recursive: true);
    }
    return sharedDir;
  }

  /// Initialize the service and set up listeners for shared files
  Future<void> initialize({
    required Function(List<String>) onFilesReceived,
  }) async {
    // Only initialize on mobile platforms (Android/iOS)
    if (!Platform.isAndroid && !Platform.isIOS) {
      return; // Desktop platforms don't support receive_sharing_intent
    }

    try {
      // For files shared when the app is closed
      final initialMedia = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initialMedia.isNotEmpty) {
        final filePaths = await _processSharedFiles(initialMedia);
        if (filePaths.isNotEmpty) {
          onFilesReceived(filePaths);
        }
      }

      // For files shared while the app is running
      ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> media) async {
        if (media.isNotEmpty) {
          final filePaths = await _processSharedFiles(media);
          if (filePaths.isNotEmpty) {
            onFilesReceived(filePaths);
          }
        }
      });
    } catch (e) {
      // Platform doesn't support sharing intent: $e
    }
  }

  /// Process shared files by copying them to our app's directory
  Future<List<String>> _processSharedFiles(List<SharedMediaFile> sharedFiles) async {
    final List<String> processedPaths = [];
    final sharedDir = await sharedFilesDirectory;

    for (final sharedFile in sharedFiles) {
      if (sharedFile.path.isEmpty) continue;

      try {
        final sourceFile = File(sharedFile.path);
        if (!await sourceFile.exists()) continue;

        // Generate unique filename
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final originalName = path.basename(sharedFile.path);
        final extension = path.extension(originalName);
        final baseName = path.basenameWithoutExtension(originalName);
        final newFileName = '${baseName}_$timestamp$extension';

        final targetPath = path.join(sharedDir.path, newFileName);
        await sourceFile.copy(targetPath);
        processedPaths.add(targetPath);
      } catch (e) {
        // Error processing shared file: $e
      }
    }

    return processedPaths;
  }


  /// Get all shared files
  Future<List<FileSystemEntity>> getSharedFiles() async {
    final sharedDir = await sharedFilesDirectory;
    if (!await sharedDir.exists()) {
      return [];
    }

    final files = sharedDir.listSync()
      ..sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return bStat.modified.compareTo(aStat.modified);
      });

    return files;
  }

  /// Delete a shared file
  Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      // Error deleting file: $e
      return false;
    }
  }

  /// Clear all shared files
  Future<void> clearAll() async {
    try {
      final sharedDir = await sharedFilesDirectory;
      if (await sharedDir.exists()) {
        await sharedDir.delete(recursive: true);
        await sharedDir.create(recursive: true);
      }
    } catch (e) {
      // Error clearing shared files: $e
    }
  }
}
