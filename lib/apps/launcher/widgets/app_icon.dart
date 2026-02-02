import 'package:flutter/material.dart';
import '../../../core/app_registry.dart';
import '../../../core/app_runtime_manager.dart';

/// Widget that displays an app icon in the launcher grid.
/// Shows the app icon centered with the name below, and a running indicator.
class AppIcon extends StatefulWidget {
  final AppDefinition appDefinition;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const AppIcon({
    super.key,
    required this.appDefinition,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<AppIcon> {
  @override
  void initState() {
    super.initState();
    AppRuntimeManager.instance.addListener(_onRuntimeChanged);
  }

  @override
  void dispose() {
    AppRuntimeManager.instance.removeListener(_onRuntimeChanged);
    super.dispose();
  }

  void _onRuntimeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = AppRuntimeManager.instance.isRunning(widget.appDefinition.id);

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: widget.appDefinition.themeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  widget.appDefinition.icon,
                  size: 32,
                  color: widget.appDefinition.themeColor,
                ),
              ),
              // Running indicator
              if (isRunning)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.appDefinition.name,
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