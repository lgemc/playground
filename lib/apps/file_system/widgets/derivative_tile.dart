import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/derivative_artifact.dart';
import '../services/file_system_storage.dart';
import '../../../models/transcript.dart';
import '../../video_viewer/screens/transcript_viewer_screen.dart';

class DerivativeTile extends StatelessWidget {
  final DerivativeArtifact derivative;
  final VoidCallback onDelete;
  final Future<void> Function()? onApplyRename;

  const DerivativeTile({
    super.key,
    required this.derivative,
    required this.onDelete,
    this.onApplyRename,
  });

  IconData _getIconForType(String type) {
    switch (type) {
      case 'summary':
        return Icons.summarize;
      case 'auto_title':
        return Icons.drive_file_rename_outline;
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
      // For auto_title, show apply rename dialog instead of viewing
      if (derivative.type == 'auto_title' && onApplyRename != null) {
        _showApplyRenameDialog(context, content);
      }
      // For transcript, show special viewer with segments
      else if (derivative.type == 'transcript') {
        try {
          final transcript = Transcript.fromJsonString(content);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TranscriptViewerScreen(
                transcript: transcript,
                fileName: transcript.sourceFile ?? 'Unknown',
              ),
            ),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load transcript: $e')),
          );
        }
      }
      // Default: display markdown content
      else {
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
  }

  Future<void> _showApplyRenameDialog(
    BuildContext context,
    String content,
  ) async {
    // Parse the proposed title from markdown content
    final lines = content.split('\n');
    String? proposedTitle;
    String? originalName;
    bool isApplied = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line == '# Proposed Title' && i + 2 < lines.length) {
        proposedTitle = lines[i + 2].trim();
      } else if (line == '## Original Filename' && i + 1 < lines.length) {
        originalName = lines[i + 1].trim();
      } else if (line == '## Applied' && i + 1 < lines.length) {
        isApplied = lines[i + 1].trim().toLowerCase() == 'true';
      }
    }

    if (proposedTitle == null || originalName == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to parse title from derivative')),
        );
      }
      return;
    }

    if (isApplied) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Title has already been applied')),
        );
      }
      return;
    }

    if (context.mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Apply Title'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Rename file?', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              Text('From: $originalName',
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              Text('To: $proposedTitle',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      );

      if (confirmed == true && onApplyRename != null) {
        await onApplyRename!();
      }
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
