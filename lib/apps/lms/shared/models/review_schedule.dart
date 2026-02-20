import 'package:uuid/uuid.dart';

/// Quality of recall during review
enum ReviewQuality {
  blackout,    // 0: Complete failure, no recall
  incorrect,   // 1: Incorrect response, but felt familiar
  hard,        // 2: Correct with significant difficulty
  good,        // 3: Correct with some effort
  easy,        // 4: Correct easily
  perfect,     // 5: Perfect recall, effortless
}

/// Spaced repetition schedule for a reviewable item
/// Uses SM-2 (SuperMemo 2) algorithm
class ReviewSchedule {
  final String id;
  final String reviewableItemId;
  final String userId;              // For multi-user support (default: 'default')

  // SM-2 Algorithm state
  final int repetitions;            // Number of successful reviews
  final double easeFactor;          // 1.3 - 2.5 (difficulty multiplier)
  final int intervalDays;           // Days until next review
  final DateTime nextReviewDate;

  // Performance tracking
  final int correctCount;
  final int incorrectCount;
  final double retentionRate;       // correctCount / totalCount
  final DateTime? lastReviewed;
  final ReviewQuality? lastQuality; // Last rating given
  final DateTime createdAt;
  final DateTime updatedAt;

  ReviewSchedule({
    required this.id,
    required this.reviewableItemId,
    required this.userId,
    required this.repetitions,
    required this.easeFactor,
    required this.intervalDays,
    required this.nextReviewDate,
    required this.correctCount,
    required this.incorrectCount,
    required this.retentionRate,
    this.lastReviewed,
    this.lastQuality,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReviewSchedule.create({
    required String reviewableItemId,
    String userId = 'default',
  }) {
    final now = DateTime.now();
    return ReviewSchedule(
      id: const Uuid().v4(),
      reviewableItemId: reviewableItemId,
      userId: userId,
      repetitions: 0,
      easeFactor: 2.5,  // Default difficulty
      intervalDays: 0,
      nextReviewDate: now,  // Due immediately for new items
      correctCount: 0,
      incorrectCount: 0,
      retentionRate: 0.0,
      lastReviewed: null,
      lastQuality: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  bool get isDue => DateTime.now().isAfter(nextReviewDate);
  bool get isOverdue => DateTime.now().difference(nextReviewDate).inDays > 1;
  int get totalReviews => correctCount + incorrectCount;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reviewableItemId': reviewableItemId,
      'userId': userId,
      'repetitions': repetitions,
      'easeFactor': easeFactor,
      'intervalDays': intervalDays,
      'nextReviewDate': nextReviewDate.millisecondsSinceEpoch,
      'correctCount': correctCount,
      'incorrectCount': incorrectCount,
      'retentionRate': retentionRate,
      'lastReviewed': lastReviewed?.millisecondsSinceEpoch,
      'lastQuality': lastQuality?.index,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory ReviewSchedule.fromJson(Map<String, dynamic> json) {
    return ReviewSchedule(
      id: json['id'] as String,
      reviewableItemId: json['reviewableItemId'] as String,
      userId: json['userId'] as String,
      repetitions: json['repetitions'] as int,
      easeFactor: (json['easeFactor'] as num).toDouble(),
      intervalDays: json['intervalDays'] as int,
      nextReviewDate: DateTime.fromMillisecondsSinceEpoch(
        json['nextReviewDate'] as int,
      ),
      correctCount: json['correctCount'] as int,
      incorrectCount: json['incorrectCount'] as int,
      retentionRate: (json['retentionRate'] as num).toDouble(),
      lastReviewed: json['lastReviewed'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastReviewed'] as int)
          : null,
      lastQuality: json['lastQuality'] != null
          ? ReviewQuality.values[json['lastQuality'] as int]
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['createdAt'] as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['updatedAt'] as int,
      ),
    );
  }

  /// Create from database row
  factory ReviewSchedule.fromDbRow(Map<String, Object?> row) {
    return ReviewSchedule(
      id: row['id'] as String,
      reviewableItemId: row['reviewable_item_id'] as String,
      userId: row['user_id'] as String,
      repetitions: row['repetitions'] as int,
      easeFactor: (row['ease_factor'] as num).toDouble(),
      intervalDays: row['interval_days'] as int,
      nextReviewDate: DateTime.fromMillisecondsSinceEpoch(
        row['next_review_date'] as int,
      ),
      correctCount: row['correct_count'] as int,
      incorrectCount: row['incorrect_count'] as int,
      retentionRate: (row['retention_rate'] as num).toDouble(),
      lastReviewed: row['last_reviewed'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['last_reviewed'] as int)
          : null,
      lastQuality: row['last_quality'] != null
          ? ReviewQuality.values[row['last_quality'] as int]
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int,
      ),
    );
  }

  ReviewSchedule copyWith({
    String? id,
    String? reviewableItemId,
    String? userId,
    int? repetitions,
    double? easeFactor,
    int? intervalDays,
    DateTime? nextReviewDate,
    int? correctCount,
    int? incorrectCount,
    double? retentionRate,
    DateTime? lastReviewed,
    ReviewQuality? lastQuality,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ReviewSchedule(
      id: id ?? this.id,
      reviewableItemId: reviewableItemId ?? this.reviewableItemId,
      userId: userId ?? this.userId,
      repetitions: repetitions ?? this.repetitions,
      easeFactor: easeFactor ?? this.easeFactor,
      intervalDays: intervalDays ?? this.intervalDays,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
      correctCount: correctCount ?? this.correctCount,
      incorrectCount: incorrectCount ?? this.incorrectCount,
      retentionRate: retentionRate ?? this.retentionRate,
      lastReviewed: lastReviewed ?? this.lastReviewed,
      lastQuality: lastQuality ?? this.lastQuality,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
