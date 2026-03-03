import Foundation
import GRDB
import Combine

/// Callback type for queue consumers
typealias QueueConsumerCallback = (QueueMessage) async -> Bool

/// Represents a subscriber to a queue
private struct QueueSubscriber {
    let id: String
    let queueId: String
    let callback: QueueConsumerCallback
    let name: String?
}

/// Service that manages message queues.
/// Routes events from AppBus to specific queues based on configuration.
/// Provides RabbitMQ-like message consumption with acknowledgment.
class QueueService {
    static let shared = QueueService()

    private let database = PlaygroundDatabase.shared
    private var busSubscriptionId: String?
    private var subscribers: [String: [QueueSubscriber]] = [:]
    private let messageSubject = PassthroughSubject<QueueMessage, Never>()
    private var cancellables = Set<AnyCancellable>()
    private let queue = DispatchQueue(label: "com.playground.queueservice", attributes: .concurrent)

    private init() {}

    /// Stream of all new messages (for monitoring)
    var messageStream: AnyPublisher<QueueMessage, Never> {
        messageSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    /// Initialize the queue service and database
    func initialize() {
        // Tables are created via migrations in PlaygroundDatabase
        // Subscribe to all events from the AppBus
        busSubscriptionId = AppBus.shared.subscribeToAll { [weak self] event in
            Task {
                await self?.handleBusEvent(event)
            }
        }
    }

    // MARK: - Event Handling

    /// Handle incoming events from the AppBus
    private func handleBusEvent(_ event: AppBusEvent) async {
        let matchingQueues = QueueConfigs.getMatchingQueues(event.type)

        if !matchingQueues.isEmpty {
            print("📬 [QueueService] Routing event '\(event.type)' to \(matchingQueues.count) queue(s)")
        }

        for queueConfig in matchingQueues {
            do {
                let message = try await enqueueMessage(
                    queueId: queueConfig.id,
                    eventType: event.type,
                    appId: event.appId ?? "unknown",
                    payload: event.getPayload()
                )

                print("✅ [QueueService] Enqueued message to '\(queueConfig.name)' (id: \(message.id))")

                // Notify subscribers
                await notifySubscribers(queueId: queueConfig.id)
            } catch {
                print("❌ [QueueService] Failed to enqueue message for queue \(queueConfig.id): \(error)")
            }
        }
    }

    // MARK: - Message Operations

    /// Add a message to a queue
    private func enqueueMessage(
        queueId: String,
        eventType: String,
        appId: String,
        payload: [String: Any]?
    ) async throws -> QueueMessage {
        // Use UUID to ensure uniqueness even when messages are created rapidly
        let message = QueueMessage(
            id: UUID().uuidString,
            queueId: queueId,
            eventType: eventType,
            appId: appId,
            payload: payload
        )

        try await database.execute { db in
            try message.insert(db)
        }

        messageSubject.send(message)
        return message
    }

    /// Manually enqueue a message (for external use)
    func enqueue(
        queueId: String,
        eventType: String,
        appId: String,
        payload: [String: Any]? = nil
    ) async throws -> QueueMessage {
        guard QueueConfigs.getById(queueId) != nil else {
            throw NSError(domain: "QueueService", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Unknown queue: \(queueId)"
            ])
        }

        return try await enqueueMessage(
            queueId: queueId,
            eventType: eventType,
            appId: appId,
            payload: payload
        )
    }

    // MARK: - Subscription

    /// Subscribe to a queue for message consumption
    /// Returns a subscription ID that can be used to unsubscribe
    @discardableResult
    func subscribe(
        id: String,
        queueId: String,
        name: String? = nil,
        callback: @escaping QueueConsumerCallback
    ) -> String {
        queue.async(flags: .barrier) {
            if self.subscribers[queueId] == nil {
                self.subscribers[queueId] = []
            }

            let subscriber = QueueSubscriber(
                id: id,
                queueId: queueId,
                callback: callback,
                name: name
            )

            self.subscribers[queueId]?.append(subscriber)
        }

        return id
    }

    /// Unsubscribe from a queue
    func unsubscribe(subscriptionId: String) {
        queue.async(flags: .barrier) {
            for (queueId, _) in self.subscribers {
                self.subscribers[queueId]?.removeAll { $0.id == subscriptionId }
            }
        }
    }

    // MARK: - Message Fetching and Processing

    /// Get the next available message from a queue and lock it
    /// Returns nil if no messages are available
    func fetchMessage(
        queueId: String,
        consumerId: String,
        lockTimeoutSeconds: Int? = nil
    ) async throws -> QueueMessage? {
        let config = QueueConfigs.getById(queueId)
        let timeout = lockTimeoutSeconds ?? config?.lockTimeoutSeconds ?? 30
        let now = Date()
        let lockExpires = now.addingTimeInterval(TimeInterval(timeout))

        // First, release any expired locks
        try await releaseExpiredLocks()

        // Find an available message (not locked, lock expired, and visible)
        let message = try await database.read { db -> QueueMessage? in
            try QueueMessage
                .filter(
                    QueueMessage.Columns.queueId == queueId &&
                    (QueueMessage.Columns.lockedBy == nil || QueueMessage.Columns.lockExpiresAt < now) &&
                    (QueueMessage.Columns.visibleAfter == nil || QueueMessage.Columns.visibleAfter <= now)
                )
                .order(QueueMessage.Columns.timestamp.asc)
                .fetchOne(db)
        }

        guard let message = message else {
            return nil
        }

        // Lock the message
        let updatedMessage = message.copyWith(
            deliveryCount: message.deliveryCount + 1,
            lastDeliveredAt: now,
            lockedBy: consumerId,
            lockExpiresAt: lockExpires
        )

        try await database.execute { db in
            try updatedMessage.update(db)
        }

        return updatedMessage
    }

    /// Acknowledge successful processing of a message (removes it from queue)
    @discardableResult
    func acknowledge(_ messageId: String) async throws -> Bool {
        let count = try await database.execute { db -> Int in
            try QueueMessage
                .filter(QueueMessage.Columns.id == messageId)
                .deleteAll(db)
        }

        return count > 0
    }

    /// Reject a message with exponential backoff retry.
    /// If max retries exceeded, message is moved to DLQ.
    func reject(
        _ messageId: String,
        requeue: Bool = true,
        errorReason: String? = nil
    ) async throws {
        guard let message = try await getMessage(messageId) else {
            return
        }

        let config = QueueConfigs.getById(message.queueId)

        // Check if max retries exceeded
        if let config = config, message.deliveryCount >= config.maxRetries {
            try await moveToDlq(message, errorReason: errorReason)
            return
        }

        if !requeue {
            try await moveToDlq(message, errorReason: errorReason)
            return
        }

        // Calculate backoff delay
        let delayMs = config?.getRetryDelayMs(deliveryCount: message.deliveryCount) ?? 3000
        let visibleAfter = Date().addingTimeInterval(TimeInterval(delayMs) / 1000.0)

        // Release lock and set visibility delay
        let updatedMessage = message.copyWith(
            lockedBy: nil,
            lockExpiresAt: nil,
            visibleAfter: visibleAfter
        )

        try await database.execute { db in
            try updatedMessage.update(db)
        }
    }

    // MARK: - Query Operations

    /// Get a specific message by ID
    func getMessage(_ messageId: String) async throws -> QueueMessage? {
        return try await database.read { db in
            try QueueMessage
                .filter(QueueMessage.Columns.id == messageId)
                .fetchOne(db)
        }
    }

    /// Get all messages in a queue (for inspection/debugging)
    func getMessages(
        queueId: String,
        includeLockedMessages: Bool = true,
        limit: Int? = nil,
        offset: Int = 0
    ) async throws -> [QueueMessage] {
        return try await database.read { db in
            var request = QueueMessage
                .filter(QueueMessage.Columns.queueId == queueId)

            if !includeLockedMessages {
                let now = Date()
                request = request.filter(
                    QueueMessage.Columns.lockedBy == nil ||
                    QueueMessage.Columns.lockExpiresAt < now
                )
            }

            request = request.order(QueueMessage.Columns.timestamp.asc)

            if let limit = limit {
                request = request.limit(limit, offset: offset)
            }

            return try request.fetchAll(db)
        }
    }

    /// Get metrics for a specific queue
    func getQueueMetrics(_ queueId: String) async throws -> QueueMetrics {
        let now = Date()

        return try await database.read { db in
            // Total messages
            let totalCount = try QueueMessage
                .filter(QueueMessage.Columns.queueId == queueId)
                .fetchCount(db)

            // Locked messages
            let lockedCount = try QueueMessage
                .filter(
                    QueueMessage.Columns.queueId == queueId &&
                    QueueMessage.Columns.lockedBy != nil &&
                    QueueMessage.Columns.lockExpiresAt > now
                )
                .fetchCount(db)

            // Oldest message
            let oldestMessage = try QueueMessage
                .filter(QueueMessage.Columns.queueId == queueId)
                .order(QueueMessage.Columns.timestamp.asc)
                .fetchOne(db)

            // Newest message
            let newestMessage = try QueueMessage
                .filter(QueueMessage.Columns.queueId == queueId)
                .order(QueueMessage.Columns.timestamp.desc)
                .fetchOne(db)

            // Get subscribers (need to access from queue)
            let subscribersList = self.queue.sync {
                self.subscribers[queueId] ?? []
            }

            return QueueMetrics(
                queueId: queueId,
                messageCount: totalCount,
                lockedCount: lockedCount,
                availableCount: totalCount - lockedCount,
                subscriberCount: subscribersList.count,
                subscriberIds: subscribersList.map { $0.id },
                oldestMessageAt: oldestMessage?.timestamp,
                newestMessageAt: newestMessage?.timestamp
            )
        }
    }

    /// Get metrics for all queues
    func getAllMetrics() async throws -> [String: QueueMetrics] {
        var metrics: [String: QueueMetrics] = [:]

        for config in QueueConfigs.getEnabled() {
            metrics[config.id] = try await getQueueMetrics(config.id)
        }

        return metrics
    }

    /// Get message count for a queue
    func getMessageCount(_ queueId: String) async throws -> Int {
        return try await database.read { db in
            try QueueMessage
                .filter(QueueMessage.Columns.queueId == queueId)
                .fetchCount(db)
        }
    }

    /// Clear all messages from a queue
    @discardableResult
    func clearQueue(_ queueId: String) async throws -> Int {
        return try await database.execute { db in
            try QueueMessage
                .filter(QueueMessage.Columns.queueId == queueId)
                .deleteAll(db)
        }
    }

    // MARK: - Internal Helpers

    /// Release expired locks so messages can be redelivered
    private func releaseExpiredLocks() async throws {
        let now = Date()

        try await database.execute { db in
            try db.execute(sql: """
                UPDATE queue_messages
                SET lockedBy = NULL, lockExpiresAt = NULL
                WHERE lockExpiresAt IS NOT NULL AND lockExpiresAt < ?
                """, arguments: [now])
        }
    }

    /// Notify subscribers that new messages are available
    private func notifySubscribers(queueId: String) async {
        let subscribersList = queue.sync {
            subscribers[queueId] ?? []
        }

        for subscriber in subscribersList {
            Task {
                await processMessagesForSubscriber(subscriber)
            }
        }
    }

    /// Process available messages for a subscriber
    private func processMessagesForSubscriber(_ subscriber: QueueSubscriber) async {
        do {
            guard let message = try await fetchMessage(
                queueId: subscriber.queueId,
                consumerId: subscriber.id
            ) else {
                return
            }

            let success = await subscriber.callback(message)

            if success {
                try await acknowledge(message.id)
            } else {
                try await reject(message.id)
            }
        } catch {
            print("❌ Error processing message for subscriber \(subscriber.id): \(error)")
        }
    }

    // MARK: - Dead Letter Queue

    /// Move a message to the dead letter queue
    private func moveToDlq(_ message: QueueMessage, errorReason: String?) async throws {
        let dlqMessage = DlqMessage(
            id: message.id,
            queueId: message.queueId,
            eventType: message.eventType,
            appId: message.appId,
            timestamp: message.timestamp,
            payload: message.payload,
            deliveryCount: message.deliveryCount,
            lastDeliveredAt: message.lastDeliveredAt,
            movedToDlqAt: Date(),
            errorReason: errorReason
        )

        try await database.execute { db in
            // Insert into DLQ
            try dlqMessage.insert(db)

            // Remove from main queue
            try QueueMessage
                .filter(QueueMessage.Columns.id == message.id)
                .deleteAll(db)
        }
    }

    /// Get all messages in the dead letter queue
    func getDlqMessages(
        queueId: String? = nil,
        limit: Int? = nil,
        offset: Int = 0
    ) async throws -> [DlqMessage] {
        return try await database.read { db in
            var request = DlqMessage.all()

            if let queueId = queueId {
                request = request.filter(DlqMessage.Columns.queueId == queueId)
            }

            request = request.order(DlqMessage.Columns.movedToDlqAt.desc)

            if let limit = limit {
                request = request.limit(limit, offset: offset)
            }

            return try request.fetchAll(db)
        }
    }

    /// Get DLQ message count
    func getDlqMessageCount(queueId: String? = nil) async throws -> Int {
        return try await database.read { db in
            var request = DlqMessage.all()

            if let queueId = queueId {
                request = request.filter(DlqMessage.Columns.queueId == queueId)
            }

            return try request.fetchCount(db)
        }
    }

    /// Retry a message from the DLQ (moves it back to the main queue)
    @discardableResult
    func retryFromDlq(_ messageId: String) async throws -> Bool {
        guard let dlqMessage = try await database.read({ db in
            try DlqMessage.filter(DlqMessage.Columns.id == messageId).fetchOne(db)
        }) else {
            return false
        }

        // Re-insert into main queue with reset delivery count
        let newMessage = QueueMessage(
            id: "\(Int(Date().timeIntervalSince1970 * 1000))_retry_\(dlqMessage.id)",
            queueId: dlqMessage.queueId,
            eventType: dlqMessage.eventType,
            appId: dlqMessage.appId,
            timestamp: Date(),
            payload: dlqMessage.getPayload(),
            deliveryCount: 0
        )

        try await database.execute { db in
            try newMessage.insert(db)

            // Remove from DLQ
            try DlqMessage
                .filter(DlqMessage.Columns.id == messageId)
                .deleteAll(db)
        }

        // Notify subscribers
        await notifySubscribers(queueId: dlqMessage.queueId)

        return true
    }

    /// Delete a message from the DLQ permanently
    @discardableResult
    func deleteDlqMessage(_ messageId: String) async throws -> Bool {
        let count = try await database.execute { db in
            try DlqMessage
                .filter(DlqMessage.Columns.id == messageId)
                .deleteAll(db)
        }

        return count > 0
    }

    /// Clear all messages from a queue's DLQ
    @discardableResult
    func clearDlq(queueId: String? = nil) async throws -> Int {
        return try await database.execute { db in
            if let queueId = queueId {
                return try DlqMessage
                    .filter(DlqMessage.Columns.queueId == queueId)
                    .deleteAll(db)
            } else {
                return try DlqMessage.deleteAll(db)
            }
        }
    }

    // MARK: - Cleanup

    /// Dispose resources
    func dispose() {
        if let subscriptionId = busSubscriptionId {
            AppBus.shared.unsubscribe(eventType: subscriptionId)
            busSubscriptionId = nil
        }

        queue.async(flags: .barrier) {
            self.subscribers.removeAll()
        }
    }
}
