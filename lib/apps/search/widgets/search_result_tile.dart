import 'package:flutter/material.dart';
import '../../../core/search_result.dart';

class SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;

  const SearchResultTile({
    super.key,
    required this.result,
    required this.onTap,
  });

  IconData _getIconForType(SearchResultType type) {
    switch (type) {
      case SearchResultType.file:
        return Icons.insert_drive_file;
      case SearchResultType.note:
        return Icons.note;
      case SearchResultType.vocabularyWord:
        return Icons.book;
      case SearchResultType.chat:
        return Icons.chat;
      case SearchResultType.chatMessage:
        return Icons.message;
    }
  }

  Color _getColorForType(SearchResultType type) {
    switch (type) {
      case SearchResultType.file:
        return Colors.blue;
      case SearchResultType.note:
        return Colors.orange;
      case SearchResultType.vocabularyWord:
        return Colors.green;
      case SearchResultType.chat:
        return Colors.purple;
      case SearchResultType.chatMessage:
        return Colors.deepPurple;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _getColorForType(result.type).withOpacity(0.1),
        child: Icon(
          _getIconForType(result.type),
          color: _getColorForType(result.type),
          size: 20,
        ),
      ),
      title: Text(
        result.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result.subtitle != null)
            Text(
              result.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          if (result.preview != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                result.preview!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getColorForType(result.type).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  result.typeLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: _getColorForType(result.type),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (result.timestamp != null) ...[
                const SizedBox(width: 8),
                Text(
                  _formatTimestamp(result.timestamp!),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      isThreeLine: result.preview != null,
      onTap: onTap,
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
}
