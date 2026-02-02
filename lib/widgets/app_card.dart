import 'package:flutter/material.dart';
import '../core/app_runtime_manager.dart';
import '../core/app_registry.dart';

/// Card widget representing a running app in the switcher.
class AppCard extends StatelessWidget {
  final AppRuntimeState appState;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const AppCard({
    super.key,
    required this.appState,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final definition = AppRegistry.instance.getAppDefinition(appState.appId);
    if (definition == null) {
      return const SizedBox.shrink();
    }

    final isCurrentApp = AppRuntimeManager.instance.currentAppId == appState.appId;

    return Card(
      elevation: isCurrentApp ? 8 : 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App icon with close button
              Stack(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: definition.themeColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      definition.icon,
                      size: 40,
                      color: definition.themeColor,
                    ),
                  ),
                  Positioned(
                    top: -8,
                    right: -8,
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: onClose,
                      tooltip: 'Close app',
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.errorContainer,
                        foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // App name
              Text(
                definition.name,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Status indicator
              if (isCurrentApp)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Active',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
