import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/logger.dart';
import '../../../services/log_streaming_service.dart';
import '../../../core/logs_storage.dart';

class LogItem extends StatefulWidget {
  final LogEntry log;
  final bool isSelected;
  final VoidCallback onTap;

  const LogItem({
    super.key,
    required this.log,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<LogItem> createState() => _LogItemState();
}

class _LogItemState extends State<LogItem> {
  StreamSubscription<LogStreamUpdate>? _subscription;
  LogStreamUpdate? _streamUpdate;

  @override
  void initState() {
    super.initState();
    _subscribeToStreaming();
  }

  @override
  void didUpdateWidget(LogItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.log.id != widget.log.id) {
      _subscription?.cancel();
      _subscribeToStreaming();
    }
  }

  void _subscribeToStreaming() {
    final streaming = LogStreamingService.instance;
    _streamUpdate = streaming.getState(widget.log.id);
    _subscription = streaming.streamFor(widget.log.id).listen((update) {
      if (mounted) {
        setState(() => _streamUpdate = update);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Color _getSeverityColor(LogSeverity severity) {
    switch (severity) {
      case LogSeverity.debug:
        return Colors.grey;
      case LogSeverity.info:
        return Colors.blue;
      case LogSeverity.warning:
        return Colors.orange;
      case LogSeverity.error:
        return Colors.red;
      case LogSeverity.critical:
        return Colors.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final severityColor = _getSeverityColor(widget.log.severity);
    final timeFormat = DateFormat('HH:mm:ss');
    final dateFormat = DateFormat('MMM dd');

    // Check streaming state
    final isStreaming = _streamUpdate?.state == LogStreamState.streaming;
    final streamedMessage = _streamUpdate?.message ?? '';

    // Show streamed message if streaming, otherwise show saved message
    final displayMessage = isStreaming ? streamedMessage : widget.log.message;

    return Material(
      color: widget.isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Animated indicator for streaming logs
              isStreaming
                  ? _buildStreamingIndicator(context, severityColor)
                  : Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 6, right: 12),
                      decoration: BoxDecoration(
                        color: severityColor,
                        shape: BoxShape.circle,
                      ),
                    ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: severityColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.log.severity.name.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: severityColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.log.appName,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        if (isStreaming) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          '${dateFormat.format(widget.log.timestamp)} ${timeFormat.format(widget.log.timestamp)}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayMessage.isEmpty ? '...' : displayMessage,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontStyle: isStreaming ? FontStyle.italic : null,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.log.eventType != 'general') ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.log.eventType,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                              fontStyle: FontStyle.italic,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStreamingIndicator(BuildContext context, Color severityColor) {
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(top: 6, right: 12),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: severityColor.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
          ),
          Center(
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: severityColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
