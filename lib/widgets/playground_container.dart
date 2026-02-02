import 'package:flutter/material.dart';
import '../core/app_runtime_manager.dart';
import '../core/app_registry.dart';

/// Main container widget that manages the stack of running apps.
/// Only renders the current foreground app while preserving background app states.
class PlaygroundContainer extends StatefulWidget {
  final Widget launcher;

  const PlaygroundContainer({
    super.key,
    required this.launcher,
  });

  @override
  State<PlaygroundContainer> createState() => _PlaygroundContainerState();
}

class _PlaygroundContainerState extends State<PlaygroundContainer> {
  @override
  void initState() {
    super.initState();
    // Listen to runtime manager changes
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
    final runtimeManager = AppRuntimeManager.instance;
    final currentAppId = runtimeManager.currentAppId;

    // Wrap entire container with back button handling
    return PopScope(
      canPop: currentAppId == null, // Only allow pop when launcher is showing
      onPopInvokedWithResult: (didPop, result) async {
        // If we already popped, do nothing
        if (didPop) return;

        // If an app is running, return to launcher (keep app in background)
        if (currentAppId != null) {
          runtimeManager.returnToLauncher();
        }
      },
      child: _buildContent(context, runtimeManager, currentAppId),
    );
  }

  Widget _buildContent(BuildContext context, AppRuntimeManager runtimeManager, String? currentAppId) {
    // If no app is running, show the launcher
    if (currentAppId == null) {
      return widget.launcher;
    }

    final currentAppState = runtimeManager.getAppState(currentAppId);
    if (currentAppState == null) {
      return widget.launcher;
    }

    // Build the current app with its theme
    final definition = AppRegistry.instance.getAppDefinition(currentAppId);
    if (definition == null) {
      return widget.launcher;
    }

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: definition.themeColor,
          brightness: Theme.of(context).brightness,
        ),
      ),
      child: _AppContainer(
        key: ValueKey(currentAppId),
        appState: currentAppState,
      ),
    );
  }
}

/// Container for a single app instance that preserves its state
class _AppContainer extends StatefulWidget {
  final AppRuntimeState appState;

  const _AppContainer({
    super.key,
    required this.appState,
  });

  @override
  State<_AppContainer> createState() => _AppContainerState();
}

class _AppContainerState extends State<_AppContainer>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return widget.appState.instance.build(context);
  }
}
