import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/sync_database.dart';

/// Service for tracking and syncing files
class FileSyncService {
  final SyncDatabase _db;
  final String _deviceId;

  FileSyncService(this._db, this._deviceId);

  /// Calculate SHA-256 hash of a file
  Future<String> calculateFileHash(File file) async {
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Register a file for syncing
  Future<SyncableFile> registerFile({
    required String relativePath,
    required File file,
  }) async {
    final contentHash = await calculateFileHash(file);
    final stat = await file.stat();
    final now = DateTime.now();

    // Check if file already exists in database
    final existing = await _db.getFileByPath(relativePath);

    if (existing != null) {
      // Update existing file
      final updated = SyncableFilesCompanion(
        id: Value(existing.id),
        relativePath: Value(relativePath),
        contentHash: Value(contentHash),
        sizeBytes: Value(stat.size),
        createdAt: Value(existing.createdAt),
        updatedAt: Value(now),
        deletedAt: const Value(null),
        deviceId: Value(_deviceId),
        syncVersion: Value(existing.syncVersion + 1),
      );

      await _db.upsertFile(updated);
      return (await _db.getFile(existing.id))!;
    } else {
      // Create new file record
      final id = const Uuid().v4();
      final newFile = SyncableFilesCompanion(
        id: Value(id),
        relativePath: Value(relativePath),
        contentHash: Value(contentHash),
        sizeBytes: Value(stat.size),
        createdAt: Value(now),
        updatedAt: Value(now),
        deletedAt: const Value(null),
        deviceId: Value(_deviceId),
        syncVersion: const Value(1),
      );

      await _db.upsertFile(newFile);
      return (await _db.getFile(id))!;
    }
  }

  /// Mark a file as deleted (soft delete)
  Future<void> markFileDeleted(String relativePath) async {
    final existing = await _db.getFileByPath(relativePath);
    if (existing == null) return;

    final updated = SyncableFilesCompanion(
      id: Value(existing.id),
      relativePath: Value(existing.relativePath),
      contentHash: Value(existing.contentHash),
      sizeBytes: Value(existing.sizeBytes),
      createdAt: Value(existing.createdAt),
      updatedAt: Value(DateTime.now()),
      deletedAt: Value(DateTime.now()),
      deviceId: Value(_deviceId),
      syncVersion: Value(existing.syncVersion + 1),
    );

    await _db.upsertFile(updated);
  }

  /// Check if a file has changed based on content hash
  Future<bool> hasFileChanged(String relativePath, File file) async {
    final existing = await _db.getFileByPath(relativePath);
    if (existing == null) return true;

    final currentHash = await calculateFileHash(file);
    return currentHash != existing.contentHash;
  }

  /// Get all files that need to be synced (modified since last sync)
  Future<List<SyncableFile>> getFilesToSync(DateTime since) async {
    final allFiles = await _db.getAllFiles();
    return allFiles
        .where((f) => f.updatedAt.isAfter(since))
        .toList();
  }

  /// Get file metadata by ID
  Future<SyncableFile?> getFileMetadata(String id) {
    return _db.getFile(id);
  }

  /// Get all tracked files
  Future<List<SyncableFile>> getAllFiles() {
    return _db.getAllFiles();
  }

  /// Update file metadata from remote
  Future<void> updateFromRemote(SyncableFile remoteFile) async {
    final local = await _db.getFile(remoteFile.id);

    if (local == null) {
      // New file from remote
      await _db.upsertFile(SyncableFilesCompanion(
        id: Value(remoteFile.id),
        relativePath: Value(remoteFile.relativePath),
        contentHash: Value(remoteFile.contentHash),
        sizeBytes: Value(remoteFile.sizeBytes),
        createdAt: Value(remoteFile.createdAt),
        updatedAt: Value(remoteFile.updatedAt),
        deletedAt: Value(remoteFile.deletedAt),
        deviceId: Value(remoteFile.deviceId),
        syncVersion: Value(remoteFile.syncVersion),
      ));
    } else {
      // Check for conflicts
      if (remoteFile.syncVersion > local.syncVersion ||
          (remoteFile.syncVersion == local.syncVersion &&
              remoteFile.updatedAt.isAfter(local.updatedAt))) {
        // Remote is newer, update local
        await _db.upsertFile(SyncableFilesCompanion(
          id: Value(remoteFile.id),
          relativePath: Value(remoteFile.relativePath),
          contentHash: Value(remoteFile.contentHash),
          sizeBytes: Value(remoteFile.sizeBytes),
          createdAt: Value(remoteFile.createdAt),
          updatedAt: Value(remoteFile.updatedAt),
          deletedAt: Value(remoteFile.deletedAt),
          deviceId: Value(remoteFile.deviceId),
          syncVersion: Value(remoteFile.syncVersion),
        ));
      }
    }
  }
}
