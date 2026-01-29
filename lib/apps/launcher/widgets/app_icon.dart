import 'package:flutter/material.dart';
import '../../../core/sub_app.dart';

/// Widget that displays an app icon in the launcher grid.
/// Shows the app icon centered with the name below.
class AppIcon extends StatelessWidget {
  final SubApp app;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const AppIcon({
    super.key,
    required this.app,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: app.themeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              app.icon,
              size: 32,
              color: app.themeColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            app.name,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}