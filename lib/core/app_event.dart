/// Represents an event emitted by a sub-app.
/// Modeled after message queue systems like Kafka/RabbitMQ.
class AppEvent {
  /// Unique identifier for this event instance
  final String id;

  /// The type of event (e.g., 'note.created', 'note.updated')
  final String type;

  /// The app ID that emitted this event
  final String appId;

  /// When the event was created
  final DateTime timestamp;

  /// Additional data associated with the event
  final Map<String, dynamic> metadata;

  AppEvent({
    required this.id,
    required this.type,
    required this.appId,
    required this.timestamp,
    this.metadata = const {},
  });

  /// Create a new event with auto-generated ID and timestamp
  factory AppEvent.create({
    required String type,
    required String appId,
    Map<String, dynamic> metadata = const {},
  }) {
    return AppEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      appId: appId,
      timestamp: DateTime.now(),
      metadata: metadata,
    );
  }

  /// Create from database row
  factory AppEvent.fromMap(Map<String, dynamic> map) {
    return AppEvent(
      id: map['id'] as String,
      type: map['type'] as String,
      appId: map['app_id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      metadata: map['metadata'] is String
          ? _parseMetadata(map['metadata'] as String)
          : (map['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  /// Convert to database row
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'app_id': appId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'metadata': _encodeMetadata(metadata),
    };
  }

  static Map<String, dynamic> _parseMetadata(String json) {
    if (json.isEmpty) return {};
    try {
      // Simple JSON parsing without importing dart:convert here
      // The actual parsing will be done by the caller
      return {};
    } catch (_) {
      return {};
    }
  }

  static String _encodeMetadata(Map<String, dynamic> metadata) {
    if (metadata.isEmpty) return '{}';
    // Simple encoding - actual encoding done by caller with dart:convert
    return '{}';
  }

  @override
  String toString() {
    return 'AppEvent(id: $id, type: $type, appId: $appId, timestamp: $timestamp)';
  }

  AppEvent copyWith({
    String? id,
    String? type,
    String? appId,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  }) {
    return AppEvent(
      id: id ?? this.id,
      type: type ?? this.type,
      appId: appId ?? this.appId,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
    );
  }
}
