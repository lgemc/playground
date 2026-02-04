import 'package:flutter/material.dart';
import '../services/config_service.dart';
import '../services/share_content.dart';
import 'search_result.dart';

/// Abstract class that all sub-apps must implement.
/// Each sub-app is a self-contained module with its own UI and logic.
abstract class SubApp {
  /// Unique identifier for the app (used for storage and navigation)
  String get id;

  /// Display name shown in the launcher
  String get name;

  /// Icon displayed in the launcher grid
  IconData get icon;

  /// Primary theme color for the app
  Color get themeColor;

  /// Builds the main widget for this sub-app
  Widget build(BuildContext context);

  /// Called when the app is first initialized
  void onInit() {}

  /// Called when the app is paused (goes to background)
  void onPause() {}

  /// Called when the app is resumed (comes to foreground)
  void onResume() {}

  /// Called when the app is disposed
  void onDispose() {}

  // Config management methods

  /// Get a config value (checks user override, then default)
  String? getConfig(String key, {String? defaultValue}) {
    return ConfigService.instance.get(key, appId: id, defaultValue: defaultValue);
  }

  /// Set a user override for a config value
  Future<void> setConfig(String key, String value) async {
    await ConfigService.instance.set(key, value, appId: id);
  }

  /// Define a default config value (call in onInit)
  void defineConfig(String key, String defaultValue) {
    ConfigService.instance.setDefault(key, defaultValue, appId: id);
  }

  /// Reset a config value to its default
  Future<void> resetConfig(String key) async {
    await ConfigService.instance.reset(key, appId: id);
  }

  /// Check if a config key is using its default value
  bool isDefaultConfig(String key) {
    return ConfigService.instance.isDefault(key, appId: id);
  }

  /// Get all config values for this app
  Map<String, String> getAllConfigs() {
    return ConfigService.instance.getAll(appId: id);
  }

  // Share receiver methods

  /// Content types this app can receive (empty = can't receive)
  List<ShareContentType> get acceptedShareTypes => [];

  /// Called when content is shared to this app.
  /// Override this to handle incoming shared content.
  Future<void> onReceiveShare(ShareContent content) async {}

  // Search methods

  /// Whether this app supports search
  bool get supportsSearch => false;

  /// Search for content within this app
  /// Override this to implement app-specific search
  Future<List<SearchResult>> search(String query) async {
    return [];
  }

  /// Navigate to a specific search result within this app
  /// Override this to implement app-specific navigation
  void navigateToSearchResult(
      BuildContext context, SearchResult result) {}
}