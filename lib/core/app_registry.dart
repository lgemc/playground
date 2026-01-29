import 'package:flutter/material.dart';
import '../services/config_service.dart';
import '../services/share_service.dart';
import 'sub_app.dart';

/// Central registry that discovers, registers, and manages all sub-apps.
/// Provides navigation between apps and metadata for the launcher.
class AppRegistry {
  AppRegistry._();

  static final AppRegistry _instance = AppRegistry._();
  static AppRegistry get instance => _instance;

  final Map<String, SubApp> _apps = {};
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Get all registered apps
  List<SubApp> get apps => _apps.values.toList();

  /// Register a sub-app
  void register(SubApp app) async {
    _apps[app.id] = app;
    await ConfigService.instance.loadAppOverrides(app.id);
    app.onInit();

    // Register share receivers if app accepts any content types
    if (app.acceptedShareTypes.isNotEmpty) {
      ShareService.instance.registerReceiver(app.id, app.acceptedShareTypes);
    }
  }

  /// Get a specific app by ID
  SubApp? getApp(String id) => _apps[id];

  /// Navigate to a specific sub-app
  void openApp(BuildContext context, SubApp app) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _SubAppWrapper(app: app),
      ),
    );
  }

  /// Return to the launcher (pop current app)
  void returnToLauncher(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

/// Wrapper widget that provides consistent styling for sub-apps
class _SubAppWrapper extends StatelessWidget {
  final SubApp app;

  const _SubAppWrapper({required this.app});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: app.themeColor,
          brightness: Theme.of(context).brightness,
        ),
      ),
      child: app.build(context),
    );
  }
}
