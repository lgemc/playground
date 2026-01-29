import 'dart:async';

/// State of a log message being streamed
enum LogStreamState {
  idle,
  streaming,
  completed,
  error,
}

/// Streaming update for a log message
class LogStreamUpdate {
  final String logId;
  final LogStreamState state;
  final String message;
  final String? error;

  const LogStreamUpdate({
    required this.logId,
    required this.state,
    this.message = '',
    this.error,
  });

  LogStreamUpdate copyWith({
    LogStreamState? state,
    String? message,
    String? error,
  }) {
    return LogStreamUpdate(
      logId: logId,
      state: state ?? this.state,
      message: message ?? this.message,
      error: error ?? this.error,
    );
  }
}

/// Service for broadcasting real-time log message streaming updates to the UI.
/// UI components can subscribe to updates for specific log IDs.
class LogStreamingService {
  static LogStreamingService? _instance;
  static LogStreamingService get instance =>
      _instance ??= LogStreamingService._();

  LogStreamingService._();

  /// Active streams per log ID
  final Map<String, StreamController<LogStreamUpdate>> _controllers = {};

  /// Current state per log ID
  final Map<String, LogStreamUpdate> _currentState = {};

  /// Get the stream of updates for a specific log
  Stream<LogStreamUpdate> streamFor(String logId) {
    _controllers[logId] ??= StreamController<LogStreamUpdate>.broadcast();
    // Emit current state immediately if available (for late subscribers)
    final current = _currentState[logId];
    if (current != null) {
      Future.microtask(() => _controllers[logId]?.add(current));
    }
    return _controllers[logId]!.stream;
  }

  /// Get current state for a log (synchronous)
  LogStreamUpdate? getState(String logId) => _currentState[logId];

  /// Check if a log is currently streaming
  bool isStreaming(String logId) =>
      _currentState[logId]?.state == LogStreamState.streaming;

  /// Get all currently streaming log IDs
  Set<String> get activeStreams => _currentState.entries
      .where((e) => e.value.state == LogStreamState.streaming)
      .map((e) => e.key)
      .toSet();

  /// Start streaming for a log
  void startStreaming(String logId) {
    final update = LogStreamUpdate(
      logId: logId,
      state: LogStreamState.streaming,
    );
    _emit(logId, update);
  }

  /// Append text to a streaming log message
  void appendMessage(String logId, String text) {
    final current = _currentState[logId];
    if (current == null) return;

    final update = current.copyWith(
      message: current.message + text,
    );
    _emit(logId, update);
  }

  /// Set the complete message
  void setMessage(String logId, String message) {
    final current = _currentState[logId];
    if (current == null) return;

    final update = current.copyWith(message: message);
    _emit(logId, update);
  }

  /// Mark streaming as completed
  void completeStreaming(String logId, {String? finalMessage}) {
    final current = _currentState[logId];
    final update = LogStreamUpdate(
      logId: logId,
      state: LogStreamState.completed,
      message: finalMessage ?? current?.message ?? '',
    );
    _emit(logId, update);

    // Clean up after a short delay to allow UI to show final state
    Future.delayed(const Duration(seconds: 2), () {
      _cleanup(logId);
    });
  }

  /// Mark streaming as failed
  void failStreaming(String logId, String error) {
    final update = LogStreamUpdate(
      logId: logId,
      state: LogStreamState.error,
      error: error,
    );
    _emit(logId, update);

    // Clean up after showing error
    Future.delayed(const Duration(seconds: 5), () {
      _cleanup(logId);
    });
  }

  void _emit(String logId, LogStreamUpdate update) {
    _currentState[logId] = update;
    _controllers[logId] ??= StreamController<LogStreamUpdate>.broadcast();
    _controllers[logId]?.add(update);
  }

  void _cleanup(String logId) {
    _currentState.remove(logId);
    _controllers[logId]?.close();
    _controllers.remove(logId);
  }

  /// Dispose all streams
  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
    _currentState.clear();
  }

  /// Reset instance for testing
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }
}
