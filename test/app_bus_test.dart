import 'package:flutter_test/flutter_test.dart';
import 'package:playground/core/app_event.dart';
import 'package:playground/core/event_handler.dart';

void main() {
  group('AppEvent', () {
    test('create generates unique id and timestamp', () {
      final event1 = AppEvent.create(
        type: 'test.event',
        appId: 'test_app',
      );
      final event2 = AppEvent.create(
        type: 'test.event',
        appId: 'test_app',
      );

      expect(event1.id, isNotEmpty);
      expect(event1.type, 'test.event');
      expect(event1.appId, 'test_app');
      expect(event1.timestamp, isNotNull);
      // IDs should be different (time-based)
      expect(event1.id != event2.id || event1.timestamp != event2.timestamp, true);
    });

    test('create with metadata stores metadata', () {
      final event = AppEvent.create(
        type: 'note.created',
        appId: 'notes',
        metadata: {'noteId': '123', 'title': 'Test Note'},
      );

      expect(event.metadata['noteId'], '123');
      expect(event.metadata['title'], 'Test Note');
    });

    test('toMap converts event to database format', () {
      final timestamp = DateTime(2024, 1, 15, 10, 30);
      final event = AppEvent(
        id: 'event_123',
        type: 'note.updated',
        appId: 'notes',
        timestamp: timestamp,
        metadata: {},
      );

      final map = event.toMap();
      expect(map['id'], 'event_123');
      expect(map['type'], 'note.updated');
      expect(map['app_id'], 'notes');
      expect(map['timestamp'], timestamp.millisecondsSinceEpoch);
    });

    test('copyWith creates modified copy', () {
      final original = AppEvent.create(
        type: 'note.created',
        appId: 'notes',
      );
      final modified = original.copyWith(type: 'note.updated');

      expect(modified.type, 'note.updated');
      expect(modified.id, original.id);
      expect(modified.appId, original.appId);
    });

    test('toString returns readable format', () {
      final event = AppEvent.create(
        type: 'test.event',
        appId: 'test_app',
      );

      expect(event.toString(), contains('AppEvent'));
      expect(event.toString(), contains('test.event'));
      expect(event.toString(), contains('test_app'));
    });
  });

  group('EventHandler', () {
    test('matches exact event type', () {
      final handler = CallbackEventHandler(
        id: 'handler1',
        name: 'Test Handler',
        eventTypes: ['note.created'],
        callback: (_) async {},
      );

      expect(handler.matches('note.created'), true);
      expect(handler.matches('note.updated'), false);
      expect(handler.matches('task.created'), false);
    });

    test('matches wildcard pattern *', () {
      final handler = CallbackEventHandler(
        id: 'handler1',
        name: 'All Events Handler',
        eventTypes: ['*'],
        callback: (_) async {},
      );

      expect(handler.matches('note.created'), true);
      expect(handler.matches('note.updated'), true);
      expect(handler.matches('task.created'), true);
      expect(handler.matches('anything'), true);
    });

    test('matches prefix pattern with .*', () {
      final handler = CallbackEventHandler(
        id: 'handler1',
        name: 'Note Events Handler',
        eventTypes: ['note.*'],
        callback: (_) async {},
      );

      expect(handler.matches('note.created'), true);
      expect(handler.matches('note.updated'), true);
      expect(handler.matches('note.deleted'), true);
      expect(handler.matches('task.created'), false);
      expect(handler.matches('notes.created'), false);
    });

    test('matches multiple event types', () {
      final handler = CallbackEventHandler(
        id: 'handler1',
        name: 'Multi Handler',
        eventTypes: ['note.created', 'task.created'],
        callback: (_) async {},
      );

      expect(handler.matches('note.created'), true);
      expect(handler.matches('task.created'), true);
      expect(handler.matches('note.updated'), false);
    });

    test('CallbackEventHandler executes callback', () async {
      var callCount = 0;
      AppEvent? receivedEvent;

      final handler = CallbackEventHandler(
        id: 'handler1',
        name: 'Test Handler',
        eventTypes: ['test.event'],
        callback: (event) async {
          callCount++;
          receivedEvent = event;
        },
      );

      final event = AppEvent.create(
        type: 'test.event',
        appId: 'test_app',
      );

      final result = await handler.handle(event);

      expect(result, true);
      expect(callCount, 1);
      expect(receivedEvent, event);
    });

    test('CallbackEventHandler returns false on error', () async {
      final handler = CallbackEventHandler(
        id: 'handler1',
        name: 'Failing Handler',
        eventTypes: ['test.event'],
        callback: (_) async {
          throw Exception('Handler error');
        },
      );

      final event = AppEvent.create(
        type: 'test.event',
        appId: 'test_app',
      );

      final result = await handler.handle(event);
      expect(result, false);
    });
  });

  group('Custom EventHandler', () {
    test('abstract handler can be extended', () async {
      final handler = _TestEventHandler();

      expect(handler.id, 'test_handler');
      expect(handler.name, 'Test Handler');
      expect(handler.eventTypes, ['test.*']);
      expect(handler.matches('test.event'), true);

      final event = AppEvent.create(
        type: 'test.event',
        appId: 'test_app',
      );

      final result = await handler.handle(event);
      expect(result, true);
      expect(handler.handledEvents, 1);
    });
  });
}

class _TestEventHandler extends EventHandler {
  int handledEvents = 0;

  @override
  String get id => 'test_handler';

  @override
  String get name => 'Test Handler';

  @override
  List<String> get eventTypes => ['test.*'];

  @override
  Future<bool> handle(AppEvent event) async {
    handledEvents++;
    return true;
  }
}
