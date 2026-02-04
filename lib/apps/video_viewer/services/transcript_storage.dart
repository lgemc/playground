import '../../../core/database/crdt_database.dart';

/// Storage service for transcript segment metadata (e.g., relevance flags)
class TranscriptStorage {
  static TranscriptStorage? _instance;
  static TranscriptStorage get instance => _instance ??= TranscriptStorage._();

  TranscriptStorage._();

  /// Mark a segment as relevant or not relevant
  Future<void> setSegmentRelevance({
    required String fileName,
    required double segmentStart,
    required double segmentEnd,
    required bool isRelevant,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await CrdtDatabase.instance.execute('''
      INSERT OR REPLACE INTO transcript_segments
      (file_name, segment_start, segment_end, is_relevant, marked_at)
      VALUES (?, ?, ?, ?, ?)
    ''', [
      fileName,
      segmentStart,
      segmentEnd,
      isRelevant ? 1 : 0,
      now,
    ]);
  }

  /// Check if a segment is marked as relevant
  Future<bool> isSegmentRelevant({
    required String fileName,
    required double segmentStart,
    required double segmentEnd,
  }) async {
    final results = await CrdtDatabase.instance.query('''
      SELECT is_relevant FROM transcript_segments
      WHERE file_name = ? AND segment_start = ? AND segment_end = ?
    ''', [fileName, segmentStart, segmentEnd]);

    if (results.isEmpty) return false;
    return (results.first['is_relevant'] as int) == 1;
  }

  /// Get all relevant segment markers for a file
  Future<Map<String, bool>> getRelevantSegmentsForFile(String fileName) async {
    final results = await CrdtDatabase.instance.query('''
      SELECT segment_start, segment_end, is_relevant
      FROM transcript_segments
      WHERE file_name = ? AND is_relevant = 1
    ''', [fileName]);

    final map = <String, bool>{};
    for (final row in results) {
      final key = '${row['segment_start']}_${row['segment_end']}';
      map[key] = (row['is_relevant'] as int) == 1;
    }
    return map;
  }

  /// Watch relevant segments for a file (reactive)
  Stream<Map<String, bool>> watchRelevantSegments(String fileName) {
    return CrdtDatabase.instance.watch('''
      SELECT segment_start, segment_end, is_relevant
      FROM transcript_segments
      WHERE file_name = ?
    ''', [fileName]).map((results) {
      final map = <String, bool>{};
      for (final row in results) {
        final key = '${row['segment_start']}_${row['segment_end']}';
        map[key] = (row['is_relevant'] as int) == 1;
      }
      return map;
    });
  }

  /// Delete all segment markers for a file
  Future<void> clearSegmentMarkers(String fileName) async {
    await CrdtDatabase.instance.execute('''
      DELETE FROM transcript_segments WHERE file_name = ?
    ''', [fileName]);
  }
}
