import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../services/queue_config.dart';
import '../../../services/queue_message.dart';
import '../../../services/queue_service.dart';
import 'dlq_screen.dart';

/// Screen showing detailed view of a specific queue with all messages
class QueueDetailScreen extends StatefulWidget {
  final String queueId;
  final QueueConfig config;

  const QueueDetailScreen({
    super.key,
    required this.queueId,
    required this.config,
  });

  @override
  State<QueueDetailScreen> createState() => _QueueDetailScreenState();
}

class _QueueDetailScreenState extends State<QueueDetailScreen> {
  List<QueueMessage> _messages = [];
  QueueMetrics? _metrics;
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Auto-refresh every 2 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final messages = await QueueService.instance.getMessages(
      queueId: widget.queueId,
      includeLockedMessages: true,
    );
    final metrics = await QueueService.instance.getQueueMetrics(widget.queueId);

    if (mounted) {
      setState(() {
        _messages = messages;
        _metrics = metrics;
        _loading = false;
      });
    }
  }

  Future<void> _retryMessage(QueueMessage message) async {
    try {
      // Release the lock so it can be redelivered
      await QueueService.instance.reject(message.id, requeue: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Message ${message.id} queued for retry'),
            backgroundColor: Colors.green,
          ),
        );
      }

      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to retry message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteMessage(QueueMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text(
            'Are you sure you want to permanently delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await QueueService.instance.acknowledge(message.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message deleted'),
              backgroundColor: Colors.green,
            ),
          );
        }
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete message: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _clearQueue() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Queue'),
        content: Text(
            'Are you sure you want to delete all ${_messages.length} messages from this queue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final count = await QueueService.instance.clearQueue(widget.queueId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cleared $count messages'),
              backgroundColor: Colors.green,
            ),
          );
        }
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to clear queue: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showMessageDetails(QueueMessage message) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Message Details',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    _buildDetailRow('ID', message.id),
                    _buildDetailRow('Queue', message.queueId),
                    _buildDetailRow('Event Type', message.eventType),
                    _buildDetailRow('App ID', message.appId),
                    _buildDetailRow('Timestamp',
                        _formatDateTime(message.timestamp)),
                    _buildDetailRow(
                        'Delivery Count', '${message.deliveryCount}'),
                    _buildDetailRow(
                      'Last Delivered',
                      message.lastDeliveredAt != null
                          ? _formatDateTime(message.lastDeliveredAt!)
                          : 'Never',
                    ),
                    _buildDetailRow('Locked By', message.lockedBy ?? 'None'),
                    _buildDetailRow(
                      'Lock Expires',
                      message.lockExpiresAt != null
                          ? _formatDateTime(message.lockExpiresAt!)
                          : 'N/A',
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Payload',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _formatJson(message.payload),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _retryMessage(message);
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteMessage(message);
                      },
                      icon: const Icon(Icons.delete),
                      label: const Text('Delete'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  String _formatJson(Map<String, dynamic> json) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(json);
    } catch (_) {
      return json.toString();
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config.name),
        backgroundColor: const Color(0xFF9C27B0),
        actions: [
          IconButton(
            icon: const Icon(Icons.error_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DlqScreen(queueId: widget.queueId),
                ),
              );
            },
            tooltip: 'View DLQ',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _messages.isEmpty ? null : _clearQueue,
            tooltip: 'Clear Queue',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Metrics Summary
                if (_metrics != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _buildMetricCard(
                              'Total',
                              '${_metrics!.messageCount}',
                              Icons.inbox,
                              Colors.blue,
                            ),
                            const SizedBox(width: 12),
                            _buildMetricCard(
                              'Available',
                              '${_metrics!.availableCount}',
                              Icons.hourglass_empty,
                              Colors.green,
                            ),
                            const SizedBox(width: 12),
                            _buildMetricCard(
                              'Locked',
                              '${_metrics!.lockedCount}',
                              Icons.lock,
                              Colors.orange,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildMetricCard(
                              'Subscribers',
                              '${_metrics!.subscriberCount}',
                              Icons.people,
                              Colors.purple,
                            ),
                            const SizedBox(width: 12),
                            _buildMetricCard(
                              'Max Retries',
                              '${widget.config.maxRetries}',
                              Icons.replay,
                              Colors.grey,
                            ),
                            const SizedBox(width: 12),
                            _buildMetricCard(
                              'Lock Timeout',
                              '${widget.config.lockTimeoutSeconds}s',
                              Icons.timer,
                              Colors.grey,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                // Messages List
                Expanded(
                  child: _messages.isEmpty
                      ? const Center(
                          child: Text(
                            'No messages in queue',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isLocked = message.lockedBy != null &&
                                (message.lockExpiresAt?.isAfter(DateTime.now()) ??
                                    false);
                            final isDlq =
                                message.deliveryCount >= widget.config.maxRetries;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              color: isDlq
                                  ? Colors.red[50]
                                  : isLocked
                                      ? Colors.orange[50]
                                      : null,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isDlq
                                      ? Colors.red
                                      : isLocked
                                          ? Colors.orange
                                          : Colors.blue,
                                  child: Icon(
                                    isDlq
                                        ? Icons.error
                                        : isLocked
                                            ? Icons.lock
                                            : Icons.message,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  message.eventType,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ID: ${message.id}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    Text(
                                      'Deliveries: ${message.deliveryCount} | ${_formatDateTime(message.timestamp)}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    if (isLocked)
                                      Text(
                                        'Locked by: ${message.lockedBy}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.orange[700],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    if (isDlq)
                                      const Text(
                                        'DLQ - Max retries exceeded',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.refresh,
                                          color: Colors.blue),
                                      onPressed: () => _retryMessage(message),
                                      tooltip: 'Retry',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () => _deleteMessage(message),
                                      tooltip: 'Delete',
                                    ),
                                  ],
                                ),
                                onTap: () => _showMessageDetails(message),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildMetricCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}