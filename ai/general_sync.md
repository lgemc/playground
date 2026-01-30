# General Sync: One Button to Sync Everything

## Current State Analysis

### How Vocabulary Sync Works

The sync architecture is well-designed with clear separation of concerns:

1. **Core Infrastructure** (`lib/core/sync/`):
   - `DeviceDiscoveryService`: UDP broadcast discovery on local network
   - `DeviceSyncService`: Main orchestrator with callback-based architecture
   - `SyncProtocol`: Message framing and batched data transfer over TCP
   - `SyncableEntity` mixin: Provides `updatedAt`, `deletedAt`, `syncVersion`, `deviceId` fields

2. **App Integration Pattern** (Vocabulary as reference):
   - Database table extends `SyncableTable` mixin
   - Storage implements two methods:
     - `getChangesForSync(DateTime? since)` - returns entities modified after timestamp
     - `applyChangesFromSync(List<Map> entities)` - merges incoming data with conflict resolution
   - Callbacks registered manually in `main.dart`

3. **Current Registration in main.dart**:
```dart
syncService.setGetChangesCallback((appId, since) async {
  if (appId == 'vocabulary') {
    return await VocabularyStorageV2.instance.getChangesForSync(since);
  }
  return [];
});

syncService.setApplyChangesCallback((appId, entities) async {
  if (appId == 'vocabulary') {
    await VocabularyStorageV2.instance.applyChangesFromSync(entities);
  }
});
```

### Problem: Manual Per-App Configuration

- Each new syncable app requires editing `main.dart`
- No autodiscovery of sync-capable apps
- Sync UI is per-app (each app has its own sync button)
- No global "sync everything" action

### Apps Ready for Sync (Database Prepared)

| App | Database Ready | Callbacks Integrated |
|-----|----------------|---------------------|
| Vocabulary | Yes | Yes |
| Notes | Yes (SyncableTable) | No |
| Summaries | Yes (SyncableTable) | No |
| File System | Partial (SyncableFiles table exists) | No |
| Courses | Unknown | No |

---

## Proposal: Syncable Interface + Global Sync

### 1. Create SyncableApp Interface

```dart
/// lib/core/sync/syncable_app.dart
abstract class SyncableApp {
  /// Unique identifier for sync (usually same as SubApp.id)
  String get syncId;

  /// Human-readable name for sync UI
  String get syncDisplayName;

  /// Returns entities modified since [since], or all if null
  Future<List<Map<String, dynamic>>> getChangesForSync(DateTime? since);

  /// Applies incoming entities, handling conflicts
  Future<void> applyChangesFromSync(List<Map<String, dynamic>> entities);

  /// Optional: Called before sync starts (e.g., to flush caches)
  Future<void> onSyncStart() async {}

  /// Optional: Called after sync completes
  Future<void> onSyncComplete(SyncResult result) async {}
}
```

### 2. Update SubApp to Optionally Implement Sync

```dart
/// lib/core/sub_app.dart
abstract class SubApp {
  // ... existing fields ...

  /// Returns SyncableApp if this app supports sync, null otherwise
  SyncableApp? get syncable => null;
}
```

### 3. Auto-Registration in AppRegistry

```dart
/// lib/core/app_registry.dart
class AppRegistry {
  final List<SyncableApp> _syncableApps = [];

  void register(SubApp app) {
    _apps.add(app);
    if (app.syncable != null) {
      _syncableApps.add(app.syncable!);
    }
  }

  List<SyncableApp> get syncableApps => List.unmodifiable(_syncableApps);
}
```

### 4. Simplified DeviceSyncService Integration

```dart
// In main.dart or sync service initialization
void initializeSync() {
  final syncApps = AppRegistry.instance.syncableApps;

  syncService.setGetChangesCallback((appId, since) async {
    final app = syncApps.firstWhereOrNull((a) => a.syncId == appId);
    return app?.getChangesForSync(since) ?? [];
  });

  syncService.setApplyChangesCallback((appId, entities) async {
    final app = syncApps.firstWhereOrNull((a) => a.syncId == appId);
    await app?.applyChangesFromSync(entities);
  });
}
```

### 5. Global Sync Button in Launcher

Add a sync FAB or action button in the Launcher that:

1. Shows discovered devices
2. On device selection, syncs ALL registered apps sequentially:

```dart
Future<void> syncAllApps(Device device) async {
  final apps = AppRegistry.instance.syncableApps;

  for (final app in apps) {
    await app.onSyncStart();
    final result = await syncService.syncApp(app.syncId, device);
    await app.onSyncComplete(result);
  }
}
```

---

## Implementation Steps

### Phase 1: Create Interface (No Breaking Changes)

1. Create `SyncableApp` interface in `lib/core/sync/`
2. Add optional `syncable` getter to `SubApp`
3. Update `AppRegistry` to track syncable apps

### Phase 2: Migrate Vocabulary

1. Create `VocabularySyncable` class implementing `SyncableApp`
2. Have `VocabularyApp.syncable` return it
3. Update `main.dart` to use auto-registration
4. Verify vocabulary sync still works

### Phase 3: Enable Other Apps

1. **Notes**: Implement `NotesSyncable` (database already ready)
2. **Summaries**: Implement `SummariesSyncable` (database already ready)
3. **Courses**: Add SyncableTable to database, implement interface
4. **File System**: Special case - needs file content transfer, not just metadata

### Phase 4: Global Sync UI

1. Add sync button to Launcher (or app bar)
2. Create `GlobalSyncDialog` showing:
   - Device selection
   - Per-app sync progress
   - Overall results (X items synced across Y apps)

---

## File System Sync: Special Considerations

File sync is more complex than entity sync:

1. **Metadata vs Content**: Current `SyncableFiles` table only tracks metadata
2. **Large Files**: Can't batch 100 files like vocabulary words
3. **Binary Transfer**: Need streaming, not JSON encoding
4. **Partial Sync**: May want to sync only certain folders

### Proposed Approach for Files

```dart
abstract class FileSyncableApp extends SyncableApp {
  /// Returns file metadata changes (paths, hashes, sizes)
  Future<List<FileMetadata>> getFileChangesForSync(DateTime? since);

  /// Returns actual file content for transfer
  Stream<List<int>> getFileContent(String fileId);

  /// Receives file content
  Future<void> receiveFile(FileMetadata metadata, Stream<List<int>> content);
}
```

This requires protocol extension to support binary streaming alongside JSON messages.

---

## Benefits

1. **Single Sync Point**: One button syncs everything
2. **Self-Registering**: New apps just implement interface, no main.dart changes
3. **Consistent UX**: Same sync flow for all apps
4. **Extensible**: File sync can extend the base interface
5. **Testable**: Each app's sync logic is isolated and testable

---

## Questions to Resolve

1. **Sync Order**: Should apps sync in parallel or sequentially? (Sequential is safer for cross-app references)
2. **Partial Failure**: If vocabulary syncs but notes fails, how to handle?
3. **Progress UI**: Show per-app progress or just overall?
4. **Selective Sync**: Should users be able to exclude certain apps from global sync?
5. **File Content**: Implement file streaming now or defer?

---

## Recommended Next Steps

1. Start with Phase 1-2 (interface + vocabulary migration) - low risk, validates design
2. Add Notes sync (easiest since database is ready)
3. Then Summaries and Courses
4. File System last (most complex, needs protocol changes)
