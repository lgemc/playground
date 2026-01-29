import 'package:drift/drift.dart';

/// Base mixin for all syncable tables
/// Provides common columns required for device synchronization
mixin SyncableTable on Table {
  /// Unique identifier
  TextColumn get id => text()();

  /// Timestamp when the entity was created
  DateTimeColumn get createdAt => dateTime()();

  /// Timestamp when the entity was last updated
  DateTimeColumn get updatedAt => dateTime()();

  /// Timestamp when the entity was deleted (null if not deleted)
  /// Using soft-delete pattern to enable sync conflict resolution
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Sync version number for optimistic locking
  /// Incremented on each update to detect concurrent modifications
  IntColumn get syncVersion => integer().withDefault(const Constant(1))();

  /// Device ID that made the last change
  /// Used for conflict resolution (last-writer-wins with device tiebreaker)
  TextColumn get deviceId => text()();

  @override
  Set<Column> get primaryKey => {id};
}
