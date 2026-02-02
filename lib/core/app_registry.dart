import 'package:flutter/material.dart';
import '../services/config_service.dart';
import '../services/share_service.dart';
import '../services/share_content.dart';
import 'sub_app.dart';
import 'app_runtime_manager.dart';

/// Represents a registered app definition (factory for creating instances)
class AppDefinition {
  final String id;
  final String name;
  final IconData icon;
  final Color themeColor;
  final List<ShareContentType> acceptedShareTypes;
  final SubApp Function() factory;

  AppDefinition({
    required this.id,
    required this.name,
    required this.icon,
    required this.themeColor,
    required this.acceptedShareTypes,
    required this.factory,
  });
}

/// Central registry that discovers, registers, and manages all sub-apps.
/// Provides navigation between apps and metadata for the launcher.
class AppRegistry {
  AppRegistry._();

  static final AppRegistry _instance = AppRegistry._();
  static AppRegistry get instance => _instance;

  final Map<String, AppDefinition> _appDefinitions = {};
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Get all registered app definitions
  List<AppDefinition> get appDefinitions => _appDefinitions.values.toList();

  /// Get all registered apps (for backward compatibility - returns factories)
  List<SubApp> get apps => _appDefinitions.values.map((def) => def.factory()).toList();

  /// Register a sub-app (accepts instance for backward compatibility)
  void register(SubApp app) async {
    // Create a factory that returns the app instance
    // Note: For proper multi-app support, pass factories to registerFactory instead
    _appDefinitions[app.id] = AppDefinition(
      id: app.id,
      name: app.name,
      icon: app.icon,
      themeColor: app.themeColor,
      acceptedShareTypes: app.acceptedShareTypes,
      factory: () => app,
    );

    await ConfigService.instance.loadAppOverrides(app.id);
    app.onInit();

    // Register share receivers if app accepts any content types
    if (app.acceptedShareTypes.isNotEmpty) {
      ShareService.instance.registerReceiver(app.id, app.acceptedShareTypes);
    }
  }

  /// Register a sub-app factory (preferred method for multi-app support)
  void registerFactory(
    String id,
    String name,
    IconData icon,
    Color themeColor,
    SubApp Function() factory, {
    List<ShareContentType> acceptedShareTypes = const [],
  }) async {
    _appDefinitions[id] = AppDefinition(
      id: id,
      name: name,
      icon: icon,
      themeColor: themeColor,
      acceptedShareTypes: acceptedShareTypes,
      factory: factory,
    );

    await ConfigService.instance.loadAppOverrides(id);

    // Initialize one instance to set up config defaults
    final instance = factory();
    instance.onInit();
    instance.onDispose();

    // Register share receivers if app accepts any content types
    if (acceptedShareTypes.isNotEmpty) {
      ShareService.instance.registerReceiver(id, acceptedShareTypes);
    }
  }

  /// Get a specific app definition by ID
  AppDefinition? getAppDefinition(String id) => _appDefinitions[id];

  /// Get a specific app instance by ID (for backward compatibility)
  SubApp? getApp(String id) => _appDefinitions[id]?.factory();

  /// Navigate to a specific sub-app (legacy method - uses Navigator)
  void openApp(BuildContext context, SubApp app) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _SubAppWrapper(app: app),
      ),
    );
  }

  /// Launch app using runtime manager (preferred method)
  Future<void> launchApp(String appId) async {
    final definition = _appDefinitions[appId];
    if (definition == null) {
      throw StateError('App $appId is not registered');
    }

    await AppRuntimeManager.instance.launchApp(appId, definition.factory);
  }

  /// Return to the launcher (keep app running in background)
  void returnToLauncher(BuildContext context) {
    AppRuntimeManager.instance.returnToLauncher();
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
