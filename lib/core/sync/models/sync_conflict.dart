import 'syncable_entity.dart';

/// Types of sync conflicts that can occur
enum ConflictType {
  /// One device edited while another deleted the same entity
  editVsDelete,

  /// Both devices edited the same entity
  editVsEdit,

  /// Both devices deleted the same entity (usually not a conflict)
  deleteVsDelete,
}

/// Strategies for resolving sync conflicts
enum ConflictResolution {
  /// Use timestamp comparison, latest update wins
  lastWriteWins,

  /// Deletion always takes precedence over edits
  deleteWins,

  /// Edit revives deleted items
  editWins,

  /// Flag for manual user review
  manualReview,
}

/// Represents a conflict between local and remote versions of an entity
class SyncConflict<T extends SyncableEntity> {
  /// Unique identifier for the conflicted entity
  final String entityId;

  /// Type of entity (e.g., 'vocabulary_word', 'note', etc.)
  final String entityType;

  /// Local version of the entity
  final T localVersion;

  /// Remote version of the entity
  final T remoteVersion;

  /// Type of conflict
  final ConflictType type;

  /// Timestamp when conflict was detected
  final DateTime detectedAt;

  SyncConflict({
    required this.entityId,
    required this.entityType,
    required this.localVersion,
    required this.remoteVersion,
    required this.type,
    DateTime? detectedAt,
  }) : detectedAt = detectedAt ?? DateTime.now();

  /// Resolve the conflict using the specified strategy
  /// Returns the winning version
  T resolve(ConflictResolution strategy) {
    switch (type) {
      case ConflictType.editVsDelete:
        return _resolveEditVsDelete(strategy);

      case ConflictType.editVsEdit:
        return _resolveEditVsEdit(strategy);

      case ConflictType.deleteVsDelete:
        // Both deleted - use whichever was deleted last
        return localVersion.deletedAt!.isAfter(remoteVersion.deletedAt!)
            ? localVersion
            : remoteVersion;
    }
  }

  T _resolveEditVsDelete(ConflictResolution strategy) {
    switch (strategy) {
      case ConflictResolution.lastWriteWins:
        // Compare timestamps - later timestamp wins
        if (localVersion.updatedAt.isAfter(remoteVersion.updatedAt)) {
          return localVersion;
        } else if (remoteVersion.updatedAt.isAfter(localVersion.updatedAt)) {
          return remoteVersion;
        } else {
          // Same timestamp - use deviceId as tiebreaker
          return localVersion.deviceId.compareTo(remoteVersion.deviceId) > 0
              ? localVersion
              : remoteVersion;
        }

      case ConflictResolution.deleteWins:
        // Deletion takes precedence
        return localVersion.isDeleted ? localVersion : remoteVersion;

      case ConflictResolution.editWins:
        // Edit revives the deleted item
        return localVersion.isDeleted ? remoteVersion : localVersion;

      case ConflictResolution.manualReview:
        // Don't auto-resolve, throw for manual handling
        throw ConflictRequiresManualReviewException(this);
    }
  }

  T _resolveEditVsEdit(ConflictResolution strategy) {
    switch (strategy) {
      case ConflictResolution.lastWriteWins:
      case ConflictResolution.deleteWins:
      case ConflictResolution.editWins:
        // All use last-write-wins for edit-vs-edit
        if (localVersion.updatedAt.isAfter(remoteVersion.updatedAt)) {
          return localVersion;
        } else if (remoteVersion.updatedAt.isAfter(localVersion.updatedAt)) {
          return remoteVersion;
        } else {
          // Same timestamp - use syncVersion or deviceId as tiebreaker
          if (localVersion.syncVersion != remoteVersion.syncVersion) {
            return localVersion.syncVersion > remoteVersion.syncVersion
                ? localVersion
                : remoteVersion;
          }
          return localVersion.deviceId.compareTo(remoteVersion.deviceId) > 0
              ? localVersion
              : remoteVersion;
        }

      case ConflictResolution.manualReview:
        throw ConflictRequiresManualReviewException(this);
    }
  }

  /// Detect conflict type based on the two versions
  static ConflictType detectConflictType(
    SyncableEntity local,
    SyncableEntity remote,
  ) {
    if (local.isDeleted && remote.isDeleted) {
      return ConflictType.deleteVsDelete;
    } else if (local.isDeleted || remote.isDeleted) {
      return ConflictType.editVsDelete;
    } else {
      return ConflictType.editVsEdit;
    }
  }
}

/// Exception thrown when a conflict requires manual review
class ConflictRequiresManualReviewException implements Exception {
  final SyncConflict conflict;

  ConflictRequiresManualReviewException(this.conflict);

  @override
  String toString() =>
      'Conflict requires manual review: ${conflict.entityType}#${conflict.entityId}';
}
