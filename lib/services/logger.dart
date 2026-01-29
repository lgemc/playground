import '../core/app_bus.dart';
import '../core/app_event.dart';
import 'log_streaming_service.dart';

/// Log severity levels
enum LogSeverity {
  debug,
  info,
  warning,
  error,
  critical,
}

extension LogSeverityExtension on LogSeverity {
  String get name {
    switch (this) {
      case LogSeverity.debug:
        return 'debug';
      case LogSeverity.info:
        return 'info';
      case LogSeverity.warning:
        return 'warning';
      case LogSeverity.error:
        return 'error';
      case LogSeverity.critical:
        return 'critical';
    }
  }

  static LogSeverity fromString(String value) {
    switch (value.toLowerCase()) {
      case 'debug':
        return LogSeverity.debug;
      case 'info':
        return LogSeverity.info;
      case 'warning':
        return LogSeverity.warning;
      case 'error':
        return LogSeverity.error;
      case 'critical':
        return LogSeverity.critical;
      default:
        return LogSeverity.info;
    }
  }
}

/// Logger interface for apps and services to emit log events.
/// Logs are emitted via the AppBus and can be stored by a log storage service.
class Logger {
  final String appId;
  final String appName;

  Logger({
    required this.appId,
    required this.appName,
  });

  /// Log a message with the given severity and optional metadata
  Future<void> log(
    String message, {
    LogSeverity severity = LogSeverity.info,
    String? eventType,
    Map<String, dynamic>? metadata,
  }) async {
    final logMetadata = <String, dynamic>{
      'appId': appId,
      'appName': appName,
      'message': message,
      'severity': severity.name,
      'eventType': eventType ?? 'general',
      ...?metadata,
    };

    await AppBus.instance.emit(AppEvent.create(
      type: 'log.${severity.name}',
      appId: appId,
      metadata: logMetadata,
    ));
  }

  /// Log a debug message
  Future<void> debug(String message, {String? eventType, Map<String, dynamic>? metadata}) {
    return log(message, severity: LogSeverity.debug, eventType: eventType, metadata: metadata);
  }

  /// Log an info message
  Future<void> info(String message, {String? eventType, Map<String, dynamic>? metadata}) {
    return log(message, severity: LogSeverity.info, eventType: eventType, metadata: metadata);
  }

  /// Log a warning message
  Future<void> warning(String message, {String? eventType, Map<String, dynamic>? metadata}) {
    return log(message, severity: LogSeverity.warning, eventType: eventType, metadata: metadata);
  }

  /// Log an error message
  Future<void> error(String message, {String? eventType, Map<String, dynamic>? metadata}) {
    return log(message, severity: LogSeverity.error, eventType: eventType, metadata: metadata);
  }

  /// Log a critical message
  Future<void> critical(String message, {String? eventType, Map<String, dynamic>? metadata}) {
    return log(message, severity: LogSeverity.critical, eventType: eventType, metadata: metadata);
  }

  // ============================================================
  // Streaming Log Methods
  // ============================================================

  /// Start a streaming log message. Returns the log ID for subsequent updates.
  /// The log will appear in the UI immediately and update as content is appended.
  Future<String> startStreamingLog({
    LogSeverity severity = LogSeverity.info,
    String? eventType,
    Map<String, dynamic>? metadata,
  }) async {
    final logId = '${appId}_${DateTime.now().millisecondsSinceEpoch}';

    // Initialize streaming state
    LogStreamingService.instance.startStreaming(logId);

    // Emit initial event to create the log entry (with empty message)
    final logMetadata = <String, dynamic>{
      'appId': appId,
      'appName': appName,
      'message': '', // Will be updated as content streams
      'severity': severity.name,
      'eventType': eventType ?? 'general',
      'isStreaming': true,
      ...?metadata,
    };

    await AppBus.instance.emit(AppEvent(
      id: logId,
      type: 'log.${severity.name}',
      appId: appId,
      timestamp: DateTime.now(),
      metadata: logMetadata,
    ));

    return logId;
  }

  /// Append content to a streaming log
  void appendToStreamingLog(String logId, String text) {
    LogStreamingService.instance.appendMessage(logId, text);
  }

  /// Complete a streaming log and persist the final message
  Future<void> completeStreamingLog(String logId, {String? finalMessage}) async {
    final currentState = LogStreamingService.instance.getState(logId);
    final message = finalMessage ?? currentState?.message ?? '';

    // Mark streaming as complete
    LogStreamingService.instance.completeStreaming(logId, finalMessage: message);

    // Emit completion event to update stored log entry
    await AppBus.instance.emit(AppEvent.create(
      type: 'log.stream.complete',
      appId: appId,
      metadata: {
        'streamLogId': logId,
        'finalMessage': message,
      },
    ));
  }

  /// Fail a streaming log with an error
  Future<void> failStreamingLog(String logId, String error) async {
    LogStreamingService.instance.failStreaming(logId, error);

    // Emit error event
    await AppBus.instance.emit(AppEvent.create(
      type: 'log.stream.error',
      appId: appId,
      metadata: {
        'streamLogId': logId,
        'error': error,
      },
    ));
  }
}
