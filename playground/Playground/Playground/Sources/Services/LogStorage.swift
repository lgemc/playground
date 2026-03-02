import Foundation
import GRDB
import Combine

/// Represents a stored log entry in the database
struct LogEntry: Codable, Identifiable {
    let id: String
    let appId: String
    let appName: String
    let message: String
    let severity: String
    let eventType: String
    let timestamp: Date
    let metadata: String? // JSON string

    init(
        id: String = UUID().uuidString,
        appId: String,
        appName: String,
        message: String,
        severity: LogSeverity,
        eventType: String = "general",
        timestamp: Date = Date(),
        metadata: [String: Any]? = nil
    ) {
        self.id = id
        self.appId = appId
        self.appName = appName
        self.message = message
        self.severity = severity.name
        self.eventType = eventType
        self.timestamp = timestamp

        // Encode metadata to JSON
        if let metadata = metadata {
            self.metadata = try? String(
                data: JSONSerialization.data(withJSONObject: metadata),
                encoding: .utf8
            )
        } else {
            self.metadata = nil
        }
    }

    /// Decode metadata from JSON
    func getMetadata() -> [String: Any]? {
        guard let metadataString = metadata,
              let data = metadataString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    var severityEnum: LogSeverity {
        LogSeverity.from(string: severity)
    }
}

// GRDB conformance
extension LogEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "logs"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let appId = Column(CodingKeys.appId)
        static let appName = Column(CodingKeys.appName)
        static let message = Column(CodingKeys.message)
        static let severity = Column(CodingKeys.severity)
        static let eventType = Column(CodingKeys.eventType)
        static let timestamp = Column(CodingKeys.timestamp)
        static let metadata = Column(CodingKeys.metadata)
    }
}

/// Service that persists logs to SQLite and provides streaming updates
class LogStorage {
    static let shared = LogStorage()

    private let database = PlaygroundDatabase.shared
    private var busSubscriptionId: String?
    private let logSubject = PassthroughSubject<LogEntry, Never>()
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    /// Stream of new log entries
    var logStream: AnyPublisher<LogEntry, Never> {
        logSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    /// Initialize the log storage service
    func initialize() {
        // Subscribe to log events from AppBus
        busSubscriptionId = AppBus.shared.subscribe(eventType: "log.*") { [weak self] event in
            Task {
                await self?.handleLogEvent(event)
            }
        }

        // Subscribe to log streaming completion events
        _ = AppBus.shared.subscribe(eventType: "log.stream.complete") { [weak self] event in
            Task {
                await self?.handleStreamComplete(event)
            }
        }
    }

    // MARK: - Event Handling

    /// Handle incoming log events from AppBus
    private func handleLogEvent(_ event: AppBusEvent) async {
        guard let payload = event.getPayload() else { return }

        // Skip if this is a streaming log without content yet
        if let isStreaming = payload["isStreaming"] as? Bool, isStreaming {
            // Don't persist yet - wait for completion
            return
        }

        guard let appId = payload["appId"] as? String,
              let appName = payload["appName"] as? String,
              let message = payload["message"] as? String,
              let severityStr = payload["severity"] as? String else {
            return
        }

        let severity = LogSeverity.from(string: severityStr)
        let eventType = payload["eventType"] as? String ?? "general"

        // Create metadata without duplicating core fields
        var metadata: [String: Any] = [:]
        for (key, value) in payload {
            if !["appId", "appName", "message", "severity", "eventType", "isStreaming"].contains(key) {
                metadata[key] = value
            }
        }

        let logEntry = LogEntry(
            appId: appId,
            appName: appName,
            message: message,
            severity: severity,
            eventType: eventType,
            timestamp: Date(),
            metadata: metadata.isEmpty ? nil : metadata
        )

        do {
            try await database.execute { db in
                try logEntry.insert(db)
            }

            // Broadcast to UI
            logSubject.send(logEntry)
        } catch {
            print("❌ Failed to store log entry: \(error)")
        }
    }

    /// Handle log streaming completion
    private func handleStreamComplete(_ event: AppBusEvent) async {
        guard let payload = event.getPayload(),
              let _ = payload["streamLogId"] as? String,
              let _ = payload["finalMessage"] as? String else {
            return
        }

        // Update the log entry with the final message
        // For now, we'll just create a new entry since we didn't persist the initial one
        // In a real implementation, you might want to update an existing entry
    }

    // MARK: - Query Operations

    /// Get logs with optional filtering
    func getLogs(
        appId: String? = nil,
        severity: LogSeverity? = nil,
        limit: Int = 500,
        offset: Int = 0
    ) async throws -> [LogEntry] {
        return try await database.read { db in
            var request = LogEntry
                .order(LogEntry.Columns.timestamp.desc)

            if let appId = appId {
                request = request.filter(LogEntry.Columns.appId == appId)
            }

            if let severity = severity {
                request = request.filter(LogEntry.Columns.severity == severity.name)
            }

            request = request.limit(limit, offset: offset)

            return try request.fetchAll(db)
        }
    }

    /// Get distinct app IDs that have logs
    func getApps() async throws -> [String] {
        return try await database.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT DISTINCT appId FROM logs ORDER BY appId"
            )
        }
    }

    /// Get log count
    func getLogCount(appId: String? = nil, severity: LogSeverity? = nil) async throws -> Int {
        return try await database.read { db in
            var request = LogEntry.all()

            if let appId = appId {
                request = request.filter(LogEntry.Columns.appId == appId)
            }

            if let severity = severity {
                request = request.filter(LogEntry.Columns.severity == severity.name)
            }

            return try request.fetchCount(db)
        }
    }

    /// Clear all logs
    @discardableResult
    func clearLogs(appId: String? = nil) async throws -> Int {
        return try await database.execute { db in
            if let appId = appId {
                return try LogEntry
                    .filter(LogEntry.Columns.appId == appId)
                    .deleteAll(db)
            } else {
                return try LogEntry.deleteAll(db)
            }
        }
    }

    // MARK: - Cleanup

    func dispose() {
        if let subscriptionId = busSubscriptionId {
            AppBus.shared.unsubscribe(eventType: subscriptionId)
            busSubscriptionId = nil
        }
    }
}
