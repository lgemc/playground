# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

```bash
# Run the app
flutter run

# Analyze code (linting)
flutter analyze   # or: make analyze

# Run tests
flutter test      # or: make test

# Run a single test file
flutter test test/widget_test.dart

# Get dependencies
flutter pub get
```

## Architecture

This is a Flutter-based modular application container. The core concept is a "playground" that hosts multiple self-contained sub-apps, similar to how a mobile OS hosts applications.

### Key Components

**SubApp Interface** (`lib/core/sub_app.dart`): Abstract class all sub-apps must implement. Defines `id`, `name`, `icon`, `themeColor`, `build()`, and lifecycle hooks (`onInit`, `onDispose`).

**AppRegistry** (`lib/core/app_registry.dart`): Singleton that registers sub-apps, provides navigation between apps, and manages app lifecycle.

**Launcher** (`lib/apps/launcher/`): The default "home" sub-app that displays a grid of available apps. It implements SubApp itself, making it replaceable.

### Adding a New Sub-App

1. Create a folder under `lib/apps/{app_name}/`
2. Implement a class extending `SubApp`
3. Register it in `main.dart` via `AppRegistry.instance.register(YourApp())`

### Data Storage Convention

- Each sub-app gets its own data directory: `data/{app_id}/`
- Preferences stored as: `data/{app_id}/settings.json`
- Complex data uses SQLite

### Planning Documents

The `ai/` folder contains planning documents for features (e.g., `ai/_launcher.md`).
