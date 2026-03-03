import Foundation

/// Log severity levels
enum LogSeverity: String, Codable {
    case debug
    case info
    case warning
    case error
    case critical

    var name: String {
        return self.rawValue
    }

    static func from(string: String) -> LogSeverity {
        switch string.lowercased() {
        case "debug": return .debug
        case "info": return .info
        case "warning": return .warning
        case "error": return .error
        case "critical": return .critical
        default: return .info
        }
    }
}

/// Logger interface for apps and services to emit log events.
/// Logs are emitted via the AppBus and can be stored by a log storage service.
class Logger {
    let appId: String
    let appName: String

    init(appId: String, appName: String) {
        self.appId = appId
        self.appName = appName
    }

    /// Log a message with the given severity and optional metadata
    func log(
        _ message: String,
        severity: LogSeverity = .info,
        eventType: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        var logMetadata: [String: Any] = [
            "appId": appId,
            "appName": appName,
            "message": message,
            "severity": severity.name,
            "eventType": eventType ?? "general"
        ]

        // Merge additional metadata
        if let metadata = metadata {
            logMetadata.merge(metadata) { _, new in new }
        }

        AppBus.shared.emit(
            type: "log.\(severity.name)",
            appId: appId,
            payload: logMetadata
        )
    }

    /// Log a debug message
    func debug(
        _ message: String,
        eventType: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        log(message, severity: .debug, eventType: eventType, metadata: metadata)
    }

    /// Log an info message
    func info(
        _ message: String,
        eventType: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        log(message, severity: .info, eventType: eventType, metadata: metadata)
    }

    /// Log a warning message
    func warning(
        _ message: String,
        eventType: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        log(message, severity: .warning, eventType: eventType, metadata: metadata)
    }

    /// Log an error message
    func error(
        _ message: String,
        eventType: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        log(message, severity: .error, eventType: eventType, metadata: metadata)
    }

    /// Log a critical message
    func critical(
        _ message: String,
        eventType: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        log(message, severity: .critical, eventType: eventType, metadata: metadata)
    }
}

// MARK: - Streaming Log Support

/// Manages state for streaming log messages
class LogStreamingService {
    static let shared = LogStreamingService()

    private var streamingStates: [String: StreamingState] = [:]
    private let queue = DispatchQueue(label: "com.playground.logstreaming", attributes: .concurrent)

    private init() {}

    struct StreamingState {
        var message: String
        var isComplete: Bool
        var error: String?
        var severity: LogSeverity
        var eventType: String
        var appId: String
        var appName: String
    }

    /// Start a streaming log session
    func startStreaming(logId: String, severity: LogSeverity, eventType: String, appId: String, appName: String) {
        queue.async(flags: .barrier) {
            self.streamingStates[logId] = StreamingState(
                message: "",
                isComplete: false,
                error: nil,
                severity: severity,
                eventType: eventType,
                appId: appId,
                appName: appName
            )
        }
    }

    /// Append text to a streaming log
    func appendMessage(logId: String, text: String) {
        queue.async(flags: .barrier) {
            self.streamingStates[logId]?.message += text
        }
    }

    /// Get current state of a streaming log
    func getState(logId: String) -> StreamingState? {
        queue.sync {
            return streamingStates[logId]
        }
    }

    /// Mark a streaming log as complete
    func completeStreaming(logId: String, finalMessage: String? = nil) {
        queue.async(flags: .barrier) {
            if let message = finalMessage {
                self.streamingStates[logId]?.message = message
            }
            self.streamingStates[logId]?.isComplete = true
        }
    }

    /// Mark a streaming log as failed
    func failStreaming(logId: String, error: String) {
        queue.async(flags: .barrier) {
            self.streamingStates[logId]?.error = error
            self.streamingStates[logId]?.isComplete = true
        }
    }

    /// Clean up old streaming states
    func cleanup(logId: String) {
        queue.async(flags: .barrier) {
            self.streamingStates.removeValue(forKey: logId)
        }
    }
}

// MARK: - Logger Streaming Extension

extension Logger {
    /// Start a streaming log message. Returns the log ID for subsequent updates.
    /// The log will appear in the UI immediately and update as content is appended.
    func startStreamingLog(
        severity: LogSeverity = .info,
        eventType: String? = nil,
        metadata: [String: Any]? = nil
    ) -> String {
        let logId = "\(appId)_\(Int(Date().timeIntervalSince1970 * 1000))"
        let actualEventType = eventType ?? "general"

        // Initialize streaming state
        LogStreamingService.shared.startStreaming(
            logId: logId,
            severity: severity,
            eventType: actualEventType,
            appId: appId,
            appName: appName
        )

        // Emit initial event to create the log entry (with empty message)
        var logMetadata: [String: Any] = [
            "appId": appId,
            "appName": appName,
            "message": "", // Will be updated as content streams
            "severity": severity.name,
            "eventType": actualEventType,
            "isStreaming": true
        ]

        if let metadata = metadata {
            logMetadata.merge(metadata) { _, new in new }
        }

        AppBus.shared.emit(
            type: "log.\(severity.name)",
            appId: appId,
            payload: logMetadata
        )

        return logId
    }

    /// Append content to a streaming log
    func appendToStreamingLog(logId: String, text: String) {
        LogStreamingService.shared.appendMessage(logId: logId, text: text)
    }

    /// Complete a streaming log and persist the final message
    func completeStreamingLog(logId: String, finalMessage: String? = nil) {
        guard let currentState = LogStreamingService.shared.getState(logId: logId) else {
            print("⚠️ [Logger] Attempted to complete unknown streaming log: \(logId)")
            return
        }

        let message = finalMessage ?? currentState.message

        // Mark streaming as complete
        LogStreamingService.shared.completeStreaming(logId: logId, finalMessage: message)

        // Emit completion event with all required fields from the original stream
        AppBus.shared.emit(
            type: "log.\(currentState.severity.name)",
            appId: currentState.appId,
            payload: [
                "appId": currentState.appId,
                "appName": currentState.appName,
                "message": message,
                "severity": currentState.severity.name,
                "eventType": currentState.eventType,
                "streamLogId": logId
            ]
        )
    }

    /// Fail a streaming log with an error
    func failStreamingLog(logId: String, error: String) {
        guard let currentState = LogStreamingService.shared.getState(logId: logId) else {
            // If no streaming state exists, emit a simple error log
            log(error, severity: .error, eventType: "stream_error")
            return
        }

        LogStreamingService.shared.failStreaming(logId: logId, error: error)

        // Emit error event with all required fields
        AppBus.shared.emit(
            type: "log.error",
            appId: currentState.appId,
            payload: [
                "appId": currentState.appId,
                "appName": currentState.appName,
                "message": error,
                "severity": "error",
                "eventType": "stream_error",
                "streamLogId": logId
            ]
        )
    }
}
