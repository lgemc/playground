/// Learning statistics for a course
class LearningStats {
  final String courseId;
  final int newItems;              // Never reviewed
  final int dueItems;              // Due for review today
  final int overdueItems;          // Past due date
  final int learnedItems;          // Repetitions >= 3
  final int totalItems;
  final double overallRetention;   // Weighted average retention
  final int reviewStreak;          // Consecutive days with reviews
  final DateTime? lastReviewDate;
  final Map<String, int> itemsByType;  // Count per ReviewableType

  LearningStats({
    required this.courseId,
    required this.newItems,
    required this.dueItems,
    required this.overdueItems,
    required this.learnedItems,
    required this.totalItems,
    required this.overallRetention,
    required this.reviewStreak,
    this.lastReviewDate,
    required this.itemsByType,
  });

  int get remainingToday => dueItems + overdueItems;
  double get masteryPercentage =>
      totalItems > 0 ? (learnedItems / totalItems) * 100 : 0.0;
}
