import SwiftUI
import Combine
import GRDB

/// Logger app for monitoring system logs across all sub-apps
class LogsApp: SubApp {
    let id = "logs"
    let name = "Logs"
    let iconName = "doc.text.fill"
    let themeColor = Color.blue

    // ObservableObject conformance
    let objectWillChange = ObservableObjectPublisher()

    private var queueSubscriptionId: String?

    init() {}

    func buildView() -> AnyView {
        AnyView(LogsView())
    }

    func onInit() async {
        // Ensure LogStorage is initialized
        LogStorage.shared.initialize()

        // Subscribe to the logs-processor queue to consume log messages
        queueSubscriptionId = QueueService.shared.subscribe(
            id: "logs-app-consumer",
            queueId: "logs-processor",
            name: "Logs App Consumer"
        ) { [weak self] message in
            await self?.processLogMessage(message) ?? false
        }

        print("✅ [LogsApp] Subscribed to logs-processor queue")
    }

    func onDispose() {
        // Clean up subscription
        if let subscriptionId = queueSubscriptionId {
            QueueService.shared.unsubscribe(subscriptionId: subscriptionId)
            queueSubscriptionId = nil
        }
    }

    /// Process a log message from the queue
    private func processLogMessage(_ message: QueueMessage) async -> Bool {
        guard let payload = message.getPayload() else {
            print("❌ [LogsApp] Failed to decode message payload")
            return false
        }

        guard let appId = payload["appId"] as? String,
              let appName = payload["appName"] as? String,
              let logMessage = payload["message"] as? String,
              let severityStr = payload["severity"] as? String else {
            print("❌ [LogsApp] Missing required fields in log message")
            return false
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
            message: logMessage,
            severity: severity,
            eventType: eventType,
            timestamp: Date(),
            metadata: metadata.isEmpty ? nil : metadata
        )

        do {
            try await PlaygroundDatabase.shared.execute { db in
                try logEntry.insert(db)
            }

            print("✅ [LogsApp] Processed log from queue: [\(severity.name)] \(appName): \(logMessage)")
            return true
        } catch {
            print("❌ [LogsApp] Failed to store log entry: \(error)")
            return false
        }
    }
}
