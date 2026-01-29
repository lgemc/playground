import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/app_registry.dart';
import '../models/summary.dart';
import '../services/summary_storage_v2.dart';

class SummaryDetailScreen extends StatefulWidget {
  final Summary summary;

  const SummaryDetailScreen({
    super.key,
    required this.summary,
  });

  @override
  State<SummaryDetailScreen> createState() => _SummaryDetailScreenState();
}

class _SummaryDetailScreenState extends State<SummaryDetailScreen> {
  late Summary _summary;
  final _storage = SummaryStorageV2.instance;

  @override
  void initState() {
    super.initState();
    _summary = widget.summary;
    if (_summary.isProcessing) {
      _startAutoRefresh();
    }
  }

  void _startAutoRefresh() {
    Future.delayed(const Duration(seconds: 1), () async {
      if (!mounted) return;

      // Reload the summary from storage
      final updated = await _storage.get(_summary.id);
      if (updated != null && mounted) {
        setState(() => _summary = updated);

        // Continue refreshing if still processing
        if (_summary.isProcessing) {
          _startAutoRefresh();
        }
      }
    });
  }

  Future<void> _openSourceFile() async {
    // Navigate to file system app and open the source file
    final fileSystemApp = AppRegistry.instance.getApp('file_system');
    if (fileSystemApp != null) {
      // TODO: Implement navigation to specific file in file system app
      // For now, just navigate to the app
      AppRegistry.instance.openApp(context, fileSystemApp);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: _openSourceFile,
            tooltip: 'Open source file',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_summary.isProcessing) {
      return _buildProcessingView();
    } else if (_summary.isFailed) {
      return _buildErrorView();
    } else if (_summary.isCompleted) {
      return _buildSummaryView();
    } else {
      return _buildPendingView();
    }
  }

  Widget _buildProcessingView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFileInfo(),
          const SizedBox(height: 24),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                'Generating summary...',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_summary.summaryText.isNotEmpty) ...[
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Preview (partial):',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            ),
            const SizedBox(height: 8),
            Markdown(
              data: _summary.summaryText,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Summary generation failed',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _summary.errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.schedule, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'Summary pending',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Your summary will be generated shortly',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFileInfo(),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Markdown(
            data: _summary.summaryText,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
          ),
        ],
      ),
    );
  }

  Widget _buildFileInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.picture_as_pdf, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _summary.fileName,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Created ${_formatDate(_summary.createdAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
