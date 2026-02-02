import 'package:flutter/foundation.dart';
import 'sub_app.dart';

/// Manages the runtime state of running sub-apps.
/// Tracks which apps are running, handles lifecycle, and manages app switching.
class AppRuntimeManager extends ChangeNotifier {
  AppRuntimeManager._();

  static final AppRuntimeManager _instance = AppRuntimeManager._();
  static AppRuntimeManager get instance => _instance;

  final Map<String, AppRuntimeState> _runningApps = {};
  String? _currentAppId;

  /// Get the currently active (foreground) app ID
  String? get currentAppId => _currentAppId;

  /// Get list of all running apps
  List<AppRuntimeState> get runningApps => _runningApps.values.toList();

  /// Check if an app is currently running
  bool isRunning(String appId) => _runningApps.containsKey(appId);

  /// Launch an app (or switch to it if already running)
  Future<void> launchApp(String appId, SubApp Function() appFactory) async {
    if (_runningApps.containsKey(appId)) {
      // App is already running, just switch to it
      switchToApp(appId);
      return;
    }

    // Create new instance
    final instance = appFactory();
    instance.onInit();

    // Add to running apps
    _runningApps[appId] = AppRuntimeState(
      appId: appId,
      instance: instance,
      launchedAt: DateTime.now(),
    );

    // Make it the current app
    switchToApp(appId);
  }

  /// Switch to an already running app
  void switchToApp(String appId) {
    if (!_runningApps.containsKey(appId)) {
      throw StateError('App $appId is not running');
    }

    final previousAppId = _currentAppId;

    // Pause previous app if any
    if (previousAppId != null && _runningApps.containsKey(previousAppId)) {
      _runningApps[previousAppId]!.instance.onPause();
    }

    // Switch to new app
    _currentAppId = appId;
    _runningApps[appId]!.instance.onResume();

    notifyListeners();
  }

  /// Close a running app
  Future<void> closeApp(String appId) async {
    if (!_runningApps.containsKey(appId)) {
      return;
    }

    final appState = _runningApps[appId]!;
    appState.instance.onDispose();
    _runningApps.remove(appId);

    // If we closed the current app, switch to another one or clear current
    if (_currentAppId == appId) {
      if (_runningApps.isNotEmpty) {
        // Switch to the most recently launched app
        final latestApp = _runningApps.values
            .reduce((a, b) => a.launchedAt.isAfter(b.launchedAt) ? a : b);
        _currentAppId = latestApp.appId;
        latestApp.instance.onResume();
      } else {
        _currentAppId = null;
      }
    }

    notifyListeners();
  }

  /// Close all running apps
  Future<void> closeAllApps() async {
    final appIds = _runningApps.keys.toList();
    for (final appId in appIds) {
      await closeApp(appId);
    }
  }

  /// Return to launcher (keep apps running in background)
  void returnToLauncher() {
    if (_currentAppId != null) {
      _runningApps[_currentAppId]!.instance.onPause();
      _currentAppId = null;
      notifyListeners();
    }
  }

  /// Get runtime state for a specific app
  AppRuntimeState? getAppState(String appId) => _runningApps[appId];
}

/// Represents the runtime state of a running sub-app
class AppRuntimeState {
  final String appId;
  final SubApp instance;
  final DateTime launchedAt;

  AppRuntimeState({
    required this.appId,
    required this.instance,
    required this.launchedAt,
  });
}
