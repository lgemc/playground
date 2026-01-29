import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Service managing app configuration with two layers:
/// 1. User overrides (persisted to disk)
/// 2. Default values (in-memory)
class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  static ConfigService get instance => _instance;

  ConfigService._internal();

  // In-memory storage for defaults
  final Map<String, String> _globalDefaults = {};
  final Map<String, Map<String, String>> _appDefaults = {};

  // In-memory cache for user overrides
  final Map<String, String> _globalOverrides = {};
  final Map<String, Map<String, String>> _appOverrides = {};

  bool _initialized = false;
  late String _basePath;

  /// Initialize the service by loading user overrides from disk
  Future<void> initialize() async {
    if (_initialized) return;

    final appDir = await getApplicationDocumentsDirectory();
    _basePath = appDir.path;

    await _loadGlobalOverrides();
    _initialized = true;
  }

  /// Ensure service is initialized before disk operations
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  /// Get a config value with priority: user override > default > fallback
  String? get(String key, {String? appId, String? defaultValue}) {
    if (appId != null) {
      // Check app-scoped user override
      if (_appOverrides[appId]?.containsKey(key) ?? false) {
        return _appOverrides[appId]![key];
      }
      // Check app-scoped default
      if (_appDefaults[appId]?.containsKey(key) ?? false) {
        return _appDefaults[appId]![key];
      }
    } else {
      // Check global user override
      if (_globalOverrides.containsKey(key)) {
        return _globalOverrides[key];
      }
      // Check global default
      if (_globalDefaults.containsKey(key)) {
        return _globalDefaults[key];
      }
    }

    return defaultValue;
  }

  /// Set a user override value
  Future<void> set(String key, String value, {String? appId}) async {
    await _ensureInitialized();
    if (appId != null) {
      _appOverrides.putIfAbsent(appId, () => {});
      _appOverrides[appId]![key] = value;
      await _saveAppOverrides(appId);
    } else {
      _globalOverrides[key] = value;
      await _saveGlobalOverrides();
    }
  }

  /// Define a default value (in-memory only)
  void setDefault(String key, String value, {String? appId}) {
    if (appId != null) {
      _appDefaults.putIfAbsent(appId, () => {});
      _appDefaults[appId]![key] = value;
    } else {
      _globalDefaults[key] = value;
    }
  }

  /// Get all resolved configs (user overrides merged with defaults)
  Map<String, String> getAll({String? appId}) {
    final result = <String, String>{};

    if (appId != null) {
      // Add app defaults
      if (_appDefaults.containsKey(appId)) {
        result.addAll(_appDefaults[appId]!);
      }
      // Override with user values
      if (_appOverrides.containsKey(appId)) {
        result.addAll(_appOverrides[appId]!);
      }
    } else {
      // Add global defaults
      result.addAll(_globalDefaults);
      // Override with user values
      result.addAll(_globalOverrides);
    }

    return result;
  }

  /// Remove user override, reverting to default
  Future<void> reset(String key, {String? appId}) async {
    await _ensureInitialized();
    if (appId != null) {
      _appOverrides[appId]?.remove(key);
      await _saveAppOverrides(appId);
    } else {
      _globalOverrides.remove(key);
      await _saveGlobalOverrides();
    }
  }

  /// Remove config entirely (both user override and default)
  Future<void> delete(String key, {String? appId}) async {
    await _ensureInitialized();
    if (appId != null) {
      _appOverrides[appId]?.remove(key);
      _appDefaults[appId]?.remove(key);
      await _saveAppOverrides(appId);
    } else {
      _globalOverrides.remove(key);
      _globalDefaults.remove(key);
      await _saveGlobalOverrides();
    }
  }

  /// Check if a key is using its default value (no user override)
  bool isDefault(String key, {String? appId}) {
    if (appId != null) {
      return !(_appOverrides[appId]?.containsKey(key) ?? false);
    } else {
      return !_globalOverrides.containsKey(key);
    }
  }

  /// Load app-scoped user overrides from disk
  Future<void> loadAppOverrides(String appId) async {
    await _ensureInitialized();
    final file = _getAppConfigFile(appId);
    if (await file.exists()) {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      _appOverrides[appId] = data.cast<String, String>();
    }
  }

  // Private helper methods

  Future<void> _loadGlobalOverrides() async {
    final file = _getGlobalConfigFile();
    if (await file.exists()) {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      _globalOverrides.addAll(data.cast<String, String>());
    }
  }

  Future<void> _saveGlobalOverrides() async {
    final file = _getGlobalConfigFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_globalOverrides));
  }

  Future<void> _saveAppOverrides(String appId) async {
    final file = _getAppConfigFile(appId);
    await file.parent.create(recursive: true);
    final data = _appOverrides[appId] ?? {};
    await file.writeAsString(jsonEncode(data));
  }

  File _getGlobalConfigFile() {
    return File('$_basePath/data/global/config.json');
  }

  File _getAppConfigFile(String appId) {
    return File('$_basePath/data/$appId/config.json');
  }
}
