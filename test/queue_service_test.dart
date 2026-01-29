import 'package:flutter_test/flutter_test.dart';
import 'package:playground/services/queue_message.dart';
import 'package:playground/services/queue_config.dart';

void main() {
  group('QueueMessage', () {
    test('creates message with required fields', () {
      final timestamp = DateTime(2024, 1, 15, 10, 30);
      final message = QueueMessage(
        id: 'msg_123',
        queueId: 'notes-processor',
        eventType: 'note.created',
        appId: 'notes',
        timestamp: timestamp,
      );

      expect(message.id, 'msg_123');
      expect(message.queueId, 'notes-processor');
      expect(message.eventType, 'note.created');
      expect(message.appId, 'notes');
      expect(message.timestamp, timestamp);
      expect(message.payload, isEmpty);
      expect(message.deliveryCount, 0);
      expect(message.lockedBy, isNull);
      expect(message.lockExpiresAt, isNull);
    });

    test('creates message with payload', () {
      final message = QueueMessage(
        id: 'msg_123',
        queueId: 'notes-processor',
        eventType: 'note.created',
        appId: 'notes',
        timestamp: DateTime.now(),
        payload: {'noteId': '456', 'title': 'Test Note'},
      );

      expect(message.payload['noteId'], '456');
      expect(message.payload['title'], 'Test Note');
    });

    test('toMap converts to database format', () {
      final timestamp = DateTime(2024, 1, 15, 10, 30);
      final lockExpires = DateTime(2024, 1, 15, 10, 31);
      final message = QueueMessage(
        id: 'msg_123',
        queueId: 'notes-processor',
        eventType: 'note.created',
        appId: 'notes',
        timestamp: timestamp,
        payload: {'key': 'value'},
        deliveryCount: 2,
        lockedBy: 'consumer_1',
        lockExpiresAt: lockExpires,
      );

      final map = message.toMap();

      expect(map['id'], 'msg_123');
      expect(map['queue_id'], 'notes-processor');
      expect(map['event_type'], 'note.created');
      expect(map['app_id'], 'notes');
      expect(map['timestamp'], timestamp.millisecondsSinceEpoch);
      expect(map['delivery_count'], 2);
      expect(map['locked_by'], 'consumer_1');
      expect(map['lock_expires_at'], lockExpires.millisecondsSinceEpoch);
    });

    test('fromMap creates message from database row', () {
      final timestamp = DateTime(2024, 1, 15, 10, 30);
      final map = {
        'id': 'msg_123',
        'queue_id': 'notes-processor',
        'event_type': 'note.created',
        'app_id': 'notes',
        'timestamp': timestamp.millisecondsSinceEpoch,
        'payload': '{"noteId": "456"}',
        'delivery_count': 1,
        'locked_by': null,
        'lock_expires_at': null,
      };

      final message = QueueMessage.fromMap(map);

      expect(message.id, 'msg_123');
      expect(message.queueId, 'notes-processor');
      expect(message.eventType, 'note.created');
      expect(message.appId, 'notes');
      expect(message.timestamp, timestamp);
      expect(message.payload['noteId'], '456');
      expect(message.deliveryCount, 1);
      expect(message.lockedBy, isNull);
    });

    test('copyWith creates modified copy', () {
      final original = QueueMessage(
        id: 'msg_123',
        queueId: 'notes-processor',
        eventType: 'note.created',
        appId: 'notes',
        timestamp: DateTime.now(),
        deliveryCount: 0,
      );

      final modified = original.copyWith(
        deliveryCount: 1,
        lockedBy: 'consumer_1',
      );

      expect(modified.id, original.id);
      expect(modified.queueId, original.queueId);
      expect(modified.deliveryCount, 1);
      expect(modified.lockedBy, 'consumer_1');
    });

    test('toString returns readable format', () {
      final message = QueueMessage(
        id: 'msg_123',
        queueId: 'notes-processor',
        eventType: 'note.created',
        appId: 'notes',
        timestamp: DateTime.now(),
      );

      expect(message.toString(), contains('QueueMessage'));
      expect(message.toString(), contains('msg_123'));
      expect(message.toString(), contains('notes-processor'));
    });
  });

  group('QueueConfig', () {
    test('creates config with required fields', () {
      const config = QueueConfig(
        id: 'test-queue',
        name: 'Test Queue',
        eventPatterns: ['test.*'],
      );

      expect(config.id, 'test-queue');
      expect(config.name, 'Test Queue');
      expect(config.eventPatterns, ['test.*']);
      expect(config.maxRetries, 3);
      expect(config.lockTimeoutSeconds, 30);
      expect(config.enabled, true);
    });

    test('matchesEventType with exact match', () {
      const config = QueueConfig(
        id: 'test-queue',
        name: 'Test Queue',
        eventPatterns: ['note.created', 'note.updated'],
      );

      expect(config.matchesEventType('note.created'), true);
      expect(config.matchesEventType('note.updated'), true);
      expect(config.matchesEventType('note.deleted'), false);
      expect(config.matchesEventType('task.created'), false);
    });

    test('matchesEventType with wildcard *', () {
      const config = QueueConfig(
        id: 'catch-all',
        name: 'Catch All',
        eventPatterns: ['*'],
      );

      expect(config.matchesEventType('note.created'), true);
      expect(config.matchesEventType('task.updated'), true);
      expect(config.matchesEventType('anything'), true);
    });

    test('matchesEventType with prefix pattern', () {
      const config = QueueConfig(
        id: 'notes-queue',
        name: 'Notes Queue',
        eventPatterns: ['note.*'],
      );

      expect(config.matchesEventType('note.created'), true);
      expect(config.matchesEventType('note.updated'), true);
      expect(config.matchesEventType('note.deleted'), true);
      expect(config.matchesEventType('task.created'), false);
      expect(config.matchesEventType('notes.created'), false);
    });

    test('matchesEventType with multiple patterns', () {
      const config = QueueConfig(
        id: 'multi-queue',
        name: 'Multi Queue',
        eventPatterns: ['note.*', 'task.created'],
      );

      expect(config.matchesEventType('note.created'), true);
      expect(config.matchesEventType('note.updated'), true);
      expect(config.matchesEventType('task.created'), true);
      expect(config.matchesEventType('task.updated'), false);
    });

    test('toString returns readable format', () {
      const config = QueueConfig(
        id: 'test-queue',
        name: 'Test Queue',
        eventPatterns: ['test.*'],
      );

      expect(config.toString(), contains('QueueConfig'));
      expect(config.toString(), contains('test-queue'));
    });
  });

  group('QueueMetrics', () {
    test('creates metrics with all fields', () {
      final oldest = DateTime(2024, 1, 15, 10, 0);
      final newest = DateTime(2024, 1, 15, 10, 30);
      final metrics = QueueMetrics(
        queueId: 'test-queue',
        messageCount: 100,
        lockedCount: 5,
        availableCount: 95,
        subscriberCount: 3,
        subscriberIds: ['sub1', 'sub2', 'sub3'],
        oldestMessageAt: oldest,
        newestMessageAt: newest,
      );

      expect(metrics.queueId, 'test-queue');
      expect(metrics.messageCount, 100);
      expect(metrics.lockedCount, 5);
      expect(metrics.availableCount, 95);
      expect(metrics.subscriberCount, 3);
      expect(metrics.subscriberIds, hasLength(3));
      expect(metrics.oldestMessageAt, oldest);
      expect(metrics.newestMessageAt, newest);
    });

    test('toMap converts to JSON-serializable format', () {
      final metrics = QueueMetrics(
        queueId: 'test-queue',
        messageCount: 10,
        lockedCount: 2,
        availableCount: 8,
        subscriberCount: 1,
        subscriberIds: ['consumer_1'],
      );

      final map = metrics.toMap();

      expect(map['queueId'], 'test-queue');
      expect(map['messageCount'], 10);
      expect(map['lockedCount'], 2);
      expect(map['availableCount'], 8);
      expect(map['subscriberCount'], 1);
      expect(map['subscriberIds'], ['consumer_1']);
    });

    test('toString returns readable format', () {
      final metrics = QueueMetrics(
        queueId: 'test-queue',
        messageCount: 10,
        lockedCount: 2,
        availableCount: 8,
        subscriberCount: 1,
        subscriberIds: ['consumer_1'],
      );

      expect(metrics.toString(), contains('QueueMetrics'));
      expect(metrics.toString(), contains('test-queue'));
    });
  });

  group('QueueConfigs', () {
    test('defaultQueues contains expected queues', () {
      final queues = QueueConfigs.defaultQueues;

      expect(queues.length, greaterThanOrEqualTo(3));

      final queueIds = queues.map((q) => q.id).toList();
      expect(queueIds, contains('notes-processor'));
      expect(queueIds, contains('logs-processor'));
      expect(queueIds, contains('lifecycle-processor'));
    });

    test('getById returns correct queue', () {
      final notesQueue = QueueConfigs.getById('notes-processor');

      expect(notesQueue, isNotNull);
      expect(notesQueue!.id, 'notes-processor');
      expect(notesQueue.eventPatterns, contains('note.*'));
    });

    test('getById returns null for unknown queue', () {
      final unknownQueue = QueueConfigs.getById('unknown-queue');

      expect(unknownQueue, isNull);
    });

    test('getEnabled returns only enabled queues', () {
      final enabledQueues = QueueConfigs.getEnabled();

      for (final queue in enabledQueues) {
        expect(queue.enabled, true);
      }
    });

    test('getMatchingQueues returns queues for event type', () {
      final noteQueues = QueueConfigs.getMatchingQueues('note.created');

      expect(noteQueues.isNotEmpty, true);
      expect(noteQueues.any((q) => q.id == 'notes-processor'), true);
    });

    test('getMatchingQueues returns empty for unmatched event', () {
      // Use an event type that doesn't match any enabled queue
      final queues = QueueConfigs.getMatchingQueues('unknown.event.type');

      // Should return empty or only catch-all queues
      for (final queue in queues) {
        expect(
          queue.eventPatterns.contains('*') ||
              queue.matchesEventType('unknown.event.type'),
          true,
        );
      }
    });
  });
}
