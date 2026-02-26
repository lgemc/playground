import 'dart:async';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/app_bus.dart';
import '../core/app_event.dart';
import 'queue_config.dart';
import 'queue_message.dart';

/// Callback type for queue consumers
typedef QueueConsumerCallback = Future<bool> Function(QueueMessage message);

/// Represents a subscriber to a queue
class _QueueSubscriber {
  final String id;
  final String queueId;
  final QueueConsumerCallback callback;
  final String? name;

  _QueueSubscriber({
    required this.id,
    required this.queueId,
    required this.callback,
    this.name,
  });
}

/// Service that manages message queues.
/// Routes events from AppBus to specific queues based on configuration.
/// Provides RabbitMQ-like message consumption with acknowledgment.
class QueueService {
  static QueueService? _instance;
  static QueueService get instance => _instance ??= QueueService._();

  QueueService._();

  Database? _database;
  String? _busSubscriptionId;
  final Map<String, List<_QueueSubscriber>> _subscribers = {};
  final StreamController<QueueMessage> _messageStream =
      StreamController<QueueMessage>.broadcast();

  /// Stream of all new messages (for monitoring)
  Stream<QueueMessage> get messageStream => _messageStream.stream;

  /// Initialize the queue service and database
  Future<void> init() async {
    if (_database != null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = '${appDir.path}/data/queues.db';

    _database = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE queue_messages (
            id TEXT PRIMARY KEY,
            queue_id TEXT NOT NULL,
            event_type TEXT NOT NULL,
            app_id TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            payload TEXT NOT NULL,
            delivery_count INTEGER DEFAULT 0,
            last_delivered_at INTEGER,
            locked_by TEXT,
            lock_expires_at INTEGER,
            visible_after INTEGER
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_queue_id ON queue_messages(queue_id)');
        await db.execute(
            'CREATE INDEX idx_event_type ON queue_messages(event_type)');
        await db.execute(
            'CREATE INDEX idx_timestamp ON queue_messages(timestamp DESC)');
        await db.execute(
            'CREATE INDEX idx_locked_by ON queue_messages(locked_by)');
        await db.execute(
            'CREATE INDEX idx_lock_expires ON queue_messages(lock_expires_at)');
        await db.execute(
            'CREATE INDEX idx_visible_after ON queue_messages(visible_after)');

        // Dead Letter Queue table
        await db.execute('''
          CREATE TABLE dlq_messages (
            id TEXT PRIMARY KEY,
            queue_id TEXT NOT NULL,
            event_type TEXT NOT NULL,
            app_id TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            payload TEXT NOT NULL,
            delivery_count INTEGER DEFAULT 0,
            last_delivered_at INTEGER,
            moved_to_dlq_at INTEGER NOT NULL,
            error_reason TEXT
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_dlq_queue_id ON dlq_messages(queue_id)');
        await db.execute(
            'CREATE INDEX idx_dlq_moved_at ON dlq_messages(moved_to_dlq_at DESC)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE queue_messages ADD COLUMN visible_after INTEGER');
          await db.execute(
              'CREATE INDEX idx_visible_after ON queue_messages(visible_after)');
          await db.execute('''
            CREATE TABLE dlq_messages (
              id TEXT PRIMARY KEY,
              queue_id TEXT NOT NULL,
              event_type TEXT NOT NULL,
              app_id TEXT NOT NULL,
              timestamp INTEGER NOT NULL,
              payload TEXT NOT NULL,
              delivery_count INTEGER DEFAULT 0,
              last_delivered_at INTEGER,
              moved_to_dlq_at INTEGER NOT NULL,
              error_reason TEXT
            )
          ''');
          await db.execute(
              'CREATE INDEX idx_dlq_queue_id ON dlq_messages(queue_id)');
          await db.execute(
              'CREATE INDEX idx_dlq_moved_at ON dlq_messages(moved_to_dlq_at DESC)');
        }
      },
    );

    // Subscribe to all events from the AppBus
    _busSubscriptionId = AppBus.instance.subscribe(
      id: 'queue_service',
      eventTypes: ['*'],
      callback: _handleBusEvent,
      name: 'Queue Service',
    );
  }

  /// Handle incoming events from the AppBus
  Future<void> _handleBusEvent(AppEvent event) async {
    final matchingQueues = QueueConfigs.getMatchingQueues(event.type);

    for (final queueConfig in matchingQueues) {
      await _enqueueMessage(
        queueId: queueConfig.id,
        eventType: event.type,
        appId: event.appId,
        payload: event.metadata,
      );
    }
  }

  /// Add a message to a queue
  Future<QueueMessage> _enqueueMessage({
    required String queueId,
    required String eventType,
    required String appId,
    Map<String, dynamic> payload = const {},
  }) async {
    await _ensureInitialized();

    final message = QueueMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}_${queueId}_${appId.hashCode}',
      queueId: queueId,
      eventType: eventType,
      appId: appId,
      timestamp: DateTime.now(),
      payload: payload,
    );

    await _database!.insert(
      'queue_messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    _messageStream.add(message);

    // Notify subscribers that a new message is available
    _notifySubscribers(queueId);

    return message;
  }

  /// Manually enqueue a message (for external use)
  Future<QueueMessage> enqueue({
    required String queueId,
    required String eventType,
    required String appId,
    Map<String, dynamic> payload = const {},
  }) async {
    final config = QueueConfigs.getById(queueId);
    if (config == null) {
      throw ArgumentError('Unknown queue: $queueId');
    }
    return _enqueueMessage(
      queueId: queueId,
      eventType: eventType,
      appId: appId,
      payload: payload,
    );
  }

  /// Subscribe to a queue for message consumption
  /// Returns a subscription ID that can be used to unsubscribe
  String subscribe({
    required String id,
    required String queueId,
    required QueueConsumerCallback callback,
    String? name,
  }) {
    _subscribers.putIfAbsent(queueId, () => []);
    _subscribers[queueId]!.add(_QueueSubscriber(
      id: id,
      queueId: queueId,
      callback: callback,
      name: name,
    ));
    return id;
  }

  /// Unsubscribe from a queue
  void unsubscribe(String subscriptionId) {
    for (final subscribers in _subscribers.values) {
      subscribers.removeWhere((s) => s.id == subscriptionId);
    }
  }

  /// Get the next available message from a queue and lock it
  /// Returns null if no messages are available
  Future<QueueMessage?> fetchMessage({
    required String queueId,
    required String consumerId,
    int? lockTimeoutSeconds,
  }) async {
    await _ensureInitialized();

    final config = QueueConfigs.getById(queueId);
    final timeout = lockTimeoutSeconds ?? config?.lockTimeoutSeconds ?? 30;
    final now = DateTime.now();
    final lockExpires = now.add(Duration(seconds: timeout));

    // First, release any expired locks
    await _releaseExpiredLocks();

    // Find an available message (not locked, lock expired, and visible)
    List<Map<String, dynamic>> results;
    try {
      results = await _database!.query(
        'queue_messages',
        where:
            'queue_id = ? AND (locked_by IS NULL OR lock_expires_at < ?) AND (visible_after IS NULL OR visible_after <= ?)',
        whereArgs: [queueId, now.millisecondsSinceEpoch, now.millisecondsSinceEpoch],
        orderBy: 'timestamp ASC',
        limit: 1,
      );
    } catch (e) {
      // Handle "Row too big to fit into CursorWindow" error
      if (e.toString().contains('Row too big') || e.toString().contains('CursorWindow')) {
        print('[QueueService] Detected oversized message in queue $queueId, moving to DLQ');
        // Move oversized message to DLQ using raw SQL (to avoid reading the large payload)
        await _database!.execute('''
          INSERT INTO dlq_messages
          SELECT id, queue_id, event_type, app_id, timestamp, '', delivery_count, last_delivered_at, ?, 'Message too large (>2MB)'
          FROM queue_messages
          WHERE queue_id = ? AND (locked_by IS NULL OR lock_expires_at < ?) AND (visible_after IS NULL OR visible_after <= ?)
          ORDER BY timestamp ASC
          LIMIT 1
        ''', [now.millisecondsSinceEpoch, queueId, now.millisecondsSinceEpoch, now.millisecondsSinceEpoch]);

        // Delete the oversized message from queue
        await _database!.execute('''
          DELETE FROM queue_messages
          WHERE id = (
            SELECT id FROM queue_messages
            WHERE queue_id = ? AND (locked_by IS NULL OR lock_expires_at < ?)
            ORDER BY timestamp ASC
            LIMIT 1
          )
        ''', [queueId, now.millisecondsSinceEpoch]);

        // Retry with next message
        return fetchMessage(queueId: queueId, consumerId: consumerId, lockTimeoutSeconds: lockTimeoutSeconds);
      }
      rethrow;
    }

    if (results.isEmpty) return null;

    final message = QueueMessage.fromMap(results.first);

    // Lock the message
    await _database!.update(
      'queue_messages',
      {
        'locked_by': consumerId,
        'lock_expires_at': lockExpires.millisecondsSinceEpoch,
        'last_delivered_at': now.millisecondsSinceEpoch,
        'delivery_count': message.deliveryCount + 1,
      },
      where: 'id = ?',
      whereArgs: [message.id],
    );

    return message.copyWith(
      lockedBy: consumerId,
      lockExpiresAt: lockExpires,
      lastDeliveredAt: now,
      deliveryCount: message.deliveryCount + 1,
    );
  }

  /// Acknowledge successful processing of a message (removes it from queue)
  Future<bool> acknowledge(String messageId) async {
    await _ensureInitialized();

    print('[QueueService] Acknowledging message: $messageId');
    final count = await _database!.delete(
      'queue_messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );

    print('[QueueService] Acknowledge result: deleted $count rows');
    return count > 0;
  }

  /// Reject a message with exponential backoff retry.
  /// If max retries exceeded, message is moved to DLQ.
  /// [errorReason] is stored in DLQ for debugging.
  Future<void> reject(
    String messageId, {
    bool requeue = true,
    String? errorReason,
  }) async {
    await _ensureInitialized();

    final results = await _database!.query(
      'queue_messages',
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );

    if (results.isEmpty) return;

    final message = QueueMessage.fromMap(results.first);
    final config = QueueConfigs.getById(message.queueId);

    // Check if max retries exceeded
    if (config != null && message.deliveryCount >= config.maxRetries) {
      // Move to DLQ
      await _moveToDlq(message, errorReason);
      return;
    }

    if (!requeue) {
      // Explicitly not requeuing - move to DLQ
      await _moveToDlq(message, errorReason);
      return;
    }

    // Calculate backoff delay
    final delayMs = config?.getRetryDelayMs(message.deliveryCount) ?? 3000;
    final visibleAfter = DateTime.now().add(Duration(milliseconds: delayMs));

    // Release lock and set visibility delay
    await _database!.update(
      'queue_messages',
      {
        'locked_by': null,
        'lock_expires_at': null,
        'visible_after': visibleAfter.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Get all messages in a queue (for inspection/debugging)
  Future<List<QueueMessage>> getMessages({
    required String queueId,
    bool includeLockedMessages = true,
    int? limit,
    int offset = 0,
  }) async {
    await _ensureInitialized();

    String? where = 'queue_id = ?';
    final whereArgs = <dynamic>[queueId];

    if (!includeLockedMessages) {
      where += ' AND (locked_by IS NULL OR lock_expires_at < ?)';
      whereArgs.add(DateTime.now().millisecondsSinceEpoch);
    }

    final results = await _database!.query(
      'queue_messages',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp ASC',
      limit: limit,
      offset: offset,
    );

    return results.map((row) => QueueMessage.fromMap(row)).toList();
  }

  /// Get a specific message by ID
  Future<QueueMessage?> getMessage(String messageId) async {
    await _ensureInitialized();

    final results = await _database!.query(
      'queue_messages',
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return QueueMessage.fromMap(results.first);
  }

  /// Get metrics for a specific queue
  Future<QueueMetrics> getQueueMetrics(String queueId) async {
    await _ensureInitialized();

    final now = DateTime.now().millisecondsSinceEpoch;

    // Total messages
    final totalResult = await _database!.rawQuery(
      'SELECT COUNT(*) as count FROM queue_messages WHERE queue_id = ?',
      [queueId],
    );
    final totalCount = Sqflite.firstIntValue(totalResult) ?? 0;

    // Locked messages
    final lockedResult = await _database!.rawQuery(
      'SELECT COUNT(*) as count FROM queue_messages WHERE queue_id = ? AND locked_by IS NOT NULL AND lock_expires_at > ?',
      [queueId, now],
    );
    final lockedCount = Sqflite.firstIntValue(lockedResult) ?? 0;

    // Oldest message
    final oldestResult = await _database!.query(
      'queue_messages',
      columns: ['timestamp'],
      where: 'queue_id = ?',
      whereArgs: [queueId],
      orderBy: 'timestamp ASC',
      limit: 1,
    );
    final oldestTimestamp = oldestResult.isNotEmpty
        ? DateTime.fromMillisecondsSinceEpoch(
            oldestResult.first['timestamp'] as int)
        : null;

    // Newest message
    final newestResult = await _database!.query(
      'queue_messages',
      columns: ['timestamp'],
      where: 'queue_id = ?',
      whereArgs: [queueId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    final newestTimestamp = newestResult.isNotEmpty
        ? DateTime.fromMillisecondsSinceEpoch(
            newestResult.first['timestamp'] as int)
        : null;

    // Subscribers
    final subscribers = _subscribers[queueId] ?? [];

    return QueueMetrics(
      queueId: queueId,
      messageCount: totalCount,
      lockedCount: lockedCount,
      availableCount: totalCount - lockedCount,
      subscriberCount: subscribers.length,
      subscriberIds: subscribers.map((s) => s.id).toList(),
      oldestMessageAt: oldestTimestamp,
      newestMessageAt: newestTimestamp,
    );
  }

  /// Get metrics for all queues
  Future<Map<String, QueueMetrics>> getAllMetrics() async {
    final metrics = <String, QueueMetrics>{};

    for (final config in QueueConfigs.getEnabled()) {
      metrics[config.id] = await getQueueMetrics(config.id);
    }

    return metrics;
  }

  /// Get message count for a queue
  Future<int> getMessageCount(String queueId) async {
    await _ensureInitialized();

    final result = await _database!.rawQuery(
      'SELECT COUNT(*) as count FROM queue_messages WHERE queue_id = ?',
      [queueId],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Clear all messages from a queue
  Future<int> clearQueue(String queueId) async {
    await _ensureInitialized();

    return await _database!.delete(
      'queue_messages',
      where: 'queue_id = ?',
      whereArgs: [queueId],
    );
  }

  /// Release expired locks so messages can be redelivered
  Future<void> _releaseExpiredLocks() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await _database?.update(
      'queue_messages',
      {
        'locked_by': null,
        'lock_expires_at': null,
      },
      where: 'lock_expires_at IS NOT NULL AND lock_expires_at < ?',
      whereArgs: [now],
    );
  }

  /// Notify subscribers that new messages are available
  void _notifySubscribers(String queueId) {
    final subscribers = _subscribers[queueId];
    print('[QueueService] _notifySubscribers for queue: $queueId, subscribers: ${subscribers?.length ?? 0}');
    if (subscribers == null || subscribers.isEmpty) return;

    // Process messages for each subscriber asynchronously
    for (final subscriber in subscribers) {
      print('[QueueService] Notifying subscriber: ${subscriber.id}');
      _processMessagesForSubscriber(subscriber);
    }
  }

  /// Process available messages for a subscriber
  Future<void> _processMessagesForSubscriber(_QueueSubscriber subscriber) async {
    print('[QueueService] _processMessagesForSubscriber started for: ${subscriber.id}');
    final message = await fetchMessage(
      queueId: subscriber.queueId,
      consumerId: subscriber.id,
    );

    print('[QueueService] fetchMessage result: ${message?.id ?? 'null'}');
    if (message == null) {
      print('[QueueService] No message available for subscriber: ${subscriber.id}');
      return;
    }

    try {
      print('[QueueService] Calling callback for message: ${message.id}');
      final success = await subscriber.callback(message);
      print('[QueueService] Callback returned: $success');
      if (success) {
        await acknowledge(message.id);
      } else {
        await reject(message.id);
      }
    } catch (e) {
      print('[QueueService] Callback threw error: $e');
      await reject(message.id);
    }
  }

  Future<void> _ensureInitialized() async {
    if (_database == null) {
      await init();
    }
  }

  // ==================== Dead Letter Queue Methods ====================

  /// Move a message to the dead letter queue
  Future<void> _moveToDlq(QueueMessage message, String? errorReason) async {
    final now = DateTime.now();

    // Insert into DLQ
    await _database!.insert(
      'dlq_messages',
      {
        'id': message.id,
        'queue_id': message.queueId,
        'event_type': message.eventType,
        'app_id': message.appId,
        'timestamp': message.timestamp.millisecondsSinceEpoch,
        'payload': message.toMap()['payload'],
        'delivery_count': message.deliveryCount,
        'last_delivered_at': message.lastDeliveredAt?.millisecondsSinceEpoch,
        'moved_to_dlq_at': now.millisecondsSinceEpoch,
        'error_reason': errorReason,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Remove from main queue
    await _database!.delete(
      'queue_messages',
      where: 'id = ?',
      whereArgs: [message.id],
    );
  }

  /// Get all messages in the dead letter queue
  Future<List<DlqMessage>> getDlqMessages({
    String? queueId,
    int? limit,
    int offset = 0,
  }) async {
    await _ensureInitialized();

    String? where;
    List<dynamic>? whereArgs;

    if (queueId != null) {
      where = 'queue_id = ?';
      whereArgs = [queueId];
    }

    final results = await _database!.query(
      'dlq_messages',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'moved_to_dlq_at DESC',
      limit: limit,
      offset: offset,
    );

    return results.map((row) => DlqMessage.fromMap(row)).toList();
  }

  /// Get DLQ message count
  Future<int> getDlqMessageCount({String? queueId}) async {
    await _ensureInitialized();

    final query = queueId != null
        ? 'SELECT COUNT(*) as count FROM dlq_messages WHERE queue_id = ?'
        : 'SELECT COUNT(*) as count FROM dlq_messages';

    final result = await _database!.rawQuery(
      query,
      queueId != null ? [queueId] : null,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Retry a message from the DLQ (moves it back to the main queue)
  Future<bool> retryFromDlq(String messageId) async {
    await _ensureInitialized();

    final results = await _database!.query(
      'dlq_messages',
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );

    if (results.isEmpty) return false;

    final dlqMessage = DlqMessage.fromMap(results.first);

    // Re-insert into main queue with reset delivery count
    await _database!.insert(
      'queue_messages',
      {
        'id': '${DateTime.now().millisecondsSinceEpoch}_retry_${dlqMessage.id}',
        'queue_id': dlqMessage.queueId,
        'event_type': dlqMessage.eventType,
        'app_id': dlqMessage.appId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'payload': dlqMessage.toMap()['payload'],
        'delivery_count': 0,
        'last_delivered_at': null,
        'locked_by': null,
        'lock_expires_at': null,
        'visible_after': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Remove from DLQ
    await _database!.delete(
      'dlq_messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );

    // Notify subscribers
    _notifySubscribers(dlqMessage.queueId);

    return true;
  }

  /// Delete a message from the DLQ permanently
  Future<bool> deleteDlqMessage(String messageId) async {
    await _ensureInitialized();

    final count = await _database!.delete(
      'dlq_messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );

    return count > 0;
  }

  /// Clear all messages from a queue's DLQ
  Future<int> clearDlq({String? queueId}) async {
    await _ensureInitialized();

    if (queueId != null) {
      return await _database!.delete(
        'dlq_messages',
        where: 'queue_id = ?',
        whereArgs: [queueId],
      );
    }

    return await _database!.delete('dlq_messages');
  }

  /// Dispose resources
  Future<void> dispose() async {
    if (_busSubscriptionId != null) {
      AppBus.instance.unsubscribe(_busSubscriptionId!);
      _busSubscriptionId = null;
    }
    await _messageStream.close();
    await _database?.close();
    _database = null;
    _subscribers.clear();
  }

  /// Reset for testing
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }
}
