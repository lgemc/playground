import 'package:flutter/material.dart';
import '../models/summary.dart';
import '../services/summary_storage.dart';
import 'summary_detail_screen.dart';
import '../widgets/summary_list_tile.dart';

class SummariesScreen extends StatefulWidget {
  const SummariesScreen({super.key});

  @override
  State<SummariesScreen> createState() => _SummariesScreenState();
}

class _SummariesScreenState extends State<SummariesScreen> {
  final _storage = SummaryStorage.instance;
  List<Summary> _summaries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSummaries();
    _startAutoRefresh();
  }

  Future<void> _loadSummaries() async {
    setState(() => _isLoading = true);
    try {
      final summaries = await _storage.getAll();
      if (mounted) {
        setState(() {
          _summaries = summaries;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading summaries: $e')),
        );
      }
    }
  }

  void _startAutoRefresh() {
    // Auto-refresh every 2 seconds to show processing progress
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _loadSummaries();
        _startAutoRefresh();
      }
    });
  }

  Future<void> _deleteSummary(Summary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Summary'),
        content: Text('Delete summary of "${summary.fileName}"?'),
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
      await _storage.delete(summary.id);
      _loadSummaries();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Summaries'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSummaries,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _summaries.isEmpty
              ? _buildEmptyState()
              : _buildSummariesList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.summarize, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No summaries yet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Share a PDF from the File System app',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummariesList() {
    return RefreshIndicator(
      onRefresh: _loadSummaries,
      child: ListView.builder(
        itemCount: _summaries.length,
        padding: const EdgeInsets.all(8),
        itemBuilder: (context, index) {
          final summary = _summaries[index];
          return SummaryListTile(
            summary: summary,
            onTap: () => _navigateToDetail(summary),
            onDelete: () => _deleteSummary(summary),
          );
        },
      ),
    );
  }

  void _navigateToDetail(Summary summary) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SummaryDetailScreen(summary: summary),
      ),
    ).then((_) => _loadSummaries());
  }
}
