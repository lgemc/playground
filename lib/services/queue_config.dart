/// Configuration for a single queue.
/// Defines which event topics route to this queue.
class QueueConfig {
  /// Unique identifier for this queue
  final String id;

  /// Human-readable name
  final String name;

  /// Event type patterns this queue subscribes to.
  /// Supports wildcards: 'note.*' matches 'note.created', 'note.updated', etc.
  final List<String> eventPatterns;

  /// Maximum number of retry attempts before moving to dead letter queue
  final int maxRetries;

  /// Lock timeout in seconds (how long a consumer can hold a message)
  final int lockTimeoutSeconds;

  /// Whether this queue is enabled
  final bool enabled;

  /// Retry delays in ms for exponential backoff: [3s, 9s, 3min]
  final List<int> retryDelaysMs;

  const QueueConfig({
    required this.id,
    required this.name,
    required this.eventPatterns,
    this.maxRetries = 3,
    this.lockTimeoutSeconds = 900, // 15 minutes
    this.enabled = true,
    this.retryDelaysMs = const [3000, 9000, 180000], // 3s, 9s, 3min
  });

  /// Get retry delay for a given delivery count (1-indexed)
  int getRetryDelayMs(int deliveryCount) {
    if (retryDelaysMs.isEmpty) return 0;
    final index = (deliveryCount - 1).clamp(0, retryDelaysMs.length - 1);
    return retryDelaysMs[index];
  }

  /// Check if this queue should receive events of the given type
  bool matchesEventType(String eventType) {
    for (final pattern in eventPatterns) {
      if (pattern == '*') return true;
      if (pattern == eventType) return true;
      if (pattern.endsWith('.*')) {
        final prefix = pattern.substring(0, pattern.length - 2);
        if (eventType.startsWith('$prefix.')) return true;
      }
    }
    return false;
  }

  @override
  String toString() {
    return 'QueueConfig(id: $id, name: $name, patterns: $eventPatterns)';
  }
}

/// Metrics for a single queue
class QueueMetrics {
  /// Queue identifier
  final String queueId;

  /// Total messages in queue
  final int messageCount;

  /// Messages currently being processed
  final int lockedCount;

  /// Messages available for processing
  final int availableCount;

  /// Number of registered consumers
  final int subscriberCount;

  /// List of subscriber IDs
  final List<String> subscriberIds;

  /// Timestamp of the oldest message
  final DateTime? oldestMessageAt;

  /// Timestamp of the newest message
  final DateTime? newestMessageAt;

  const QueueMetrics({
    required this.queueId,
    required this.messageCount,
    required this.lockedCount,
    required this.availableCount,
    required this.subscriberCount,
    required this.subscriberIds,
    this.oldestMessageAt,
    this.newestMessageAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'queueId': queueId,
      'messageCount': messageCount,
      'lockedCount': lockedCount,
      'availableCount': availableCount,
      'subscriberCount': subscriberCount,
      'subscriberIds': subscriberIds,
      'oldestMessageAt': oldestMessageAt?.toIso8601String(),
      'newestMessageAt': newestMessageAt?.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'QueueMetrics(queue: $queueId, messages: $messageCount, available: $availableCount, subscribers: $subscriberCount)';
  }
}

/// Hardcoded queue configurations.
/// In a production system, these would come from a config file or database.
class QueueConfigs {
  static const List<QueueConfig> defaultQueues = [
    // Queue for note-related events
    QueueConfig(
      id: 'notes-processor',
      name: 'Notes Processor',
      eventPatterns: ['note.*'],
      maxRetries: 3,
      lockTimeoutSeconds: 30,
    ),
    // Queue for vocabulary events (word definition lookup)
    QueueConfig(
      id: 'vocabulary-definition',
      name: 'Vocabulary Definition Processor',
      eventPatterns: ['vocabulary.create', 'vocabulary.update'],
      maxRetries: 3,
      lockTimeoutSeconds: 60,
    ),
    // Queue for summary generation tasks
    QueueConfig(
      id: 'summary-processor',
      name: 'Summary Processor',
      eventPatterns: ['summary.create'],
      maxRetries: 3,
      lockTimeoutSeconds: 120, // Summaries can take longer
    ),
    // Queue for log events
    QueueConfig(
      id: 'logs-processor',
      name: 'Logs Processor',
      eventPatterns: ['log.*'],
      maxRetries: 5,
      lockTimeoutSeconds: 10,
    ),
    // Queue for app lifecycle events
    QueueConfig(
      id: 'lifecycle-processor',
      name: 'Lifecycle Processor',
      eventPatterns: ['app.opened', 'app.closed', 'app.initialized'],
      maxRetries: 3,
      lockTimeoutSeconds: 15,
    ),
    // Queue for chat title generation tasks
    QueueConfig(
      id: 'chat-title-generator',
      name: 'Chat Title Generator',
      eventPatterns: ['chat.title_generate'],
      maxRetries: 3,
      lockTimeoutSeconds: 60, // AI calls can take time
    ),
    // Queue for derivative artifact generation
    QueueConfig(
      id: 'derivative-processor',
      name: 'Derivative Processor',
      eventPatterns: ['derivative.create'],
      maxRetries: 3,
      lockTimeoutSeconds: 600, // Long timeout for video transcription
    ),
    // Queue for concept extraction from course content
    QueueConfig(
      id: 'concept-extraction',
      name: 'Concept Extraction Processor',
      eventPatterns: ['activity.extract_concepts', 'derivative.completed'],
      maxRetries: 3,
      lockTimeoutSeconds: 120, // AI concept extraction can take time
    ),
    // Catch-all queue for unmatched events (disabled by default)
    QueueConfig(
      id: 'default-queue',
      name: 'Default Queue',
      eventPatterns: ['*'],
      maxRetries: 3,
      lockTimeoutSeconds: 30,
      enabled: false,
    ),
  ];

  /// Get queue config by ID
  static QueueConfig? getById(String id) {
    try {
      return defaultQueues.firstWhere((q) => q.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get all enabled queues
  static List<QueueConfig> getEnabled() {
    return defaultQueues.where((q) => q.enabled).toList();
  }

  /// Get queues that match a given event type
  static List<QueueConfig> getMatchingQueues(String eventType) {
    return defaultQueues
        .where((q) => q.enabled && q.matchesEventType(eventType))
        .toList();
  }
}