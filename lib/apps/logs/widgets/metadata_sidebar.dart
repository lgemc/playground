import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/logger.dart';
import '../../../services/log_streaming_service.dart';
import '../../../core/logs_storage.dart';

class MetadataSidebar extends StatefulWidget {
  final LogEntry? log;
  final VoidCallback onClose;

  const MetadataSidebar({
    super.key,
    required this.log,
    required this.onClose,
  });

  @override
  State<MetadataSidebar> createState() => _MetadataSidebarState();
}

class _MetadataSidebarState extends State<MetadataSidebar> {
  StreamSubscription<LogStreamUpdate>? _subscription;
  LogStreamUpdate? _streamUpdate;

  @override
  void initState() {
    super.initState();
    _subscribeToStreaming();
  }

  @override
  void didUpdateWidget(MetadataSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.log?.id != widget.log?.id) {
      _subscription?.cancel();
      _subscribeToStreaming();
    }
  }

  void _subscribeToStreaming() {
    _streamUpdate = null;
    if (widget.log == null) return;

    final streaming = LogStreamingService.instance;
    _streamUpdate = streaming.getState(widget.log!.id);
    _subscription = streaming.streamFor(widget.log!.id).listen((update) {
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
    final screenWidth = MediaQuery.of(context).size.width;
    final sidebarWidth = screenWidth * 0.6;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      top: 0,
      bottom: 0,
      right: widget.log != null ? 0 : -sidebarWidth,
      width: sidebarWidth,
      child: Material(
        elevation: 16,
        child: Container(
          color: Theme.of(context).colorScheme.surface,
          child: widget.log != null ? _buildContent(context) : const SizedBox(),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy HH:mm:ss');
    final severityColor = _getSeverityColor(widget.log!.severity);

    // Check streaming state
    final isStreaming = _streamUpdate?.state == LogStreamState.streaming;
    final streamedMessage = _streamUpdate?.message ?? '';
    final displayMessage = isStreaming ? streamedMessage : widget.log!.message;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, severityColor, isStreaming),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(context, 'Timestamp', dateFormat.format(widget.log!.timestamp)),
                _buildInfoRow(context, 'App', widget.log!.appName),
                _buildInfoRow(context, 'App ID', widget.log!.appId),
                _buildInfoRow(context, 'Severity', widget.log!.severity.name.toUpperCase()),
                _buildInfoRow(context, 'Event Type', widget.log!.eventType),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'Message',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
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
                      const SizedBox(width: 4),
                      Text(
                        'Streaming...',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: isStreaming
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                          )
                        : null,
                  ),
                  child: SelectableText(
                    displayMessage.isEmpty ? '...' : displayMessage,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontStyle: isStreaming ? FontStyle.italic : null,
                        ),
                  ),
                ),
                if (widget.log!.metadata.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Metadata',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      _formatMetadata(widget.log!.metadata),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, Color severityColor, bool isStreaming) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: severityColor.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          isStreaming
              ? _buildStreamingIndicator(severityColor)
              : Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: severityColor,
                    shape: BoxShape.circle,
                  ),
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Log Details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildStreamingIndicator(Color severityColor) {
    return SizedBox(
      width: 12,
      height: 12,
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
              width: 6,
              height: 6,
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

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _formatMetadata(Map<String, dynamic> metadata) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(metadata);
  }
}
