import 'package:flutter/material.dart';

import '../core/app_registry.dart';
import '../services/share_content.dart';

/// Bottom sheet that displays available apps to share content with.
/// Shows a grid of app icons that the user can tap to share.
class ShareSheet extends StatelessWidget {
  final ShareContent content;
  final List<String> receiverIds;

  const ShareSheet({
    super.key,
    required this.content,
    required this.receiverIds,
  });

  @override
  Widget build(BuildContext context) {
    final receivers = receiverIds
        .map((id) => AppRegistry.instance.getApp(id))
        .whereType<dynamic>()
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.share),
              const SizedBox(width: 8),
              Text(
                'Share to',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _getContentDescription(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).hintColor,
                ),
          ),
          const SizedBox(height: 16),
          // App grid
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: receivers.map((app) => _AppTile(app: app)).toList(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _getContentDescription() {
    switch (content.type) {
      case ShareContentType.text:
        final text = content.data['text'] as String? ?? '';
        if (text.length > 50) {
          return '"${text.substring(0, 50)}..."';
        }
        return '"$text"';
      case ShareContentType.note:
        final title = content.data['title'] as String? ?? 'Untitled';
        return 'Note: $title';
      case ShareContentType.file:
        final name = content.data['name'] as String? ?? 'Unknown file';
        return 'File: $name';
      case ShareContentType.url:
        final url = content.data['url'] as String? ?? '';
        return url;
      case ShareContentType.json:
        return 'Structured data';
    }
  }
}

class _AppTile extends StatelessWidget {
  final dynamic app;

  const _AppTile({required this.app});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(app.id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 80,
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: (app.themeColor as Color).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                app.icon as IconData,
                size: 28,
                color: app.themeColor as Color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              app.name as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
