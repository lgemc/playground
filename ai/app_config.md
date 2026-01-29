# App Config Implementation Plan

## Overview
Implement a configuration system similar to environment variables in an operating system, where apps can define default values and users can override them.

## Architecture

### 1. Config Scope
- **Global Config**: Shared across all apps (e.g., theme preferences, language)
- **App-Scoped Config**: Specific to each app, isolated by app ID

### 2. Config Layers (Priority Order)
1. **User Overrides**: User-modified values (highest priority)
2. **Default Values**: App-defined defaults (fallback)

### 3. Core Components

#### ConfigService (`lib/core/config_service.dart`)
- Singleton service managing all configuration
- Methods:
  - `String? get(String key, {String? appId, String? defaultValue})` - Get config with optional default
  - `void set(String key, String value, {String? appId})` - Set user override
  - `void setDefault(String key, String value, {String? appId})` - Define default value
  - `Map<String, String> getAll({String? appId})` - Get all resolved configs
  - `void reset(String key, {String? appId})` - Remove user override, revert to default
  - `void delete(String key, {String? appId})` - Remove config entirely (user + default)
  - `bool isDefault(String key, {String? appId})` - Check if using default value

#### Storage Strategy
- User overrides: `data/global/config.json` and `data/{app_id}/config.json`
- Defaults: In-memory only (defined by apps at runtime)
- Resolution: Check user override first, then default, then null

### 4. Integration Points

#### SubApp Extension
Add config methods to `SubApp`:
```dart
class SubApp {
  // Get config (checks user override, then default)
  String? getConfig(String key, {String? defaultValue});

  // Set user override
  void setConfig(String key, String value);

  // Define defaults (call in onInit)
  void defineConfig(String key, String defaultValue);

  // Reset to default
  void resetConfig(String key);
}
```

#### AppRegistry Enhancement
- Initialize ConfigService on startup
- Apps define defaults in `onInit()` lifecycle hook

### 5. Config UI
- Settings sub-app to view/edit global configs
- Per-app settings UI showing:
  - Config key
  - Current value (with indicator if it's default or user-modified)
  - Reset button to revert to default
  - Edit functionality

## Implementation Steps

1. Create `ConfigService` with dual-layer storage (defaults + overrides)
2. Add helper methods to `SubApp` base class
3. Initialize `ConfigService` in `main.dart`
4. Update existing apps to define default configs
5. Write unit tests for ConfigService
6. Create settings UI for config management

## Usage Example

```dart
class NotesApp extends SubApp {
  @override
  void onInit() {
    // Define defaults
    defineConfig('theme', 'light');
    defineConfig('fontSize', '14');
    defineConfig('autoSave', 'true');

    // Use config (gets user override or default)
    final theme = getConfig('theme');  // Returns 'light' or user value
  }

  void updateTheme(String newTheme) {
    // User override
    setConfig('theme', newTheme);
  }

  void restoreDefaults() {
    resetConfig('theme');  // Back to 'light'
  }
}
```

## Type Support
- Start with string-only values
- Apps serialize/deserialize as needed
- Helper parsing: `getBool(key)`, `getInt(key)` can be added later
