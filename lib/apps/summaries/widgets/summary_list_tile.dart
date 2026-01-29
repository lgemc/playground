import 'package:flutter/material.dart';
import '../models/summary.dart';

class SummaryListTile extends StatelessWidget {
  final Summary summary;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const SummaryListTile({
    super.key,
    required this.summary,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      child: ListTile(
        onTap: summary.isCompleted ? onTap : null,
        leading: _buildLeading(),
        title: Text(
          summary.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _buildSubtitle(context),
        trailing: summary.isCompleted
            ? IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              )
            : null,
      ),
    );
  }

  Widget _buildLeading() {
    if (summary.isPending) {
      return const CircleAvatar(
        backgroundColor: Colors.orange,
        child: Icon(Icons.schedule, color: Colors.white, size: 20),
      );
    } else if (summary.isProcessing) {
      return const CircleAvatar(
        backgroundColor: Colors.blue,
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
      );
    } else if (summary.isCompleted) {
      return const CircleAvatar(
        backgroundColor: Colors.green,
        child: Icon(Icons.check, color: Colors.white, size: 20),
      );
    } else {
      return const CircleAvatar(
        backgroundColor: Colors.red,
        child: Icon(Icons.error_outline, color: Colors.white, size: 20),
      );
    }
  }

  Widget _buildSubtitle(BuildContext context) {
    String statusText;
    if (summary.isPending) {
      statusText = 'Pending...';
    } else if (summary.isProcessing) {
      statusText = 'Generating summary...';
    } else if (summary.isCompleted) {
      final wordCount = summary.summaryText.split(RegExp(r'\s+')).length;
      statusText = 'Completed • $wordCount words';
    } else {
      statusText = 'Failed: ${summary.errorMessage ?? "Unknown error"}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(statusText),
        const SizedBox(height: 4),
        Text(
          _formatDate(summary.createdAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }
}
