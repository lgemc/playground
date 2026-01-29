import '../models/sync_conflict.dart';
import '../models/syncable_entity.dart';

/// Service for detecting and resolving sync conflicts
/// Note: Most resolution logic is in the SyncConflict class itself
class ConflictResolver {
  ConflictResolver();

  /// Detect if there's a conflict between local and remote versions
  /// Returns null if no conflict (versions match)
  static bool hasConflict(SyncableEntity local, SyncableEntity remote) {
    // Conflict if both have been modified since last sync
    // (different sync versions indicate divergent histories)
    return local.syncVersion != remote.syncVersion;
  }

  /// Detect the type of conflict
  static ConflictType detectConflictType(
    SyncableEntity local,
    SyncableEntity remote,
  ) {
    return SyncConflict.detectConflictType(local, remote);
  }

  /// Get the default resolution strategy for a conflict type
  static ConflictResolution getDefaultStrategy(ConflictType type) {
    switch (type) {
      case ConflictType.editVsDelete:
        // Default: deletion wins (safer to preserve user intent to delete)
        return ConflictResolution.deleteWins;

      case ConflictType.deleteVsDelete:
        // Both deleted - use last-write-wins to pick the definitive deletion
        return ConflictResolution.lastWriteWins;

      case ConflictType.editVsEdit:
        // Both edited - use last-write-wins
        return ConflictResolution.lastWriteWins;
    }
  }
}
