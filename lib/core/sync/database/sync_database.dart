import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'sync_database.g.dart';

/// Tracks sync state with other devices
class SyncState extends Table {
  /// ID of the device we're tracking sync state for
  TextColumn get deviceId => text()();

  /// ID of the app being synced
  TextColumn get appId => text()();

  /// ID of the last entity that was synced
  TextColumn get lastEntityId => text()();

  /// Timestamp of last successful sync
  DateTimeColumn get lastSyncAt => dateTime()();

  /// Last sync version number processed
  IntColumn get lastSyncVersion => integer()();

  @override
  Set<Column> get primaryKey => {deviceId, appId};
}

/// Tracks pending changes that need to be synced
class PendingSync extends Table {
  /// Auto-incrementing ID
  IntColumn get id => integer().autoIncrement()();

  /// ID of the app that owns this entity
  TextColumn get appId => text()();

  /// ID of the entity that changed
  TextColumn get entityId => text()();

  /// Type of operation: 'create', 'update', 'delete'
  TextColumn get operation => text()();

  /// When the change occurred
  DateTimeColumn get timestamp => dateTime()();

  /// Device that made the change
  TextColumn get deviceId => text()();

  /// Sync version at time of change
  IntColumn get syncVersion => integer()();
}

/// Metadata for synced files
class SyncableFiles extends Table {
  /// Unique ID for the file
  TextColumn get id => text()();

  /// Relative path from app data directory
  TextColumn get relativePath => text()();

  /// SHA-256 hash of file content
  TextColumn get contentHash => text()();

  /// Size in bytes
  IntColumn get sizeBytes => integer()();

  /// When the file was created
  DateTimeColumn get createdAt => dateTime()();

  /// When the file was last modified
  DateTimeColumn get updatedAt => dateTime()();

  /// When the file was deleted (null if not deleted)
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Device that made the last change
  TextColumn get deviceId => text()();

  /// Sync version for optimistic locking
  IntColumn get syncVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Known devices in the network
class KnownDevices extends Table {
  /// Unique device ID
  TextColumn get id => text()();

  /// Human-readable device name
  TextColumn get name => text()();

  /// Device type (android, ios, windows, linux, web)
  TextColumn get type => text()();

  /// Last known IP address
  TextColumn get ipAddress => text().nullable()();

  /// Last known port
  IntColumn get port => integer().nullable()();

  /// Last time device was seen
  DateTimeColumn get lastSeen => dateTime()();

  /// Whether device is currently online
  BoolColumn get isOnline => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [SyncState, PendingSync, SyncableFiles, KnownDevices],
)
class SyncDatabase extends _$SyncDatabase {
  SyncDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // Queries for SyncState
  Future<List<SyncStateData>> getAllSyncStates() => select(syncState).get();

  Future<SyncStateData?> getSyncState(String deviceId, String appId) {
    return (select(syncState)
          ..where((t) => t.deviceId.equals(deviceId) & t.appId.equals(appId)))
        .getSingleOrNull();
  }

  Future<void> upsertSyncState(SyncStateCompanion state) {
    return into(syncState).insertOnConflictUpdate(state);
  }

  // Queries for PendingSync
  Future<List<PendingSyncData>> getPendingChanges([String? appId]) {
    final query = select(pendingSync)..orderBy([(t) => OrderingTerm.asc(t.timestamp)]);
    if (appId != null) {
      query.where((t) => t.appId.equals(appId));
    }
    return query.get();
  }

  Future<int> addPendingChange(PendingSyncCompanion change) {
    return into(pendingSync).insert(change);
  }

  Future<void> removePendingChange(int id) {
    return (delete(pendingSync)..where((t) => t.id.equals(id))).go();
  }

  Future<void> clearPendingChanges(String appId) {
    return (delete(pendingSync)..where((t) => t.appId.equals(appId))).go();
  }

  // Queries for SyncableFiles
  Future<List<SyncableFile>> getAllFiles() => select(syncableFiles).get();

  Future<SyncableFile?> getFile(String id) {
    return (select(syncableFiles)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<SyncableFile?> getFileByPath(String relativePath) {
    return (select(syncableFiles)..where((t) => t.relativePath.equals(relativePath)))
        .getSingleOrNull();
  }

  Future<void> upsertFile(SyncableFilesCompanion file) {
    return into(syncableFiles).insertOnConflictUpdate(file);
  }

  Future<void> deleteFile(String id) {
    return (delete(syncableFiles)..where((t) => t.id.equals(id))).go();
  }

  // Queries for KnownDevices
  Future<List<KnownDevice>> getAllDevices() => select(knownDevices).get();

  Future<List<KnownDevice>> getOnlineDevices() {
    return (select(knownDevices)..where((t) => t.isOnline.equals(true))).get();
  }

  Future<KnownDevice?> getDevice(String id) {
    return (select(knownDevices)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsertDevice(KnownDevicesCompanion device) {
    return into(knownDevices).insertOnConflictUpdate(device);
  }

  Future<void> updateDeviceOnlineStatus(String id, bool isOnline) {
    return (update(knownDevices)..where((t) => t.id.equals(id)))
        .write(KnownDevicesCompanion(isOnline: Value(isOnline)));
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'data', 'sync_state.db'));

    // Ensure directory exists
    await file.parent.create(recursive: true);

    return NativeDatabase(file);
  });
}
