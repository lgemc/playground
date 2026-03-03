import Foundation
import GRDB

// MARK: - Queue Message

/// Represents a message stored in a queue.
/// Messages persist until successfully processed and acknowledged.
struct QueueMessage: Codable, Identifiable {
    /// Unique identifier for this message
    let id: String

    /// The queue this message belongs to
    let queueId: String

    /// Original event type that triggered this message
    let eventType: String

    /// ID of the app that emitted the original event
    let appId: String

    /// When the message was created
    let timestamp: Date

    /// Message payload data (JSON string)
    let payload: String?

    /// Number of times this message has been delivered
    let deliveryCount: Int

    /// When this message was last delivered to a consumer
    let lastDeliveredAt: Date?

    /// ID of the consumer currently processing this message (if any)
    let lockedBy: String?

    /// When the lock expires (message can be redelivered after this)
    let lockExpiresAt: Date?

    /// When this message becomes visible for processing (for retry delays)
    let visibleAfter: Date?

    init(
        id: String = UUID().uuidString,
        queueId: String,
        eventType: String,
        appId: String,
        timestamp: Date = Date(),
        payload: [String: Any]? = nil,
        deliveryCount: Int = 0,
        lastDeliveredAt: Date? = nil,
        lockedBy: String? = nil,
        lockExpiresAt: Date? = nil,
        visibleAfter: Date? = nil
    ) {
        self.id = id
        self.queueId = queueId
        self.eventType = eventType
        self.appId = appId
        self.timestamp = timestamp
        self.deliveryCount = deliveryCount
        self.lastDeliveredAt = lastDeliveredAt
        self.lockedBy = lockedBy
        self.lockExpiresAt = lockExpiresAt
        self.visibleAfter = visibleAfter

        // Encode payload to JSON
        if let payload = payload {
            self.payload = try? String(
                data: JSONSerialization.data(withJSONObject: payload),
                encoding: .utf8
            )
        } else {
            self.payload = nil
        }
    }

    /// Decode payload from JSON
    func getPayload() -> [String: Any]? {
        guard let payloadString = payload,
              let data = payloadString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// Create a copy with updated fields
    func copyWith(
        id: String? = nil,
        queueId: String? = nil,
        eventType: String? = nil,
        appId: String? = nil,
        timestamp: Date? = nil,
        payload: String? = nil,
        deliveryCount: Int? = nil,
        lastDeliveredAt: Date? = nil,
        lockedBy: String? = nil,
        lockExpiresAt: Date? = nil,
        visibleAfter: Date? = nil
    ) -> QueueMessage {
        QueueMessage(
            id: id ?? self.id,
            queueId: queueId ?? self.queueId,
            eventType: eventType ?? self.eventType,
            appId: appId ?? self.appId,
            timestamp: timestamp ?? self.timestamp,
            payload: self.getPayload(),
            deliveryCount: deliveryCount ?? self.deliveryCount,
            lastDeliveredAt: lastDeliveredAt ?? self.lastDeliveredAt,
            lockedBy: lockedBy ?? self.lockedBy,
            lockExpiresAt: lockExpiresAt ?? self.lockExpiresAt,
            visibleAfter: visibleAfter ?? self.visibleAfter
        )
    }
}

// GRDB conformance
extension QueueMessage: FetchableRecord, PersistableRecord {
    static let databaseTableName = "queue_messages"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let queueId = Column(CodingKeys.queueId)
        static let eventType = Column(CodingKeys.eventType)
        static let appId = Column(CodingKeys.appId)
        static let timestamp = Column(CodingKeys.timestamp)
        static let payload = Column(CodingKeys.payload)
        static let deliveryCount = Column(CodingKeys.deliveryCount)
        static let lastDeliveredAt = Column(CodingKeys.lastDeliveredAt)
        static let lockedBy = Column(CodingKeys.lockedBy)
        static let lockExpiresAt = Column(CodingKeys.lockExpiresAt)
        static let visibleAfter = Column(CodingKeys.visibleAfter)
    }
}

// MARK: - Dead Letter Queue Message

/// Represents a message in the Dead Letter Queue.
/// These are messages that failed processing after all retry attempts.
struct DlqMessage: Codable, Identifiable {
    let id: String
    let queueId: String
    let eventType: String
    let appId: String
    let timestamp: Date
    let payload: String?
    let deliveryCount: Int
    let lastDeliveredAt: Date?
    let movedToDlqAt: Date
    let errorReason: String?

    init(
        id: String,
        queueId: String,
        eventType: String,
        appId: String,
        timestamp: Date,
        payload: String? = nil,
        deliveryCount: Int = 0,
        lastDeliveredAt: Date? = nil,
        movedToDlqAt: Date = Date(),
        errorReason: String? = nil
    ) {
        self.id = id
        self.queueId = queueId
        self.eventType = eventType
        self.appId = appId
        self.timestamp = timestamp
        self.payload = payload
        self.deliveryCount = deliveryCount
        self.lastDeliveredAt = lastDeliveredAt
        self.movedToDlqAt = movedToDlqAt
        self.errorReason = errorReason
    }

    /// Decode payload from JSON
    func getPayload() -> [String: Any]? {
        guard let payloadString = payload,
              let data = payloadString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

// GRDB conformance
extension DlqMessage: FetchableRecord, PersistableRecord {
    static let databaseTableName = "dlq_messages"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let queueId = Column(CodingKeys.queueId)
        static let eventType = Column(CodingKeys.eventType)
        static let appId = Column(CodingKeys.appId)
        static let timestamp = Column(CodingKeys.timestamp)
        static let payload = Column(CodingKeys.payload)
        static let deliveryCount = Column(CodingKeys.deliveryCount)
        static let lastDeliveredAt = Column(CodingKeys.lastDeliveredAt)
        static let movedToDlqAt = Column(CodingKeys.movedToDlqAt)
        static let errorReason = Column(CodingKeys.errorReason)
    }
}

// MARK: - Queue Configuration

/// Configuration for a single queue.
/// Defines which event topics route to this queue.
struct QueueConfig {
    /// Unique identifier for this queue
    let id: String

    /// Human-readable name
    let name: String

    /// Event type patterns this queue subscribes to.
    /// Supports wildcards: 'note.*' matches 'note.created', 'note.updated', etc.
    let eventPatterns: [String]

    /// Maximum number of retry attempts before moving to dead letter queue
    let maxRetries: Int

    /// Lock timeout in seconds (how long a consumer can hold a message)
    let lockTimeoutSeconds: Int

    /// Whether this queue is enabled
    let enabled: Bool

    /// Retry delays in ms for exponential backoff: [3s, 9s, 3min]
    let retryDelaysMs: [Int]

    init(
        id: String,
        name: String,
        eventPatterns: [String],
        maxRetries: Int = 3,
        lockTimeoutSeconds: Int = 900, // 15 minutes
        enabled: Bool = true,
        retryDelaysMs: [Int] = [3000, 9000, 180000] // 3s, 9s, 3min
    ) {
        self.id = id
        self.name = name
        self.eventPatterns = eventPatterns
        self.maxRetries = maxRetries
        self.lockTimeoutSeconds = lockTimeoutSeconds
        self.enabled = enabled
        self.retryDelaysMs = retryDelaysMs
    }

    /// Get retry delay for a given delivery count (1-indexed)
    func getRetryDelayMs(deliveryCount: Int) -> Int {
        if retryDelaysMs.isEmpty { return 0 }
        let index = max(0, min(deliveryCount - 1, retryDelaysMs.count - 1))
        return retryDelaysMs[index]
    }

    /// Check if this queue should receive events of the given type
    func matchesEventType(_ eventType: String) -> Bool {
        for pattern in eventPatterns {
            if pattern == "*" { return true }
            if pattern == eventType { return true }
            if pattern.hasSuffix(".*") {
                let prefix = String(pattern.dropLast(2))
                if eventType.hasPrefix("\(prefix).") { return true }
            }
        }
        return false
    }
}

// MARK: - Queue Metrics

/// Metrics for a single queue
struct QueueMetrics {
    /// Queue identifier
    let queueId: String

    /// Total messages in queue
    let messageCount: Int

    /// Messages currently being processed
    let lockedCount: Int

    /// Messages available for processing
    let availableCount: Int

    /// Number of registered consumers
    let subscriberCount: Int

    /// List of subscriber IDs
    let subscriberIds: [String]

    /// Timestamp of the oldest message
    let oldestMessageAt: Date?

    /// Timestamp of the newest message
    let newestMessageAt: Date?

    func toMap() -> [String: Any] {
        var map: [String: Any] = [
            "queueId": queueId,
            "messageCount": messageCount,
            "lockedCount": lockedCount,
            "availableCount": availableCount,
            "subscriberCount": subscriberCount,
            "subscriberIds": subscriberIds
        ]

        if let oldest = oldestMessageAt {
            map["oldestMessageAt"] = ISO8601DateFormatter().string(from: oldest)
        }
        if let newest = newestMessageAt {
            map["newestMessageAt"] = ISO8601DateFormatter().string(from: newest)
        }

        return map
    }
}

// MARK: - Queue Configurations

/// Hardcoded queue configurations.
/// In a production system, these would come from a config file or database.
struct QueueConfigs {
    static let defaultQueues: [QueueConfig] = [
        // Queue for note-related events
        QueueConfig(
            id: "notes-processor",
            name: "Notes Processor",
            eventPatterns: ["note.*"],
            maxRetries: 3,
            lockTimeoutSeconds: 30
        ),
        // Queue for vocabulary events (word definition lookup)
        QueueConfig(
            id: "vocabulary-definition",
            name: "Vocabulary Definition Processor",
            eventPatterns: ["vocabulary.create", "vocabulary.update"],
            maxRetries: 3,
            lockTimeoutSeconds: 60
        ),
        // Queue for log events
        QueueConfig(
            id: "logs-processor",
            name: "Logs Processor",
            eventPatterns: ["log.*"],
            maxRetries: 5,
            lockTimeoutSeconds: 10
        ),
        // Queue for app lifecycle events
        QueueConfig(
            id: "lifecycle-processor",
            name: "Lifecycle Processor",
            eventPatterns: ["app.opened", "app.closed", "app.initialized"],
            maxRetries: 3,
            lockTimeoutSeconds: 15
        ),
        // Queue for chat title generation tasks
        QueueConfig(
            id: "chat-title-generator",
            name: "Chat Title Generator",
            eventPatterns: ["chat.title_generate"],
            maxRetries: 3,
            lockTimeoutSeconds: 60
        ),
        // Queue for derivative generation (video transcripts, thumbnails, etc.)
        QueueConfig(
            id: "derivative-generator",
            name: "Derivative Generator",
            eventPatterns: ["derivative.create"],
            maxRetries: 3,
            lockTimeoutSeconds: 600, // 10 minutes for video transcription
            retryDelaysMs: [5000, 15000, 300000] // 5s, 15s, 5min
        ),
        // Catch-all queue for unmatched events (disabled by default)
        QueueConfig(
            id: "default-queue",
            name: "Default Queue",
            eventPatterns: ["*"],
            maxRetries: 3,
            lockTimeoutSeconds: 30,
            enabled: false
        )
    ]

    /// Get queue config by ID
    static func getById(_ id: String) -> QueueConfig? {
        return defaultQueues.first { $0.id == id }
    }

    /// Get all enabled queues
    static func getEnabled() -> [QueueConfig] {
        return defaultQueues.filter { $0.enabled }
    }

    /// Get queues that match a given event type
    static func getMatchingQueues(_ eventType: String) -> [QueueConfig] {
        return defaultQueues.filter { $0.enabled && $0.matchesEventType(eventType) }
    }
}
