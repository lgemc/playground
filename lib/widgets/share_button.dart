import 'package:flutter/material.dart';

import '../services/share_content.dart';
import '../services/share_service.dart';

/// Reusable button for sharing content from list tiles.
/// Renders an IconButton with share icon that triggers the share flow.
class ShareButton extends StatelessWidget {
  final ShareContent content;
  final VoidCallback? onShared;
  final double? iconSize;
  final Color? color;

  const ShareButton({
    super.key,
    required this.content,
    this.onShared,
    this.iconSize,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.share,
        size: iconSize,
        color: color,
      ),
      tooltip: 'Share',
      onPressed: () async {
        final success = await ShareService.instance.share(context, content);
        if (success) {
          onShared?.call();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Shared successfully'),
                duration: Duration(seconds: 1),
              ),
            );
          }
        }
      },
    );
  }
}