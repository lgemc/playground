# Device Sync Implementation Plan

## Current Storage Analysis

The app currently uses two storage mechanisms:

### 1. SQLite (via sqflite)
- **Used for**: AppBus event persistence (`lib/core/app_bus.dart`)
- **Database**: `data/app_bus.db` with events table
- **Characteristics**: Single centralized database for inter-app messaging

### 2. JSON Files
- **Used for**: App-specific data storage
- **Pattern**: Each app stores data in `data/{app_id}/` directory
- **Examples**:
  - Vocabulary: `data/vocabulary/words.json`
  - Notes: `data/notes/metadata.json` + individual `.md` files per note
  - LMS: `data/lms/courses.json` (nested JSON structure)
  - Chat, Summaries, File System: Similar JSON-based patterns

### 3. Storage Patterns Identified
- **Metadata + Content Split**: Notes app stores metadata in JSON, content in separate `.md` files
- **Single File**: Vocabulary and LMS use single JSON files with all data
- **Common Fields**: All models have `id`, `createdAt`, `updatedAt` timestamps
- **Events**: AppBus emits create/update/delete events that are already tracked

## Sync Requirements

Based on your requirements:
1. **P2P sync without server interference** (or minimal server)
2. **Support for SQLite and files**
3. **Handle edit vs delete conflicts automatically**
4. **Seamless sync across devices**
5. **Target platforms**: Android, iOS, Windows, Linux, Web

## Recommended Approach: Hybrid Solution

Given the P2P requirement and existing architecture, here's the recommended stack:

### Core Technology: **Drift + Custom Sync Layer**

**Why Drift (not PowerSync):**
- PowerSync requires a centralized Postgres backend (conflicts with P2P requirement)
- Drift provides SQLite with full Web/Desktop/Mobile support
- Enables complete control over sync logic for P2P architecture

### Architecture Components

#### 1. **Local Database Migration** (Phase 1)
- Migrate all JSON storage to Drift-managed SQLite
- Keep one SQLite database per app: `data/{app_id}/data.db`
- Implement soft-delete pattern for all tables

**Soft Delete Schema Pattern:**
```dart
abstract class SyncableTable extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get syncVersion => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text()(); // Device that made the last change

  @override
  Set<Column> get primaryKey => {id};
}
```

**Benefits:**
- Never use `DELETE FROM` - always `UPDATE SET deleted_at = NOW()`
- Sync can detect "edit after delete" and "delete after edit" scenarios
- `syncVersion` enables optimistic locking
- `deviceId` helps resolve conflicts (last-writer-wins or custom logic)

#### 2. **File Sync Layer** (Phase 1)
For files (e.g., note markdown content, PDFs, images):
- Store file metadata in SQLite (path, hash, size, updatedAt, deletedAt)
- Store actual files in `data/{app_id}/files/`
- Track file changes via content hash (SHA-256)

**File Metadata Table:**
```dart
class SyncableFiles extends Table {
  TextColumn get id => text()();
  TextColumn get relativePath => text()();
  TextColumn get contentHash => text()();
  IntColumn get sizeBytes => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get deviceId => text()();
}
```

#### 3. **P2P Sync Protocol** (Phase 2)

**Option A: Local Network Discovery + WebRTC**
- Use mDNS/Bonjour for device discovery on same network
- WebRTC data channels for P2P transfer
- No internet required when on same WiFi

**Packages:**
- `multicast_dns` for device discovery
- `flutter_webrtc` for P2P data transfer
- `network_info_plus` for network detection

**Option B: Syncthing Protocol Integration**
- Use Syncthing's battle-tested sync protocol
- Can work P2P or via relay servers (optional)
- Block-level syncing for efficiency

**Package:**
- Custom Dart wrapper for Syncthing library (requires native integration)

**Option C: CRDT-based Sync (Most Robust)**
- Use **automerge** or **yjs** CRDT library
- Automatic conflict resolution
- True P2P with eventual consistency
- Can sync via any transport (WebSocket, WebRTC, HTTP)

**Packages:**
- `yrs` (Yjs Dart port) - not yet stable
- Custom CRDT implementation for simple cases
- OR use operational transforms (simpler than CRDT)

#### 4. **Conflict Resolution Strategy** (Phase 2)

**For "Edit vs Delete" conflicts:**

```dart
enum ConflictResolution {
  lastWriteWins,      // Use timestamp + deviceId tiebreaker
  deleteWins,         // Deletion always takes precedence
  editWins,           // Edit revives deleted item
  manualReview,       // Flag for user review
}

class SyncConflict {
  final String entityId;
  final String entityType;
  final SyncableRecord localVersion;
  final SyncableRecord remoteVersion;
  final ConflictType type; // editVsDelete, editVsEdit, etc.

  SyncableRecord resolve(ConflictResolution strategy) {
    switch (type) {
      case ConflictType.editVsDelete:
        if (strategy == ConflictResolution.lastWriteWins) {
          return localVersion.updatedAt.isAfter(remoteVersion.updatedAt)
              ? localVersion
              : remoteVersion;
        }
        // ... other strategies
    }
  }
}
```

**Default Strategy (Recommended):**
1. If one device deleted and another edited:
   - Compare timestamps
   - Later timestamp wins
   - If deleted later → item stays deleted
   - If edited later → item revives with new data
2. If both edited:
   - Use vector clocks or Lamport timestamps
   - Last-write-wins with deviceId as tiebreaker

#### 5. **Sync State Tracking** (Phase 2)

Central sync database: `data/sync_state.db`

```dart
// Track what's been synced with which devices
class SyncState extends Table {
  TextColumn get deviceId => text()();
  TextColumn get appId => text()();
  TextColumn get lastEntityId => text()(); // Last synced entity
  DateTimeColumn get lastSyncAt => dateTime()();
  IntColumn get lastSyncVersion => integer()();

  @override
  Set<Column> get primaryKey => {deviceId, appId};
}

// Track pending changes to sync
class PendingSync extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get appId => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()(); // 'create', 'update', 'delete'
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get deviceId => text()();
}
```

#### 6. **Sync Service** (Phase 2)

```dart
class DeviceSyncService {
  // Discovery
  Future<List<Device>> discoverDevices();

  // Connection
  Future<SyncSession> connectToDevice(Device device);

  // Sync operations
  Future<SyncResult> syncApp(String appId, Device device);
  Future<SyncResult> syncAllApps(Device device);

  // Conflict handling
  Stream<SyncConflict> get conflicts;
  Future<void> resolveConflict(SyncConflict conflict, ConflictResolution resolution);

  // State
  Future<Map<String, DateTime>> getLastSyncTimes();
  Future<List<PendingChange>> getPendingChanges();
}
```

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)
1. **Add Drift dependency**
   - `drift: ^2.14.0`
   - `drift_dev: ^2.14.0` (dev)
   - `build_runner: ^2.4.0` (dev)
   - `sqlite3_flutter_libs: ^0.5.0`
   - `drift_sqflite: ^2.0.0` (mobile)

2. **Define base syncable mixin**
   ```dart
   mixin SyncableEntity {
     String get id;
     DateTime get createdAt;
     DateTime get updatedAt;
     DateTime? get deletedAt;
     int get syncVersion;
     String get deviceId;

     bool get isDeleted => deletedAt != null;
   }
   ```

3. **Migrate one app as proof of concept (Vocabulary)**
   - Convert `VocabularyStorage` to use Drift
   - Implement soft-delete pattern
   - Test CRUD operations
   - Ensure AppBus events still work

4. **Create file sync metadata tables**
   - Define schema for file tracking
   - Implement content hashing
   - Build file metadata sync

### Phase 2: Sync Protocol (Week 3-4)
1. **Choose sync transport** (Recommend: Local Network + WebRTC)
   - Implement device discovery
   - Establish P2P connections
   - Handle connection lifecycle

2. **Implement change detection**
   - Track pending changes in PendingSync table
   - Build diff algorithm between devices
   - Optimize for incremental sync

3. **Build conflict resolver**
   - Implement conflict detection logic
   - Create resolution strategies
   - Test edit-vs-delete scenarios

4. **Sync service implementation**
   - Build DeviceSyncService
   - Implement sync protocols
   - Add background sync support

### Phase 3: Rollout (Week 5-6)
1. **Migrate remaining apps to Drift**
   - Notes, Chat, LMS, Summaries, File System
   - Ensure data migration preserves existing data

2. **Testing**
   - Multi-device sync scenarios
   - Conflict resolution edge cases
   - Network failure recovery
   - Performance testing with large datasets

3. **UI for sync management**
   - Device pairing screen
   - Sync status indicator
   - Manual sync trigger
   - Conflict review interface (if needed)

### Phase 4: Optimization (Week 7+)
1. **Delta sync** - Only transfer changed fields
2. **Compression** - Gzip sync payloads
3. **Batch operations** - Group small changes
4. **Smart scheduling** - Sync when on WiFi, charging, etc.

## Alternative: If Server is Acceptable

If you're willing to use a lightweight server relay (even self-hosted):

### **Simpler Option: Supabase Realtime + Postgres**
- PostgreSQL backend with soft-deletes
- Supabase Realtime for live sync
- Built-in conflict resolution
- Works on all platforms
- Can self-host

### **Middle Ground: CouchDB/PouchDB**
- CouchDB server (can be local/self-hosted)
- PouchDB on Flutter (via `couchdb_dart`)
- Built-in replication and conflict resolution
- Works offline-first
- Mature ecosystem

## Recommended Decision Path

1. **Start with Drift migration** (Phase 1) - This is required regardless of sync choice
2. **Prototype P2P sync with mDNS + WebRTC** (Phase 2)
3. **Evaluate complexity**:
   - If too complex → fallback to self-hosted CouchDB
   - If manageable → continue with P2P implementation
4. **Consider CRDT** if conflicts become hard to manage

## Key Tradeoffs

| Approach | Pros | Cons |
|----------|------|------|
| **Full P2P (WebRTC)** | No server, true P2P, privacy | Complex NAT traversal, discovery challenges, both devices must be online |
| **P2P + Relay** | Hybrid approach, works offline | Requires some server infrastructure |
| **CouchDB** | Battle-tested, built-in sync | Requires server (can be local) |
| **PowerSync** | Managed, robust | Not P2P, requires Postgres backend |

## Files to Create

```
lib/core/sync/
├── sync_service.dart          # Main sync orchestrator
├── device_discovery.dart      # mDNS/network discovery
├── sync_protocol.dart         # P2P protocol implementation
├── conflict_resolver.dart     # Conflict resolution logic
├── models/
│   ├── sync_state.dart
│   ├── pending_sync.dart
│   └── sync_conflict.dart
└── database/
    ├── sync_database.dart     # Drift database for sync state
    └── syncable_mixin.dart    # Mixin for all syncable tables

lib/shared/database/
└── base_storage.dart          # Base class for Drift-based storage

lib/apps/{app_id}/database/
└── {app_id}_database.dart     # Drift database per app
```

## Next Steps

1. Review this plan and decide on sync approach (Pure P2P vs. Optional Relay vs. CouchDB)
2. Start Phase 1 with Drift migration for one app
3. Build proof-of-concept sync between two devices
4. Iterate based on real-world testing
