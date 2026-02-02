import 'package:flutter/material.dart';
import '../../core/app_registry.dart';
import 'widgets/app_icon.dart';
import 'widgets/global_sync_dialog.dart';

/// Main screen for the launcher displaying all registered apps in a grid.
class LauncherScreen extends StatelessWidget {
  const LauncherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appDefinitions = AppRegistry.instance.appDefinitions;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: appDefinitions.isEmpty ? _buildEmptyState(context) : _buildAppGrid(context, appDefinitions),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showGlobalSync(context),
        tooltip: 'Sync Database',
        child: const Icon(Icons.sync),
      ),
    );
  }

  void _showGlobalSync(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const GlobalSyncDialog(),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
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
            'No apps installed',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppGrid(BuildContext context, List<AppDefinition> appDefinitions) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _getCrossAxisCount(constraints.maxWidth);

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 24,
            crossAxisSpacing: 24,
            childAspectRatio: 0.85,
          ),
          itemCount: appDefinitions.length,
          itemBuilder: (context, index) {
            final appDef = appDefinitions[index];
            return AppIcon(
              appDefinition: appDef,
              onTap: () => AppRegistry.instance.launchApp(appDef.id),
            );
          },
        );
      },
    );
  }

  int _getCrossAxisCount(double width) {
    if (width < 400) return 4;
    if (width < 600) return 5;
    if (width < 900) return 6;
    return 8;
  }
}
