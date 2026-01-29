import 'app_event.dart';

/// Callback type for event handlers
typedef EventCallback = Future<void> Function(AppEvent event);

/// Abstract class for background services that handle events.
/// Implement this to create a service that listens to specific event types.
abstract class EventHandler {
  /// Unique identifier for this handler
  String get id;

  /// Human-readable name for this handler
  String get name;

  /// List of event types this handler is interested in.
  /// Use '*' to listen to all events.
  /// Use prefix matching like 'note.*' to match all note events.
  List<String> get eventTypes;

  /// Called when an event matching the subscribed types is received.
  /// Return true if the event was handled successfully.
  Future<bool> handle(AppEvent event);

  /// Called when the handler is registered with the bus
  void onRegister() {}

  /// Called when the handler is unregistered
  void onUnregister() {}

  /// Checks if this handler should process the given event type
  bool matches(String eventType) {
    for (final pattern in eventTypes) {
      if (pattern == '*') return true;
      if (pattern == eventType) return true;
      if (pattern.endsWith('.*')) {
        final prefix = pattern.substring(0, pattern.length - 2);
        if (eventType.startsWith('$prefix.')) return true;
      }
    }
    return false;
  }
}

/// Simple handler that wraps a callback function
class CallbackEventHandler extends EventHandler {
  @override
  final String id;

  @override
  final String name;

  @override
  final List<String> eventTypes;

  final EventCallback _callback;

  CallbackEventHandler({
    required this.id,
    required this.name,
    required this.eventTypes,
    required EventCallback callback,
  }) : _callback = callback;

  @override
  Future<bool> handle(AppEvent event) async {
    try {
      await _callback(event);
      return true;
    } catch (_) {
      return false;
    }
  }
}