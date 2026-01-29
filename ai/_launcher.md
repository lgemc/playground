# Launcher

Is where the sub apps will be shown and published. Use a simple UI like Android or iOS, with squares and icons, and the app name.

---

## Plan: Application Module System & Launcher Sub-App

### 1. Project Architecture

The playground project needs a modular architecture where each sub-app is self-contained but follows a common interface.

```
playground/
├── lib/
│   ├── main.dart                    # Entry point, loads launcher
│   ├── core/
│   │   ├── app_registry.dart        # Registry of all sub-apps
│   │   ├── sub_app.dart             # Abstract class/interface for sub-apps
│   │   └── file_storage.dart        # File-based storage utilities
│   └── apps/
│       ├── launcher/                # Launcher is a sub-app itself
│       │   ├── launcher_app.dart
│       │   ├── launcher_screen.dart
│       │   └── widgets/
│       │       └── app_icon.dart
│       └── [other_apps]/            # Future sub-apps go here
├── data/                            # File-based data storage per app
│   ├── launcher/
│   └── [other_apps]/
└── ai/                              # AI planning docs
    └── _launcher.md
```

### 2. Sub-App Interface

Each sub-app must implement a common interface:

```dart
abstract class SubApp {
  String get id;           // Unique identifier
  String get name;         // Display name
  IconData get icon;       // Icon for the launcher
  Color get themeColor;    // Primary color
  Widget build(BuildContext context);  // Main widget

  // Optional: lifecycle hooks
  void onInit() {}
  void onDispose() {}
}
```

### 3. App Registry

A central registry that:
- Discovers and registers all sub-apps
- Provides metadata for the launcher to display
- Handles navigation between apps

### 4. Launcher Sub-App Implementation

The launcher is the default/home sub-app with these features:

#### UI Components
- **Grid layout**: 4 columns on phones, adaptive on larger screens
- **App icons**: Square containers with rounded corners
  - Icon in the center
  - App name below
  - Optional badge for notifications
- **Navigation**: Tap to open app, long-press for options

#### Visual Design
- Clean, minimal design similar to stock Android/iOS
- Support light/dark themes
- Smooth animations for app transitions

### 5. Implementation Steps

#### Phase 1: Core Foundation
- [ ] Create `SubApp` abstract class
- [ ] Create `AppRegistry` singleton
- [ ] Set up file storage utilities
- [ ] Create main.dart entry point

#### Phase 2: Launcher Sub-App
- [ ] Implement `LauncherApp` extending `SubApp`
- [ ] Create `LauncherScreen` with grid layout
- [ ] Build `AppIcon` widget component
- [ ] Add navigation logic to open sub-apps
- [ ] Implement app-to-launcher return flow

#### Phase 3: Data Layer
- [ ] Create per-app data directories
- [ ] Implement file-based preferences
- [ ] SQLite setup for complex data needs

### 6. Navigation Flow

```
main.dart
    │
    ▼
AppRegistry.init()
    │
    ▼
Load Launcher (default app)
    │
    ▼
User taps app icon
    │
    ▼
Navigator pushes SubApp.build()
    │
    ▼
Back button → returns to Launcher
```

### 7. File Storage Convention

Each sub-app gets its own data directory:
- `data/{app_id}/` - App-specific files
- `data/{app_id}/settings.json` - App preferences
- `data/shared/` - Cross-app shared files (future)

### 8. First Milestone

Deliver a working launcher that:
1. Shows itself as a registered app (for testing)
2. Displays a grid of available apps
3. Can navigate to any sub-app
4. Handles back navigation properly
5. Stores minimal state (last opened app, etc.)

---

## Notes

- Launcher should be treated exactly like any other sub-app
- This allows replacing the launcher with a custom one in the future
- The only special thing about launcher is it's the default app on startup
