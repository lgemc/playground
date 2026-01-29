import 'sync_conflict.dart';

/// Result of a sync operation
class SyncResult {
  /// Whether the sync completed successfully
  final bool success;

  /// Number of entities synced (sent + received)
  final int entitiesSynced;

  /// Number of entities sent to remote
  final int entitiesSent;

  /// Number of entities received from remote
  final int entitiesReceived;

  /// Number of conflicts detected
  final int conflictsDetected;

  /// Number of conflicts resolved automatically
  final int conflictsResolved;

  /// Conflicts that require manual review
  final List<SyncConflict> pendingConflicts;

  /// Error message if sync failed
  final String? error;

  /// Duration of the sync operation
  final Duration duration;

  /// Timestamp when sync started
  final DateTime startedAt;

  /// Timestamp when sync completed
  final DateTime completedAt;

  SyncResult({
    required this.success,
    required this.entitiesSynced,
    required this.entitiesSent,
    required this.entitiesReceived,
    required this.conflictsDetected,
    required this.conflictsResolved,
    this.pendingConflicts = const [],
    this.error,
    DateTime? startedAt,
    DateTime? completedAt,
  })  : startedAt = startedAt ?? DateTime.now(),
        completedAt = completedAt ?? DateTime.now(),
        duration = (completedAt ?? DateTime.now())
            .difference(startedAt ?? DateTime.now());

  /// Create a successful sync result
  factory SyncResult.success({
    required int entitiesSent,
    required int entitiesReceived,
    int conflictsDetected = 0,
    int conflictsResolved = 0,
    List<SyncConflict> pendingConflicts = const [],
    DateTime? startedAt,
  }) {
    final now = DateTime.now();
    return SyncResult(
      success: true,
      entitiesSynced: entitiesSent + entitiesReceived,
      entitiesSent: entitiesSent,
      entitiesReceived: entitiesReceived,
      conflictsDetected: conflictsDetected,
      conflictsResolved: conflictsResolved,
      pendingConflicts: pendingConflicts,
      startedAt: startedAt,
      completedAt: now,
    );
  }

  /// Create a failed sync result
  factory SyncResult.failure({
    required String error,
    DateTime? startedAt,
  }) {
    final now = DateTime.now();
    return SyncResult(
      success: false,
      entitiesSynced: 0,
      entitiesSent: 0,
      entitiesReceived: 0,
      conflictsDetected: 0,
      conflictsResolved: 0,
      error: error,
      startedAt: startedAt,
      completedAt: now,
    );
  }

  /// Whether there are conflicts that need manual review
  bool get hasUnresolvedConflicts => pendingConflicts.isNotEmpty;

  @override
  String toString() {
    if (!success) {
      return 'SyncResult(failed: $error)';
    }
    return 'SyncResult(synced: $entitiesSynced, sent: $entitiesSent, '
        'received: $entitiesReceived, conflicts: $conflictsDetected, '
        'resolved: $conflictsResolved, duration: ${duration.inMilliseconds}ms)';
  }
}
