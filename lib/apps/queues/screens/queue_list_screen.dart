import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/queue_config.dart';
import '../../../services/queue_service.dart';
import 'dlq_screen.dart';
import 'queue_detail_screen.dart';

/// Screen showing all available queues with their metrics
class QueueListScreen extends StatefulWidget {
  const QueueListScreen({super.key});

  @override
  State<QueueListScreen> createState() => _QueueListScreenState();
}

class _QueueListScreenState extends State<QueueListScreen> {
  Map<String, QueueMetrics> _metrics = {};
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
    // Auto-refresh every 2 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadMetrics();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMetrics() async {
    final metrics = await QueueService.instance.getAllMetrics();
    if (mounted) {
      setState(() {
        _metrics = metrics;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue Debugger'),
        backgroundColor: const Color(0xFF9C27B0),
        actions: [
          IconButton(
            icon: const Icon(Icons.error_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DlqScreen(),
                ),
              );
            },
            tooltip: 'View DLQ',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMetrics,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _metrics.isEmpty
              ? const Center(
                  child: Text(
                    'No queues available',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _metrics.length,
                  itemBuilder: (context, index) {
                    final queueId = _metrics.keys.elementAt(index);
                    final metrics = _metrics[queueId]!;
                    final config = QueueConfigs.getById(queueId);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => QueueDetailScreen(
                                queueId: queueId,
                                config: config!,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          config?.name ?? queueId,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          queueId,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(metrics),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${metrics.messageCount} msgs',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _buildMetricChip(
                                    Icons.hourglass_empty,
                                    'Available',
                                    '${metrics.availableCount}',
                                    Colors.green,
                                  ),
                                  const SizedBox(width: 8),
                                  _buildMetricChip(
                                    Icons.lock,
                                    'Locked',
                                    '${metrics.lockedCount}',
                                    Colors.orange,
                                  ),
                                  const SizedBox(width: 8),
                                  _buildMetricChip(
                                    Icons.people,
                                    'Subscribers',
                                    '${metrics.subscriberCount}',
                                    Colors.blue,
                                  ),
                                ],
                              ),
                              if (config != null) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: config.eventPatterns
                                      .map(
                                        (pattern) => Chip(
                                          label: Text(
                                            pattern,
                                            style: const TextStyle(fontSize: 10),
                                          ),
                                          backgroundColor: Colors.grey[200],
                                          padding: EdgeInsets.zero,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildMetricChip(
      IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(QueueMetrics metrics) {
    if (metrics.messageCount == 0) return Colors.grey;
    if (metrics.messageCount > 100) return Colors.red;
    if (metrics.messageCount > 50) return Colors.orange;
    return Colors.blue;
  }
}
