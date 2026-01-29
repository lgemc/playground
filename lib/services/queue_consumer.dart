import 'dart:async';

import 'queue_message.dart';
import 'queue_service.dart';

/// Abstract base class for queue consumers.
/// Implement this to create a service that processes messages from a specific queue.
abstract class QueueConsumer {
  /// Unique identifier for this consumer
  String get id;

  /// Human-readable name for this consumer
  String get name;

  /// The queue ID this consumer processes messages from
  String get queueId;

  /// How often to poll for new messages (in milliseconds)
  int get pollIntervalMs => 1000;

  Timer? _pollTimer;
  bool _isProcessing = false;
  bool _isRunning = false;

  /// Whether this consumer is currently running
  bool get isRunning => _isRunning;

  /// Start consuming messages from the queue
  void start() {
    if (_isRunning) return;
    _isRunning = true;

    // Register with queue service for push notifications
    QueueService.instance.subscribe(
      id: id,
      queueId: queueId,
      callback: _handleMessage,
      name: name,
    );

    // Also poll periodically in case we miss notifications
    _pollTimer = Timer.periodic(
      Duration(milliseconds: pollIntervalMs),
      (_) => _pollForMessages(),
    );

    onStart();
  }

  /// Stop consuming messages
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;

    _pollTimer?.cancel();
    _pollTimer = null;

    QueueService.instance.unsubscribe(id);

    onStop();
  }

  /// Poll for available messages
  Future<void> _pollForMessages() async {
    if (_isProcessing || !_isRunning) return;
    _isProcessing = true;

    try {
      while (_isRunning) {
        final message = await QueueService.instance.fetchMessage(
          queueId: queueId,
          consumerId: id,
        );

        if (message == null) break;

        final success = await _handleMessage(message);
        if (success) {
          await QueueService.instance.acknowledge(message.id);
        } else {
          await QueueService.instance.reject(message.id);
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Handle a single message
  Future<bool> _handleMessage(QueueMessage message) async {
    try {
      return await processMessage(message);
    } catch (e) {
      onError(message, e);
      return false;
    }
  }

  /// Process a message from the queue.
  /// Return true if processing was successful (message will be acknowledged).
  /// Return false if processing failed (message will be rejected and requeued).
  Future<bool> processMessage(QueueMessage message);

  /// Called when the consumer starts
  void onStart() {}

  /// Called when the consumer stops
  void onStop() {}

  /// Called when an error occurs during message processing
  void onError(QueueMessage message, Object error) {}
}

/// Simple consumer that wraps a callback function
class CallbackQueueConsumer extends QueueConsumer {
  @override
  final String id;

  @override
  final String name;

  @override
  final String queueId;

  @override
  final int pollIntervalMs;

  final Future<bool> Function(QueueMessage message) _callback;
  final void Function(QueueMessage message, Object error)? _onError;

  CallbackQueueConsumer({
    required this.id,
    required this.name,
    required this.queueId,
    required Future<bool> Function(QueueMessage message) callback,
    void Function(QueueMessage message, Object error)? onError,
    this.pollIntervalMs = 1000,
  })  : _callback = callback,
        _onError = onError;

  @override
  Future<bool> processMessage(QueueMessage message) => _callback(message);

  @override
  void onError(QueueMessage message, Object error) {
    _onError?.call(message, error);
  }
}