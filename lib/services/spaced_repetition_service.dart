import '../core/database/crdt_database.dart';
import '../apps/lms/shared/models/review_schedule.dart';
import '../apps/lms/shared/models/reviewable_item.dart';
import '../apps/lms/shared/models/learning_stats.dart';

class SpacedRepetitionService {
  static SpacedRepetitionService? _instance;
  static SpacedRepetitionService get instance =>
      _instance ??= SpacedRepetitionService._();

  SpacedRepetitionService._();

  /// Update schedule after user reviews an item
  /// Based on SM-2 (SuperMemo 2) algorithm
  Future<ReviewSchedule> updateAfterReview(
    ReviewSchedule current,
    ReviewQuality quality,
  ) async {
    final now = DateTime.now();
    int newRepetitions = current.repetitions;
    double newEaseFactor = current.easeFactor;
    int newInterval = current.intervalDays;
    int newCorrect = current.correctCount;
    int newIncorrect = current.incorrectCount;

    // Update performance counters
    if (quality.index >= 3) {
      // Good, easy, or perfect
      newCorrect++;
    } else {
      // Blackout, incorrect, or hard
      newIncorrect++;
    }

    // SM-2 Algorithm
    if (quality.index < 3) {
      // Failed: reset interval but keep ease factor
      newRepetitions = 0;
      newInterval = 1;
    } else {
      // Passed: increase interval
      newRepetitions++;

      // Update ease factor
      newEaseFactor = current.easeFactor +
          (0.1 - (5 - quality.index) * (0.08 + (5 - quality.index) * 0.02));

      // Clamp ease factor between 1.3 and 2.5
      if (newEaseFactor < 1.3) newEaseFactor = 1.3;
      if (newEaseFactor > 2.5) newEaseFactor = 2.5;

      // Calculate new interval
      if (newRepetitions == 1) {
        newInterval = 1;
      } else if (newRepetitions == 2) {
        newInterval = 6;
      } else {
        newInterval = (current.intervalDays * newEaseFactor).round();
      }
    }

    // Calculate retention rate
    final totalReviews = newCorrect + newIncorrect;
    final newRetention = totalReviews > 0 ? newCorrect / totalReviews : 0.0;

    // Create updated schedule
    final updated = current.copyWith(
      repetitions: newRepetitions,
      easeFactor: newEaseFactor,
      intervalDays: newInterval,
      nextReviewDate: now.add(Duration(days: newInterval)),
      correctCount: newCorrect,
      incorrectCount: newIncorrect,
      retentionRate: newRetention,
      lastReviewed: now,
      lastQuality: quality,
      updatedAt: now,
    );

    // Save to database
    await _saveSchedule(updated);

    return updated;
  }

  /// Get items due for review today
  Future<List<ReviewableItemWithSchedule>> getDueReviews({
    String? courseId,
    int maxItems = 20,
    String userId = 'default',
  }) async {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    String query = '''
      SELECT
        ri.*,
        rs.id as schedule_id,
        rs.repetitions,
        rs.ease_factor,
        rs.interval_days,
        rs.next_review_date,
        rs.correct_count,
        rs.incorrect_count,
        rs.retention_rate,
        rs.last_reviewed,
        rs.last_quality
      FROM reviewable_items ri
      INNER JOIN review_schedules rs ON ri.id = rs.reviewable_item_id
      WHERE rs.user_id = ?
        AND rs.next_review_date <= ?
    ''';

    List<dynamic> args = [userId, nowMs];

    if (courseId != null) {
      query += ' AND ri.course_id = ?';
      args.add(courseId);
    }

    query += '''
      ORDER BY
        (rs.next_review_date < ?) DESC,  -- Overdue first
        rs.next_review_date ASC,         -- Oldest due first
        rs.repetitions ASC               -- New items before mature
      LIMIT ?
    ''';

    args.addAll([nowMs, maxItems]);

    final rows = await CrdtDatabase.instance.query(query, args);
    return rows.map((row) => ReviewableItemWithSchedule.fromRow(row)).toList();
  }

  /// Get learning statistics for a course
  Future<LearningStats> getStats(String courseId,
      {String userId = 'default'}) async {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    // Count by status
    final countQuery = '''
      SELECT
        COUNT(CASE WHEN rs.repetitions = 0 THEN 1 END) as new_items,
        COUNT(CASE WHEN rs.next_review_date <= ? AND rs.repetitions > 0 THEN 1 END) as due_items,
        COUNT(CASE WHEN rs.next_review_date < ? - 86400000 THEN 1 END) as overdue_items,
        COUNT(CASE WHEN rs.repetitions >= 3 THEN 1 END) as learned_items,
        COUNT(*) as total_items,
        AVG(rs.retention_rate) as avg_retention
      FROM reviewable_items ri
      INNER JOIN review_schedules rs ON ri.id = rs.reviewable_item_id
      WHERE ri.course_id = ? AND rs.user_id = ?
    ''';

    final countRows = await CrdtDatabase.instance.query(
      countQuery,
      [nowMs, nowMs, courseId, userId],
    );

    if (countRows.isEmpty) {
      return LearningStats(
        courseId: courseId,
        newItems: 0,
        dueItems: 0,
        overdueItems: 0,
        learnedItems: 0,
        totalItems: 0,
        overallRetention: 0.0,
        reviewStreak: 0,
        lastReviewDate: null,
        itemsByType: {},
      );
    }

    final counts = countRows.first;

    // Count by type
    final typeQuery = '''
      SELECT ri.type, COUNT(*) as count
      FROM reviewable_items ri
      INNER JOIN review_schedules rs ON ri.id = rs.reviewable_item_id
      WHERE ri.course_id = ? AND rs.user_id = ?
      GROUP BY ri.type
    ''';

    final typeRows = await CrdtDatabase.instance.query(
      typeQuery,
      [courseId, userId],
    );
    final itemsByType = <String, int>{};
    for (final row in typeRows) {
      itemsByType[row['type'] as String] = row['count'] as int;
    }

    // Get last review date
    final lastReviewQuery = '''
      SELECT MAX(rs.last_reviewed) as last_date
      FROM review_schedules rs
      INNER JOIN reviewable_items ri ON ri.id = rs.reviewable_item_id
      WHERE ri.course_id = ? AND rs.user_id = ?
    ''';

    final lastRows = await CrdtDatabase.instance.query(
      lastReviewQuery,
      [courseId, userId],
    );
    final lastReviewMs = lastRows.first['last_date'] as int?;
    final lastReviewDate = lastReviewMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lastReviewMs)
        : null;

    // Calculate streak (simplified: consecutive days with at least 1 review)
    final streak = await _calculateReviewStreak(courseId, userId);

    return LearningStats(
      courseId: courseId,
      newItems: counts['new_items'] as int,
      dueItems: counts['due_items'] as int,
      overdueItems: counts['overdue_items'] as int,
      learnedItems: counts['learned_items'] as int,
      totalItems: counts['total_items'] as int,
      overallRetention: (counts['avg_retention'] as num?)?.toDouble() ?? 0.0,
      reviewStreak: streak,
      lastReviewDate: lastReviewDate,
      itemsByType: itemsByType,
    );
  }

  /// Create initial schedule for new reviewable item
  Future<ReviewSchedule> createSchedule(
    String reviewableItemId, {
    String userId = 'default',
  }) async {
    final schedule = ReviewSchedule.create(
      reviewableItemId: reviewableItemId,
      userId: userId,
    );

    await _saveSchedule(schedule);
    return schedule;
  }

  /// Batch create schedules for multiple items
  Future<void> createSchedulesForItems(
    List<String> reviewableItemIds, {
    String userId = 'default',
  }) async {
    for (final itemId in reviewableItemIds) {
      // Check if schedule already exists
      final existing = await getSchedule(itemId, userId: userId);
      if (existing == null) {
        await createSchedule(itemId, userId: userId);
      }
    }
  }

  /// Get schedule for a specific item
  Future<ReviewSchedule?> getSchedule(
    String reviewableItemId, {
    String userId = 'default',
  }) async {
    final rows = await CrdtDatabase.instance.query(
      'SELECT * FROM review_schedules WHERE reviewable_item_id = ? AND user_id = ?',
      [reviewableItemId, userId],
    );

    if (rows.isEmpty) return null;
    return ReviewSchedule.fromDbRow(rows.first);
  }

  // Private helper methods

  Future<void> _saveSchedule(ReviewSchedule schedule) async {
    final existing = await CrdtDatabase.instance.query(
      'SELECT id FROM review_schedules WHERE id = ?',
      [schedule.id],
    );

    final data = schedule.toJson();

    if (existing.isEmpty) {
      await CrdtDatabase.instance.execute(
        '''INSERT INTO review_schedules
           (id, reviewable_item_id, user_id, repetitions, ease_factor,
            interval_days, next_review_date, correct_count, incorrect_count,
            retention_rate, last_reviewed, last_quality, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          data['id'],
          data['reviewableItemId'],
          data['userId'],
          data['repetitions'],
          data['easeFactor'],
          data['intervalDays'],
          data['nextReviewDate'],
          data['correctCount'],
          data['incorrectCount'],
          data['retentionRate'],
          data['lastReviewed'],
          data['lastQuality'],
          data['createdAt'],
          data['updatedAt'],
        ],
      );
    } else {
      await CrdtDatabase.instance.execute(
        '''UPDATE review_schedules
           SET repetitions = ?, ease_factor = ?, interval_days = ?,
               next_review_date = ?, correct_count = ?, incorrect_count = ?,
               retention_rate = ?, last_reviewed = ?, last_quality = ?,
               updated_at = ?
           WHERE id = ?''',
        [
          data['repetitions'],
          data['easeFactor'],
          data['intervalDays'],
          data['nextReviewDate'],
          data['correctCount'],
          data['incorrectCount'],
          data['retentionRate'],
          data['lastReviewed'],
          data['lastQuality'],
          data['updatedAt'],
          data['id'],
        ],
      );
    }
  }

  Future<int> _calculateReviewStreak(String courseId, String userId) async {
    final now = DateTime.now();
    int streak = 0;

    // Check each day going backwards
    for (int i = 0; i < 365; i++) {
      final checkDate = now.subtract(Duration(days: i));
      final startOfDay =
          DateTime(checkDate.year, checkDate.month, checkDate.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final rows = await CrdtDatabase.instance.query(
        '''SELECT COUNT(*) as count
           FROM review_schedules rs
           INNER JOIN reviewable_items ri ON ri.id = rs.reviewable_item_id
           WHERE ri.course_id = ?
             AND rs.user_id = ?
             AND rs.last_reviewed >= ?
             AND rs.last_reviewed < ?''',
        [
          courseId,
          userId,
          startOfDay.millisecondsSinceEpoch,
          endOfDay.millisecondsSinceEpoch,
        ],
      );

      if ((rows.first['count'] as int) > 0) {
        streak++;
      } else {
        break; // Streak broken
      }
    }

    return streak;
  }
}

/// Helper class combining ReviewableItem with its schedule
class ReviewableItemWithSchedule {
  final ReviewableItem item;
  final ReviewSchedule schedule;

  ReviewableItemWithSchedule({
    required this.item,
    required this.schedule,
  });

  factory ReviewableItemWithSchedule.fromRow(Map<String, Object?> row) {
    // Parse ReviewableItem fields
    final item = ReviewableItem.fromDbRow(row);

    // Parse ReviewSchedule fields
    final schedule = ReviewSchedule.fromJson({
      'id': row['schedule_id'],
      'reviewableItemId': row['id'],
      'userId': 'default',
      'repetitions': row['repetitions'],
      'easeFactor': row['ease_factor'],
      'intervalDays': row['interval_days'],
      'nextReviewDate': row['next_review_date'],
      'correctCount': row['correct_count'],
      'incorrectCount': row['incorrect_count'],
      'retentionRate': row['retention_rate'],
      'lastReviewed': row['last_reviewed'],
      'lastQuality': row['last_quality'],
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
    });

    return ReviewableItemWithSchedule(item: item, schedule: schedule);
  }
}
