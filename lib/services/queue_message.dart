import 'dart:convert';

/// Represents a message stored in a queue.
/// Messages persist until successfully processed and acknowledged.
class QueueMessage {
  /// Unique identifier for this message
  final String id;

  /// The queue this message belongs to
  final String queueId;

  /// Original event type that triggered this message
  final String eventType;

  /// ID of the app that emitted the original event
  final String appId;

  /// When the message was created
  final DateTime timestamp;

  /// Message payload data
  final Map<String, dynamic> payload;

  /// Number of times this message has been delivered
  final int deliveryCount;

  /// When this message was last delivered to a consumer
  final DateTime? lastDeliveredAt;

  /// ID of the consumer currently processing this message (if any)
  final String? lockedBy;

  /// When the lock expires (message can be redelivered after this)
  final DateTime? lockExpiresAt;

  /// When this message becomes visible for processing (for retry delays)
  final DateTime? visibleAfter;

  QueueMessage({
    required this.id,
    required this.queueId,
    required this.eventType,
    required this.appId,
    required this.timestamp,
    this.payload = const {},
    this.deliveryCount = 0,
    this.lastDeliveredAt,
    this.lockedBy,
    this.lockExpiresAt,
    this.visibleAfter,
  });

  /// Create from database row
  factory QueueMessage.fromMap(Map<String, dynamic> map) {
    return QueueMessage(
      id: map['id'] as String,
      queueId: map['queue_id'] as String,
      eventType: map['event_type'] as String,
      appId: map['app_id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      payload: _parsePayload(map['payload']),
      deliveryCount: map['delivery_count'] as int? ?? 0,
      lastDeliveredAt: map['last_delivered_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_delivered_at'] as int)
          : null,
      lockedBy: map['locked_by'] as String?,
      lockExpiresAt: map['lock_expires_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lock_expires_at'] as int)
          : null,
      visibleAfter: map['visible_after'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['visible_after'] as int)
          : null,
    );
  }

  /// Convert to database row
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'queue_id': queueId,
      'event_type': eventType,
      'app_id': appId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'payload': json.encode(payload),
      'delivery_count': deliveryCount,
      'last_delivered_at': lastDeliveredAt?.millisecondsSinceEpoch,
      'locked_by': lockedBy,
      'lock_expires_at': lockExpiresAt?.millisecondsSinceEpoch,
      'visible_after': visibleAfter?.millisecondsSinceEpoch,
    };
  }

  static Map<String, dynamic> _parsePayload(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      try {
        return Map<String, dynamic>.from(json.decode(value) as Map);
      } catch (_) {
        return {};
      }
    }
    return {};
  }

  QueueMessage copyWith({
    String? id,
    String? queueId,
    String? eventType,
    String? appId,
    DateTime? timestamp,
    Map<String, dynamic>? payload,
    int? deliveryCount,
    DateTime? lastDeliveredAt,
    String? lockedBy,
    DateTime? lockExpiresAt,
    DateTime? visibleAfter,
  }) {
    return QueueMessage(
      id: id ?? this.id,
      queueId: queueId ?? this.queueId,
      eventType: eventType ?? this.eventType,
      appId: appId ?? this.appId,
      timestamp: timestamp ?? this.timestamp,
      payload: payload ?? this.payload,
      deliveryCount: deliveryCount ?? this.deliveryCount,
      lastDeliveredAt: lastDeliveredAt ?? this.lastDeliveredAt,
      lockedBy: lockedBy ?? this.lockedBy,
      lockExpiresAt: lockExpiresAt ?? this.lockExpiresAt,
      visibleAfter: visibleAfter ?? this.visibleAfter,
    );
  }

  @override
  String toString() {
    return 'QueueMessage(id: $id, queue: $queueId, eventType: $eventType, deliveryCount: $deliveryCount)';
  }
}

/// Represents a message in the Dead Letter Queue.
/// These are messages that failed processing after all retry attempts.
class DlqMessage {
  final String id;
  final String queueId;
  final String eventType;
  final String appId;
  final DateTime timestamp;
  final Map<String, dynamic> payload;
  final int deliveryCount;
  final DateTime? lastDeliveredAt;
  final DateTime movedToDlqAt;
  final String? errorReason;

  DlqMessage({
    required this.id,
    required this.queueId,
    required this.eventType,
    required this.appId,
    required this.timestamp,
    this.payload = const {},
    this.deliveryCount = 0,
    this.lastDeliveredAt,
    required this.movedToDlqAt,
    this.errorReason,
  });

  factory DlqMessage.fromMap(Map<String, dynamic> map) {
    return DlqMessage(
      id: map['id'] as String,
      queueId: map['queue_id'] as String,
      eventType: map['event_type'] as String,
      appId: map['app_id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      payload: _parsePayload(map['payload']),
      deliveryCount: map['delivery_count'] as int? ?? 0,
      lastDeliveredAt: map['last_delivered_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_delivered_at'] as int)
          : null,
      movedToDlqAt:
          DateTime.fromMillisecondsSinceEpoch(map['moved_to_dlq_at'] as int),
      errorReason: map['error_reason'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'queue_id': queueId,
      'event_type': eventType,
      'app_id': appId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'payload': json.encode(payload),
      'delivery_count': deliveryCount,
      'last_delivered_at': lastDeliveredAt?.millisecondsSinceEpoch,
      'moved_to_dlq_at': movedToDlqAt.millisecondsSinceEpoch,
      'error_reason': errorReason,
    };
  }

  static Map<String, dynamic> _parsePayload(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      try {
        return Map<String, dynamic>.from(json.decode(value) as Map);
      } catch (_) {
        return {};
      }
    }
    return {};
  }

  @override
  String toString() {
    return 'DlqMessage(id: $id, queue: $queueId, eventType: $eventType, deliveryCount: $deliveryCount, error: $errorReason)';
  }
}
