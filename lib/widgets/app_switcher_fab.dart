import 'package:flutter/material.dart';
import '../core/app_runtime_manager.dart';
import 'app_switcher_overlay.dart';

/// Floating action button for opening the app switcher.
/// Always visible on top of all apps when multiple apps are running.
/// Draggable and snaps to nearest corner when released.
class AppSwitcherFAB extends StatefulWidget {
  const AppSwitcherFAB({super.key});

  @override
  State<AppSwitcherFAB> createState() => _AppSwitcherFABState();
}

class _AppSwitcherFABState extends State<AppSwitcherFAB> {
  Offset _position = const Offset(1.0, 0.5); // Start at mid-right (x: right edge, y: center)

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

  void _openSwitcher() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => const AppSwitcherOverlay(),
    );
  }

  /// Snaps the position to the nearest edge (border)
  Offset _snapToEdge(Offset position) {
    // Calculate distance to each edge
    final distanceToLeft = position.dx;
    final distanceToRight = 1.0 - position.dx;
    final distanceToTop = position.dy;
    final distanceToBottom = 1.0 - position.dy;

    // Find the minimum distance
    final minDistance = [
      distanceToLeft,
      distanceToRight,
      distanceToTop,
      distanceToBottom,
    ].reduce((a, b) => a < b ? a : b);

    // Snap to the closest edge, keeping position along that edge
    if (minDistance == distanceToLeft) {
      return Offset(0.0, position.dy);
    } else if (minDistance == distanceToRight) {
      return Offset(1.0, position.dy);
    } else if (minDistance == distanceToTop) {
      return Offset(position.dx, 0.0);
    } else {
      return Offset(position.dx, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runningApps = AppRuntimeManager.instance.runningApps;

    // Only show FAB if there are running apps
    if (runningApps.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final fabSize = 56.0; // Standard FAB size
        final padding = 16.0;

        // Calculate actual position based on screen size and edge
        final isOnLeftEdge = _position.dx == 0.0;
        final isOnTopEdge = _position.dy == 0.0;
        final isOnRightEdge = _position.dx == 1.0;
        final isOnBottomEdge = _position.dy == 1.0;

        // Position along edges
        double? left;
        double? top;

        if (isOnLeftEdge) {
          left = padding;
          top = _position.dy * (constraints.maxHeight - fabSize - 2 * padding) + padding;
        } else if (isOnRightEdge) {
          left = constraints.maxWidth - fabSize - padding;
          top = _position.dy * (constraints.maxHeight - fabSize - 2 * padding) + padding;
        } else if (isOnTopEdge) {
          left = _position.dx * (constraints.maxWidth - fabSize - 2 * padding) + padding;
          top = padding;
        } else if (isOnBottomEdge) {
          left = _position.dx * (constraints.maxWidth - fabSize - 2 * padding) + padding;
          top = constraints.maxHeight - fabSize - padding;
        }

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Draggable(
                feedback: Material(
                  color: Colors.transparent,
                  child: FloatingActionButton(
                    onPressed: null,
                    child: Badge(
                      label: Text('${runningApps.length}'),
                      child: const Icon(Icons.apps),
                    ),
                  ),
                ),
                childWhenDragging: const SizedBox.shrink(),
                onDragEnd: (details) {
                  setState(() {
                    // Convert pixel position to normalized position (0.0 to 1.0)
                    final normalizedX = details.offset.dx / constraints.maxWidth;
                    final normalizedY = details.offset.dy / constraints.maxHeight;
                    // Snap to nearest edge
                    _position = _snapToEdge(Offset(normalizedX, normalizedY));
                  });
                },
                child: FloatingActionButton(
                  onPressed: _openSwitcher,
                  tooltip: 'App Switcher',
                  child: Badge(
                    label: Text('${runningApps.length}'),
                    child: const Icon(Icons.apps),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
