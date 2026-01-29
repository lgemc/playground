/// Base mixin for all syncable entities
/// Provides common fields required for device synchronization
mixin SyncableEntity {
  /// Unique identifier for the entity
  String get id;

  /// Timestamp when the entity was created
  DateTime get createdAt;

  /// Timestamp when the entity was last updated
  DateTime get updatedAt;

  /// Timestamp when the entity was deleted (null if not deleted)
  /// Using soft-delete pattern to enable sync conflict resolution
  DateTime? get deletedAt;

  /// Sync version number for optimistic locking
  /// Incremented on each update to detect concurrent modifications
  int get syncVersion;

  /// Device ID that made the last change
  /// Used for conflict resolution (last-writer-wins with device tiebreaker)
  String get deviceId;

  /// Whether this entity has been deleted
  bool get isDeleted => deletedAt != null;

  /// Check if this entity is newer than another based on updatedAt
  bool isNewerThan(SyncableEntity other) {
    return updatedAt.isAfter(other.updatedAt);
  }

  /// Check if this entity was modified after deletion
  bool wasModifiedAfterDeletion() {
    if (deletedAt == null) return false;
    return updatedAt.isAfter(deletedAt!);
  }
}
