import 'dart:io';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/summaries_database.dart';
import '../models/summary.dart' as model;
import '../../../core/sync/services/device_id_service.dart';

/// V2 storage service using Drift for sync support
class SummaryStorageV2 {
  static SummaryStorageV2? _instance;
  static SummaryStorageV2 get instance => _instance ??= SummaryStorageV2._();

  SummaryStorageV2._();

  final _database = SummariesDatabase();
  final _uuid = const Uuid();
  String? _dataDir;

  /// Initialize the storage
  Future<void> init() async {
    // Data directory is known from database location
    // The database is already initialized via LazyDatabase
    _dataDir = await _getDatabasePath();
    await Directory('$_dataDir/summaries').create(recursive: true);
  }

  Future<String> _getDatabasePath() async {
    // Get the database directory from the connection
    final result = await _database.customSelect('PRAGMA database_list').get();
    if (result.isNotEmpty) {
      final path = result.first.data['file'] as String?;
      if (path != null) {
        return File(path).parent.path;
      }
    }
    // Fallback
    return '';
  }

  /// Create a new summary (initially in pending state)
  Future<model.Summary> create({
    required String fileId,
    required String fileName,
    required String filePath,
  }) async {
    final now = DateTime.now();
    final deviceId = await DeviceIdService.instance.getDeviceId();

    final id = _uuid.v4();
    await _database.insertSummary(
      SummariesCompanion.insert(
        id: id,
        fileId: fileId,
        fileName: fileName,
        filePath: filePath,
        summaryText: const Value(''),
        status: model.SummaryStatus.pending.name,
        createdAt: now,
        updatedAt: now,
        deviceId: deviceId,
        syncVersion: const Value(1),
      ),
    );

    return model.Summary(
      id: id,
      fileId: fileId,
      fileName: fileName,
      filePath: filePath,
      summaryText: '',
      status: model.SummaryStatus.pending,
      createdAt: now,
    );
  }

  /// Update a summary
  Future<void> update(model.Summary summary) async {
    final deviceId = await DeviceIdService.instance.getDeviceId();
    final existing = await _database.getSummary(summary.id);
    if (existing == null) return;

    await _database.updateSummary(
      summary.id,
      SummariesCompanion(
        fileId: Value(summary.fileId),
        fileName: Value(summary.fileName),
        filePath: Value(summary.filePath),
        summaryText: Value(summary.summaryText),
        status: Value(summary.status.name),
        completedAt: Value(summary.completedAt),
        errorMessage: Value(summary.errorMessage),
        updatedAt: Value(DateTime.now()),
        deviceId: Value(deviceId),
        syncVersion: Value(existing.syncVersion + 1),
      ),
    );

    // If completed, save summary text to markdown file
    if (summary.isCompleted && summary.summaryText.isNotEmpty) {
      await _saveSummaryFile(summary.id, summary.summaryText);
    }
  }

  /// Get a summary by ID
  Future<model.Summary?> get(String id) async {
    final summary = await _database.getSummary(id);
    if (summary == null) return null;

    return _toModel(summary);
  }

  /// Get all summaries
  Future<List<model.Summary>> getAll({
    model.SummaryStatus? status,
    int? limit,
    int offset = 0,
  }) async {
    final summaries = await _database.getAllSummaries(
      status: status?.name,
    );

    final results = <model.Summary>[];
    for (final summary in summaries) {
      results.add(await _toModel(summary));
    }

    // Apply pagination manually
    if (offset > 0 || limit != null) {
      final end = limit != null ? offset + limit : results.length;
      return results.sublist(
        offset.clamp(0, results.length),
        end.clamp(0, results.length),
      );
    }

    return results;
  }

  /// Get summaries for a specific file
  Future<List<model.Summary>> getByFileId(String fileId) async {
    final summaries = await _database.getSummariesByFileId(fileId);
    final results = <model.Summary>[];
    for (final summary in summaries) {
      results.add(await _toModel(summary));
    }
    return results;
  }

  /// Delete a summary
  Future<void> delete(String id) async {
    final deviceId = await DeviceIdService.instance.getDeviceId();
    await _database.softDeleteSummary(id, deviceId);
    await _deleteSummaryFile(id);
  }

  /// Get count of summaries
  Future<int> getCount({model.SummaryStatus? status}) async {
    return _database.getCount(status: status?.name);
  }

  /// Convert database entity to model
  Future<model.Summary> _toModel(Summary summary) async {
    var summaryText = summary.summaryText;

    // Load summary text from file if completed
    final status = model.SummaryStatus.values.firstWhere(
      (s) => s.name == summary.status,
      orElse: () => model.SummaryStatus.pending,
    );

    if (status == model.SummaryStatus.completed) {
      final fileText = await _loadSummaryFile(summary.id);
      if (fileText != null) {
        summaryText = fileText;
      }
    }

    return model.Summary(
      id: summary.id,
      fileId: summary.fileId,
      fileName: summary.fileName,
      filePath: summary.filePath,
      summaryText: summaryText,
      status: status,
      createdAt: summary.createdAt,
      completedAt: summary.completedAt,
      errorMessage: summary.errorMessage,
    );
  }

  /// Save summary text to markdown file
  Future<void> _saveSummaryFile(String id, String text) async {
    await _ensureDataDir();
    final file = File('$_dataDir/summaries/$id.md');
    await file.writeAsString(text);
  }

  /// Load summary text from markdown file
  Future<String?> _loadSummaryFile(String id) async {
    try {
      await _ensureDataDir();
      final file = File('$_dataDir/summaries/$id.md');
      if (await file.exists()) {
        return await file.readAsString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Delete summary markdown file
  Future<void> _deleteSummaryFile(String id) async {
    try {
      await _ensureDataDir();
      final file = File('$_dataDir/summaries/$id.md');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore errors
    }
  }

  Future<void> _ensureDataDir() async {
    if (_dataDir == null) {
      await init();
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _database.close();
  }

  /// Reset for testing
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }
}
