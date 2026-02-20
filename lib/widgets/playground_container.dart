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
    final runningApps = runtimeManager.runningApps;

    // If no apps have ever been launched, show the launcher directly.
    if (runningApps.isEmpty) {
      return widget.launcher;
    }

    // Always keep all running apps in the widget tree via IndexedStack so that
    // their internal Navigator state (e.g. course → module → activity) is
    // preserved when the user returns to the launcher and comes back.
    //
    // The launcher lives at index 0. Running apps follow it at index 1+.
    // When currentAppId is null we show the launcher (index 0); otherwise we
    // show the matching app.

    int activeIndex = 0; // default: launcher
    if (currentAppId != null) {
      final appIndex = runningApps.indexWhere((s) => s.appId == currentAppId);
      if (appIndex >= 0) {
        activeIndex = appIndex + 1; // +1 because launcher occupies index 0
      }
    }

    final appWidgets = runningApps.map((appState) {
      final definition = AppRegistry.instance.getAppDefinition(appState.appId);
      final themeColor = definition?.themeColor ?? Colors.blue;
      return Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: themeColor,
            brightness: Theme.of(context).brightness,
          ),
        ),
        child: _AppContainer(
          key: ValueKey(appState.appId),
          appState: appState,
        ),
      );
    }).toList();

    return IndexedStack(
      index: activeIndex,
      children: [
        widget.launcher,
        ...appWidgets,
      ],
    );
  }
}

/// Container for a single app instance that preserves its state.
/// Each app gets its own Navigator so that internal navigation (e.g.
/// course → module → activity) survives app-switching.
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
    // Wrap in a Navigator so each app has its own route stack.
    // This preserves the navigation state (e.g. course → module → activity)
    // when the user switches to another app and comes back.
    return Navigator(
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (context) => widget.appState.instance.build(context),
        settings: settings,
      ),
    );
  }
}
