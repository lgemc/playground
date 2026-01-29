import 'dart:async';
import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'app_event.dart';
import 'event_handler.dart';

/// Central event bus for inter-app communication.
/// Similar to Kafka/RabbitMQ, provides pub/sub messaging with persistence.
class AppBus {
  static AppBus? _instance;
  static AppBus get instance => _instance ??= AppBus._();

  AppBus._();

  Database? _database;
  final Map<String, EventHandler> _handlers = {};
  final StreamController<AppEvent> _eventStream =
      StreamController<AppEvent>.broadcast();

  /// Stream of all events (for debugging/monitoring)
  Stream<AppEvent> get eventStream => _eventStream.stream;

  /// Initialize the event bus and database
  Future<void> init() async {
    if (_database != null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = '${appDir.path}/data/app_bus.db';

    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE events (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            app_id TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            metadata TEXT NOT NULL,
            processed INTEGER DEFAULT 0
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_events_type ON events(type)');
        await db.execute(
            'CREATE INDEX idx_events_app_id ON events(app_id)');
        await db.execute(
            'CREATE INDEX idx_events_timestamp ON events(timestamp DESC)');
      },
    );
  }

  /// Emit an event to the bus
  /// The event is stored in SQLite and dispatched to matching handlers
  Future<void> emit(AppEvent event) async {
    await _ensureInitialized();

    // Store event in database for traceability
    await _database!.insert(
      'events',
      {
        'id': event.id,
        'type': event.type,
        'app_id': event.appId,
        'timestamp': event.timestamp.millisecondsSinceEpoch,
        'metadata': json.encode(event.metadata),
        'processed': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Dispatch to stream
    _eventStream.add(event);

    // Dispatch to handlers
    await _dispatchToHandlers(event);
  }

  /// Register an event handler
  void registerHandler(EventHandler handler) {
    _handlers[handler.id] = handler;
    handler.onRegister();
  }

  /// Unregister an event handler
  void unregisterHandler(String handlerId) {
    final handler = _handlers.remove(handlerId);
    handler?.onUnregister();
  }

  /// Subscribe to specific event types with a callback
  /// Returns a subscription ID that can be used to unsubscribe
  String subscribe({
    required String id,
    required List<String> eventTypes,
    required EventCallback callback,
    String? name,
  }) {
    final handler = CallbackEventHandler(
      id: id,
      name: name ?? id,
      eventTypes: eventTypes,
      callback: callback,
    );
    registerHandler(handler);
    return id;
  }

  /// Unsubscribe from events
  void unsubscribe(String subscriptionId) {
    unregisterHandler(subscriptionId);
  }

  /// Get events from the database with optional filtering
  Future<List<AppEvent>> getEvents({
    String? type,
    String? appId,
    DateTime? since,
    DateTime? until,
    int? limit,
    int offset = 0,
  }) async {
    await _ensureInitialized();

    final where = <String>[];
    final args = <dynamic>[];

    if (type != null) {
      if (type.endsWith('.*')) {
        final prefix = type.substring(0, type.length - 1);
        where.add('type LIKE ?');
        args.add('$prefix%');
      } else {
        where.add('type = ?');
        args.add(type);
      }
    }

    if (appId != null) {
      where.add('app_id = ?');
      args.add(appId);
    }

    if (since != null) {
      where.add('timestamp >= ?');
      args.add(since.millisecondsSinceEpoch);
    }

    if (until != null) {
      where.add('timestamp <= ?');
      args.add(until.millisecondsSinceEpoch);
    }

    final results = await _database!.query(
      'events',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );

    return results.map((row) {
      return AppEvent(
        id: row['id'] as String,
        type: row['type'] as String,
        appId: row['app_id'] as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
        metadata: _parseMetadata(row['metadata'] as String),
      );
    }).toList();
  }

  /// Get a specific event by ID
  Future<AppEvent?> getEvent(String id) async {
    await _ensureInitialized();

    final results = await _database!.query(
      'events',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (results.isEmpty) return null;

    final row = results.first;
    return AppEvent(
      id: row['id'] as String,
      type: row['type'] as String,
      appId: row['app_id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
      metadata: _parseMetadata(row['metadata'] as String),
    );
  }

  /// Get event count with optional filtering
  Future<int> getEventCount({String? type, String? appId}) async {
    await _ensureInitialized();

    final where = <String>[];
    final args = <dynamic>[];

    if (type != null) {
      where.add('type = ?');
      args.add(type);
    }

    if (appId != null) {
      where.add('app_id = ?');
      args.add(appId);
    }

    final result = await _database!.rawQuery(
      'SELECT COUNT(*) as count FROM events${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}',
      args,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Clear old events (for maintenance)
  Future<int> clearEvents({DateTime? before, String? type}) async {
    await _ensureInitialized();

    final where = <String>[];
    final args = <dynamic>[];

    if (before != null) {
      where.add('timestamp < ?');
      args.add(before.millisecondsSinceEpoch);
    }

    if (type != null) {
      where.add('type = ?');
      args.add(type);
    }

    return await _database!.delete(
      'events',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
    );
  }

  /// Dispatch event to all matching handlers
  Future<void> _dispatchToHandlers(AppEvent event) async {
    for (final handler in _handlers.values) {
      if (handler.matches(event.type)) {
        try {
          final success = await handler.handle(event);
          if (success) {
            await _markEventProcessed(event.id);
          }
        } catch (e) {
          // Log error but don't fail other handlers
          // In production, this would go to a logging service
        }
      }
    }
  }

  Future<void> _markEventProcessed(String eventId) async {
    await _database?.update(
      'events',
      {'processed': 1},
      where: 'id = ?',
      whereArgs: [eventId],
    );
  }

  Future<void> _ensureInitialized() async {
    if (_database == null) {
      await init();
    }
  }

  Map<String, dynamic> _parseMetadata(String json) {
    try {
      return Map<String, dynamic>.from(
          jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return {};
    }
  }

  /// Close the database connection
  Future<void> dispose() async {
    await _eventStream.close();
    await _database?.close();
    _database = null;
    _handlers.clear();
  }

  /// Reset for testing
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }
}