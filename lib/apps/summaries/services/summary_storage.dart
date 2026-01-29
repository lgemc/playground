import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/summary.dart';

/// Storage service for summaries
class SummaryStorage {
  static SummaryStorage? _instance;
  static SummaryStorage get instance => _instance ??= SummaryStorage._();

  SummaryStorage._();

  Database? _database;
  String? _dataDir;

  final _uuid = const Uuid();

  /// Initialize the storage (creates database and directories)
  Future<void> init() async {
    if (_database != null) return;

    final appDir = await getApplicationDocumentsDirectory();
    _dataDir = '${appDir.path}/data/summaries';

    // Create directories
    await Directory(_dataDir!).create(recursive: true);
    await Directory('$_dataDir/summaries').create(recursive: true);

    // Initialize database
    final dbPath = '$_dataDir/summaries.db';
    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE summaries (
            id TEXT PRIMARY KEY,
            file_id TEXT NOT NULL,
            file_name TEXT NOT NULL,
            file_path TEXT NOT NULL,
            summary_text TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            completed_at TEXT,
            error_message TEXT
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_file_id ON summaries(file_id)');
        await db.execute(
            'CREATE INDEX idx_status ON summaries(status)');
        await db.execute(
            'CREATE INDEX idx_created_at ON summaries(created_at DESC)');
      },
    );
  }

  /// Create a new summary (initially in pending state)
  Future<Summary> create({
    required String fileId,
    required String fileName,
    required String filePath,
  }) async {
    await _ensureInitialized();

    final summary = Summary(
      id: _uuid.v4(),
      fileId: fileId,
      fileName: fileName,
      filePath: filePath,
      summaryText: '',
      status: SummaryStatus.pending,
      createdAt: DateTime.now(),
    );

    await _database!.insert('summaries', summary.toMap());
    return summary;
  }

  /// Update a summary
  Future<void> update(Summary summary) async {
    await _ensureInitialized();

    await _database!.update(
      'summaries',
      summary.toMap(),
      where: 'id = ?',
      whereArgs: [summary.id],
    );

    // If completed, save summary text to markdown file
    if (summary.isCompleted && summary.summaryText.isNotEmpty) {
      await _saveSummaryFile(summary.id, summary.summaryText);
    }
  }

  /// Get a summary by ID
  Future<Summary?> get(String id) async {
    await _ensureInitialized();

    final results = await _database!.query(
      'summaries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (results.isEmpty) return null;

    final summary = Summary.fromMap(results.first);

    // Load summary text from file if completed
    if (summary.isCompleted) {
      final text = await _loadSummaryFile(summary.id);
      if (text != null) {
        return summary.copyWith(summaryText: text);
      }
    }

    return summary;
  }

  /// Get all summaries
  Future<List<Summary>> getAll({
    SummaryStatus? status,
    int? limit,
    int offset = 0,
  }) async {
    await _ensureInitialized();

    String? where;
    List<dynamic>? whereArgs;

    if (status != null) {
      where = 'status = ?';
      whereArgs = [status.name];
    }

    final results = await _database!.query(
      'summaries',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );

    final summaries = <Summary>[];
    for (final row in results) {
      final summary = Summary.fromMap(row);

      // Load summary text from file if completed
      if (summary.isCompleted) {
        final text = await _loadSummaryFile(summary.id);
        if (text != null) {
          summaries.add(summary.copyWith(summaryText: text));
          continue;
        }
      }

      summaries.add(summary);
    }

    return summaries;
  }

  /// Get summaries for a specific file
  Future<List<Summary>> getByFileId(String fileId) async {
    await _ensureInitialized();

    final results = await _database!.query(
      'summaries',
      where: 'file_id = ?',
      whereArgs: [fileId],
      orderBy: 'created_at DESC',
    );

    return results.map((row) => Summary.fromMap(row)).toList();
  }

  /// Delete a summary
  Future<void> delete(String id) async {
    await _ensureInitialized();

    await _database!.delete(
      'summaries',
      where: 'id = ?',
      whereArgs: [id],
    );

    // Delete summary file
    await _deleteSummaryFile(id);
  }

  /// Get count of summaries
  Future<int> getCount({SummaryStatus? status}) async {
    await _ensureInitialized();

    String query;
    List<dynamic>? args;

    if (status != null) {
      query = 'SELECT COUNT(*) as count FROM summaries WHERE status = ?';
      args = [status.name];
    } else {
      query = 'SELECT COUNT(*) as count FROM summaries';
    }

    final result = await _database!.rawQuery(query, args);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Save summary text to markdown file
  Future<void> _saveSummaryFile(String id, String text) async {
    final file = File('$_dataDir/summaries/$id.md');
    await file.writeAsString(text);
  }

  /// Load summary text from markdown file
  Future<String?> _loadSummaryFile(String id) async {
    try {
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
      final file = File('$_dataDir/summaries/$id.md');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore errors
    }
  }

  Future<void> _ensureInitialized() async {
    if (_database == null) {
      await init();
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _database?.close();
    _database = null;
  }

  /// Reset for testing
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }
}
