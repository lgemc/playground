import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/derivative_artifact.dart';
import '../services/file_system_storage.dart';

class DerivativeTile extends StatelessWidget {
  final DerivativeArtifact derivative;
  final VoidCallback onDelete;

  const DerivativeTile({
    super.key,
    required this.derivative,
    required this.onDelete,
  });

  IconData _getIconForType(String type) {
    switch (type) {
      case 'summary':
        return Icons.summarize;
      case 'transcript':
        return Icons.transcribe;
      case 'translation':
        return Icons.translate;
      default:
        return Icons.auto_awesome;
    }
  }

  Color _getColorForStatus(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'processing':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildStatusWidget(String status) {
    if (status == 'processing') {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Processing'),
        ],
      );
    }

    return Chip(
      label: Text(status.toUpperCase()),
      backgroundColor: _getColorForStatus(status),
      labelStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
      padding: EdgeInsets.zero,
    );
  }

  Future<void> _openDerivative(BuildContext context) async {
    if (derivative.status != 'completed') {
      return;
    }

    // Get the content
    final content = await FileSystemStorage.instance
        .getDerivativeContent(derivative.id);

    if (context.mounted) {
      // Display markdown content
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text(derivative.type.toUpperCase()),
            ),
            body: Markdown(
              data: content,
              selectable: true,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(derivative.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Derivative'),
            content: Text(
              'Are you sure you want to delete this ${derivative.type}?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        onDelete();
      },
      child: Card(
        child: ListTile(
          leading: Icon(
            _getIconForType(derivative.type),
            color: _getColorForStatus(derivative.status),
          ),
          title: Text(
            derivative.type.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: derivative.status == 'failed'
              ? Text(
                  derivative.errorMessage ?? 'Unknown error',
                  style: const TextStyle(color: Colors.red),
                )
              : Text(
                  'Created ${_formatDate(derivative.createdAt)}',
                ),
          trailing: _buildStatusWidget(derivative.status),
          onTap: () => _openDerivative(context),
          enabled: derivative.status == 'completed',
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }
}
