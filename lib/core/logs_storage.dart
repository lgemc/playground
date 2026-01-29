import 'dart:async';
import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'app_bus.dart';
import 'app_event.dart';
import '../services/logger.dart';

/// Represents a stored log entry
class LogEntry {
  final String id;
  final String appId;
  final String appName;
  final String message;
  final LogSeverity severity;
  final String eventType;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  LogEntry({
    required this.id,
    required this.appId,
    required this.appName,
    required this.message,
    required this.severity,
    required this.eventType,
    required this.timestamp,
    this.metadata = const {},
  });

  factory LogEntry.fromMap(Map<String, dynamic> map) {
    return LogEntry(
      id: map['id'] as String,
      appId: map['app_id'] as String,
      appName: map['app_name'] as String,
      message: map['message'] as String,
      severity: LogSeverityExtension.fromString(map['severity'] as String),
      eventType: map['event_type'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      metadata: map['metadata'] is String
          ? _parseMetadata(map['metadata'] as String)
          : (map['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'app_id': appId,
      'app_name': appName,
      'message': message,
      'severity': severity.name,
      'event_type': eventType,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'metadata': json.encode(metadata),
    };
  }

  static Map<String, dynamic> _parseMetadata(String jsonStr) {
    if (jsonStr.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(json.decode(jsonStr) as Map);
    } catch (_) {
      return {};
    }
  }
}

/// Service that stores logs from the AppBus into SQLite
class LogsStorage {
  static LogsStorage? _instance;
  static LogsStorage get instance => _instance ??= LogsStorage._();

  LogsStorage._();

  Database? _database;
  String? _subscriptionId;
  String? _streamCompleteSubscriptionId;
  final StreamController<LogEntry> _logStream =
      StreamController<LogEntry>.broadcast();

  /// Stream of new log entries (for real-time updates)
  Stream<LogEntry> get logStream => _logStream.stream;

  /// Initialize the log storage service
  Future<void> init() async {
    if (_database != null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = '${appDir.path}/data/logs.db';

    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE logs (
            id TEXT PRIMARY KEY,
            app_id TEXT NOT NULL,
            app_name TEXT NOT NULL,
            message TEXT NOT NULL,
            severity TEXT NOT NULL,
            event_type TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            metadata TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_logs_app_id ON logs(app_id)');
        await db.execute('CREATE INDEX idx_logs_severity ON logs(severity)');
        await db.execute('CREATE INDEX idx_logs_timestamp ON logs(timestamp DESC)');
        await db.execute('CREATE INDEX idx_logs_event_type ON logs(event_type)');
      },
    );

    // Subscribe to log events from the AppBus
    _subscriptionId = AppBus.instance.subscribe(
      id: 'logs_storage',
      eventTypes: ['log.*'],
      callback: _handleLogEvent,
      name: 'Logs Storage Service',
    );

    // Subscribe to stream completion events
    _streamCompleteSubscriptionId = AppBus.instance.subscribe(
      id: 'logs_storage_stream_complete',
      eventTypes: ['log.stream.complete'],
      callback: _handleStreamComplete,
      name: 'Logs Storage Stream Complete Handler',
    );
  }

  /// Handle incoming log events
  Future<bool> _handleLogEvent(AppEvent event) async {
    final metadata = event.metadata;

    final logEntry = LogEntry(
      id: event.id,
      appId: metadata['appId'] as String? ?? event.appId,
      appName: metadata['appName'] as String? ?? 'Unknown',
      message: metadata['message'] as String? ?? '',
      severity: LogSeverityExtension.fromString(
        metadata['severity'] as String? ?? 'info',
      ),
      eventType: metadata['eventType'] as String? ?? 'general',
      timestamp: event.timestamp,
      metadata: Map<String, dynamic>.from(metadata)
        ..remove('appId')
        ..remove('appName')
        ..remove('message')
        ..remove('severity')
        ..remove('eventType'),
    );

    await _storeLog(logEntry);
    _logStream.add(logEntry);

    return true;
  }

  /// Handle stream completion - update stored log with final message
  Future<bool> _handleStreamComplete(AppEvent event) async {
    final logId = event.metadata['streamLogId'] as String?;
    final finalMessage = event.metadata['finalMessage'] as String?;

    if (logId != null && finalMessage != null) {
      await _ensureInitialized();

      await _database!.update(
        'logs',
        {'message': finalMessage},
        where: 'id = ?',
        whereArgs: [logId],
      );

      // Notify listeners about the update
      final updated = await _getLogById(logId);
      if (updated != null) {
        _logStream.add(updated);
      }
    }

    return true;
  }

  /// Get a single log by ID
  Future<LogEntry?> _getLogById(String id) async {
    await _ensureInitialized();

    final results = await _database!.query(
      'logs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return LogEntry.fromMap(results.first);
  }

  /// Store a log entry in the database
  Future<void> _storeLog(LogEntry entry) async {
    await _ensureInitialized();

    await _database!.insert(
      'logs',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get logs with optional filtering
  Future<List<LogEntry>> getLogs({
    String? appId,
    LogSeverity? severity,
    String? eventType,
    DateTime? since,
    DateTime? until,
    String? searchQuery,
    int? limit,
    int offset = 0,
  }) async {
    await _ensureInitialized();

    final where = <String>[];
    final args = <dynamic>[];

    if (appId != null) {
      where.add('app_id = ?');
      args.add(appId);
    }

    if (severity != null) {
      where.add('severity = ?');
      args.add(severity.name);
    }

    if (eventType != null) {
      where.add('event_type = ?');
      args.add(eventType);
    }

    if (since != null) {
      where.add('timestamp >= ?');
      args.add(since.millisecondsSinceEpoch);
    }

    if (until != null) {
      where.add('timestamp <= ?');
      args.add(until.millisecondsSinceEpoch);
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      where.add('message LIKE ?');
      args.add('%$searchQuery%');
    }

    final results = await _database!.query(
      'logs',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );

    return results.map((row) => LogEntry.fromMap(row)).toList();
  }

  /// Get unique app IDs that have logs
  Future<List<String>> getAppIds() async {
    await _ensureInitialized();

    final results = await _database!.rawQuery(
      'SELECT DISTINCT app_id, app_name FROM logs ORDER BY app_name',
    );

    return results.map((row) => row['app_id'] as String).toList();
  }

  /// Get unique app names with their IDs
  Future<Map<String, String>> getApps() async {
    await _ensureInitialized();

    final results = await _database!.rawQuery(
      'SELECT DISTINCT app_id, app_name FROM logs ORDER BY app_name',
    );

    return {
      for (final row in results)
        row['app_id'] as String: row['app_name'] as String,
    };
  }

  /// Get log count with optional filtering
  Future<int> getLogCount({String? appId, LogSeverity? severity}) async {
    await _ensureInitialized();

    final where = <String>[];
    final args = <dynamic>[];

    if (appId != null) {
      where.add('app_id = ?');
      args.add(appId);
    }

    if (severity != null) {
      where.add('severity = ?');
      args.add(severity.name);
    }

    final result = await _database!.rawQuery(
      'SELECT COUNT(*) as count FROM logs${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}',
      args,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Clear old logs
  Future<int> clearLogs({DateTime? before, String? appId}) async {
    await _ensureInitialized();

    final where = <String>[];
    final args = <dynamic>[];

    if (before != null) {
      where.add('timestamp < ?');
      args.add(before.millisecondsSinceEpoch);
    }

    if (appId != null) {
      where.add('app_id = ?');
      args.add(appId);
    }

    return await _database!.delete(
      'logs',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
    );
  }

  Future<void> _ensureInitialized() async {
    if (_database == null) {
      await init();
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    if (_subscriptionId != null) {
      AppBus.instance.unsubscribe(_subscriptionId!);
      _subscriptionId = null;
    }
    if (_streamCompleteSubscriptionId != null) {
      AppBus.instance.unsubscribe(_streamCompleteSubscriptionId!);
      _streamCompleteSubscriptionId = null;
    }
    await _logStream.close();
    await _database?.close();
    _database = null;
  }

  /// Reset for testing
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }
}