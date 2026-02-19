# Internal Navigation and Multi-App System

## Overview

Transform Playground into an OS-like environment where multiple sub-apps can run simultaneously with a task switcher interface.

## Current State

- Apps launch exclusively (one at a time)
- Navigation replaces the entire screen
- No concept of "running" vs "not running" apps
- AppRegistry manages registration but not runtime state

## Goals

1. Enable multiple apps to run concurrently
2. Provide iOS-style floating menu for task switching
3. Show all running apps in a switcher interface
4. Allow users to switch between or close running apps

## Architecture Changes

### 1. Runtime State Management

**New Class: `AppRuntimeManager`** (`lib/core/app_runtime_manager.dart`)

```dart
class AppRuntimeManager {
  // Track running apps with their state
  final Map<String, AppRuntimeState> _runningApps = {};

  // Current foreground app
  String? _currentAppId;

  // Launch app (create instance, call onInit)
  Future<void> launchApp(String appId);

  // Bring app to foreground (without reinitializing)
  void switchToApp(String appId);

  // Close app (call onDispose, remove from running apps)
  Future<void> closeApp(String appId);

  // Get list of running apps
  List<AppRuntimeState> getRunningApps();
}

class AppRuntimeState {
  final String appId;
  final SubApp instance;
  final DateTime launchedAt;
  final Widget? lastState; // Preserve widget state if possible
}
```

### 2. Widget State Preservation

Use `AutomaticKeepAliveClientMixin` or custom state management to preserve app state when switching:

```dart
class AppContainer extends StatefulWidget {
  final SubApp app;
  final bool isActive;
}
```

### 3. AppRegistry Integration

Update `AppRegistry` to work with `AppRuntimeManager`:
- `AppRegistry`: Holds app definitions (templates)
- `AppRuntimeManager`: Manages running instances

## UI Components

### 1. Floating Action Button (FAB)

**Location**: `lib/widgets/app_switcher_fab.dart`

- Position: Bottom-right corner (draggable)
- Icon: Grid or layers icon
- Always visible on top of all apps
- Tap to open switcher menu

### 2. App Switcher Overlay

**Location**: `lib/widgets/app_switcher_overlay.dart`

**Design**:
```
┌─────────────────────────┐
│  Running Apps           │
├─────────────────────────┤
│  ┌───┐ ┌───┐ ┌───┐    │
│  │ 1 │ │ 2 │ │ 3 │    │ <- App cards with preview
│  └───┘ └───┘ └───┘    │
│  Chat  Note  Todo      │
│   [×]   [×]   [×]      │ <- Close buttons
└─────────────────────────┘
```

Features:
- Horizontal scrollable list of running apps
- Each card shows app icon, name, small preview
- Tap card to switch to that app
- Tap [×] to close app
- Show background blur/dimming

### 3. Main Container Widget

**Location**: `lib/widgets/playground_container.dart`

```dart
class PlaygroundContainer extends StatefulWidget {
  // Manages the stack of running apps
  // Only renders the current foreground app
  // Preserves background app states
}
```

## Implementation Steps

### Phase 1: Core Runtime Management

1. Create `AppRuntimeManager` class
   - Implement app lifecycle (launch, switch, close)
   - Track running apps map
   - Emit events on state changes

2. Update `AppRegistry`
   - Separate registration from instantiation
   - Apps become factories, not singletons
   - Each launch creates new instance

3. Modify SubApp lifecycle
   - Add `onPause()` callback (when app goes to background)
   - Add `onResume()` callback (when app comes to foreground)
   - Ensure `onDispose()` is called on close

### Phase 2: UI Container

1. Create `PlaygroundContainer`
   - Widget stack for multiple apps
   - Only foreground app visible
   - Use `IndexedStack` or `Offstage` for state preservation

2. Implement state preservation
   - Keep background apps in memory
   - Maintain scroll positions, form data, etc.

### Phase 3: Floating Button

1. Create `AppSwitcherFAB`
   - Draggable floating button
   - Save position to preferences
   - Always on top using `Stack` or `Overlay`

2. Add tap interaction
   - Open switcher overlay on tap
   - Smooth animation

### Phase 4: App Switcher

1. Create `AppSwitcherOverlay`
   - Modal overlay with running apps
   - Card-based UI with app previews
   - Close button per app

2. Implement switcher logic
   - Switch: Close overlay, call `AppRuntimeManager.switchToApp()`
   - Close: Show confirmation dialog, call `AppRuntimeManager.closeApp()`

3. Add app preview snapshots (optional)
   - Use `RepaintBoundary` to capture screenshots
   - Show in switcher cards

### Phase 5: Integration

1. Update `main.dart`
   - Wrap app with `PlaygroundContainer`
   - Initialize `AppRuntimeManager`
   - Add `AppSwitcherFAB` to overlay

2. Update Launcher app
   - Tapping app icon launches new instance (if not running)
   - Or switches to existing instance (if already running)
   - Show indicator for running apps

3. Update navigation flows
   - Replace `Navigator.push()` with `AppRuntimeManager.switchToApp()`
   - Handle back button (return to previous app, not close)

## Configuration

Add settings to ConfigService:

```dart
{
  "playground.multitasking.enabled": true,
  "playground.multitasking.maxRunningApps": 10,
  "playground.multitasking.fabPosition": {"x": 0.9, "y": 0.9},
  "playground.multitasking.showPreviews": true,
}
```

## Edge Cases

1. **Memory pressure**: Implement LRU eviction when max apps reached
2. **App crashes**: Isolate crashes to single app, don't kill container
3. **Deep links**: Handle launching specific app from notification
4. **Persistence**: Optionally restore running apps on app restart
5. **Launcher**: Should Launcher itself be closeable? (Probably not - it's special)

## Future Enhancements

- Picture-in-picture mode for video/map apps
- Split-screen multitasking
- App windowing system
- Gestures for app switching (swipe between apps)
- Recent apps history (closed apps)

## Testing

1. Unit tests for `AppRuntimeManager`
2. Widget tests for switcher UI
3. Integration test: Launch 3 apps, switch between them, close one
4. Memory leak tests (ensure disposed apps release resources)
5. State preservation tests (data persists when backgrounded)

## Migration Path

1. Implement runtime manager (backward compatible)
2. Add switcher UI (can be disabled via config)
3. Gradually migrate apps to support pause/resume
4. Enable by default once stable

## Files to Create

- `lib/core/app_runtime_manager.dart`
- `lib/widgets/playground_container.dart`
- `lib/widgets/app_switcher_fab.dart`
- `lib/widgets/app_switcher_overlay.dart`
- `lib/widgets/app_card.dart`
- `test/core/app_runtime_manager_test.dart`

## Files to Modify

- `lib/core/app_registry.dart` - Separate registration from instantiation
- `lib/core/sub_app.dart` - Add `onPause()` and `onResume()` callbacks
- `lib/main.dart` - Integrate new container and FAB
- `lib/apps/launcher/launcher_app.dart` - Update launch logic
