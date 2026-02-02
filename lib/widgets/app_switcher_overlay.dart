import 'package:flutter/material.dart';
import '../core/app_runtime_manager.dart';
import 'app_card.dart';

/// Overlay that shows all running apps in a switcher interface.
/// Users can tap to switch to an app or close apps.
class AppSwitcherOverlay extends StatefulWidget {
  const AppSwitcherOverlay({super.key});

  @override
  State<AppSwitcherOverlay> createState() => _AppSwitcherOverlayState();
}

class _AppSwitcherOverlayState extends State<AppSwitcherOverlay> {
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

  void _switchToApp(String appId) {
    AppRuntimeManager.instance.switchToApp(appId);
    Navigator.of(context).pop(); // Close the overlay
  }

  Future<void> _closeApp(String appId) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close App'),
        content: const Text('Are you sure you want to close this app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Close'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await AppRuntimeManager.instance.closeApp(appId);

      // If no more apps, close the overlay and return to launcher
      if (AppRuntimeManager.instance.runningApps.isEmpty && mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _goHome() {
    AppRuntimeManager.instance.returnToLauncher();
    Navigator.of(context).pop(); // Close the overlay
  }

  @override
  Widget build(BuildContext context) {
    final runningApps = AppRuntimeManager.instance.runningApps;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 400),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'Running Apps',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    // Home button
                    IconButton(
                      icon: const Icon(Icons.home),
                      onPressed: _goHome,
                      tooltip: 'Home',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // App cards
              Flexible(
                child: runningApps.isEmpty
                    ? _buildEmptyState()
                    : _buildAppList(runningApps),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.apps,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No running apps',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppList(List<AppRuntimeState> apps) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final appState in apps) ...[
            AppCard(
              appState: appState,
              onTap: () => _switchToApp(appState.appId),
              onClose: () => _closeApp(appState.appId),
            ),
            const SizedBox(width: 16),
          ],
        ],
      ),
    );
  }
}
