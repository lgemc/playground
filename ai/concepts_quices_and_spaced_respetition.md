# Concepts, Quizzes, and Spaced Repetition System

## Overview

This document outlines the implementation of a complete learning system that covers all levels of Bloom's taxonomy through concept extraction, quizzing, and spaced repetition. Based on evidence-based learning theories including the Testing Effect, Spacing Effect, and Retrieval Practice.

---

## Pedagogical Framework

### Learning Theories Foundation

**1. Bloom's Taxonomy Coverage**
- **Remember**: Flashcards, definition recall
- **Understand**: Comprehension quizzes, explanations
- **Apply**: Practice problems, scenarios
- **Analyze**: Compare/contrast, categorization
- **Evaluate**: Critique tasks, assessment
- **Create**: Projects, synthesis

**2. Evidence-Based Principles**
- **Testing Effect** (Karpicke & Roediger, 2008): Retrieval practice > re-reading
- **Spacing Effect** (Cepeda et al., 2006): Distributed practice > massed practice
- **Interleaving** (Rohrer & Taylor, 2007): Mixed practice > blocked practice
- **Generation Effect**: Self-generated > presented information
- **Elaboration**: Deep processing through "why" questions

### Optimal Learning Flow

```
Content Exposure → Active Processing → Immediate Testing →
Spaced Reviews → Application → Higher-Order Synthesis
```

**Timeline for single concept:**
1. **Day 0**: Expose (lecture/reading) + immediate quiz
2. **Day 1**: First spaced review (flashcard)
3. **Day 3**: Second review + application problem
4. **Day 7**: Interleaved quiz with other concepts
5. **Day 14**: Application project
6. **Day 30**: Synthesis/evaluation task

---

## Current Architecture Analysis

### Existing LMS Structure

```
Course → Module → SubSection → Activity
```

**Activities (lib/apps/lms/shared/models/activity.dart):**
- ResourceFileActivity: videos, PDFs, audio
- QuizActivity: PLANNED but not implemented (line 44-46)

**Related Systems:**
- **DerivativeArtifacts** (ai/_derivate_artifacts.md): Auto-generate transcripts/summaries
- **Vocabulary App** (lib/apps/vocabulary): Word learning WITHOUT spaced repetition
- **Notes App** (lib/apps/notes): Note-taking capability
- **File System** (lib/apps/file_system): Resource storage

### Critical Gaps

❌ **No concept-level tracking**: Activities are containers, not atomic learnable units
❌ **No spaced repetition**: Vocabulary app lacks SRS
❌ **No quiz implementation**: ActivityType.quiz exists but unimplemented
❌ **No progress tracking**: Can't measure mastery
❌ **No learning analytics**: No retention curves or weak area identification

---

## Architecture Design

### Problem Statement

**Activities ≠ Concepts**

An activity (video, PDF) contains 10-50 concepts. To implement spaced repetition, we need to:
1. Extract atomic learnable units (concepts)
2. Track each concept's review schedule independently
3. Present concepts in daily review sessions
4. Measure retention per concept

### Solution: Three-Layer Model

```
Course/Module/SubSection/Activity
        ↓
   [Extraction]
        ↓
ReviewableItem (concept/question/flashcard)
        ↓
   [Scheduling]
        ↓
ReviewSchedule (SM-2 state per item)
```

---

## Data Models

### 1. ReviewableItem

**Location**: `lib/apps/lms/shared/models/reviewable_item.dart`

```dart
class ReviewableItem {
  final String id;
  final String activityId;          // Source activity
  final String courseId;            // For filtering by course
  final String? moduleId;           // Optional: for module-level filtering
  final String? subSectionId;       // Optional: for granular filtering
  final ReviewableType type;
  final String content;             // Question text or term
  final String? answer;             // For flashcards or correct answer
  final List<String> distractors;   // For multiple choice questions
  final Map<String, dynamic> metadata;  // Extra data (hints, explanations)
  final DateTime createdAt;
  final DateTime updatedAt;

  ReviewableItem({
    required this.id,
    required this.activityId,
    required this.courseId,
    this.moduleId,
    this.subSectionId,
    required this.type,
    required this.content,
    this.answer,
    this.distractors = const [],
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReviewableItem.create({
    required String activityId,
    required String courseId,
    String? moduleId,
    String? subSectionId,
    required ReviewableType type,
    required String content,
    String? answer,
    List<String>? distractors,
    Map<String, dynamic>? metadata,
  }) {
    final now = DateTime.now();
    return ReviewableItem(
      id: Uuid().v4(),
      activityId: activityId,
      courseId: courseId,
      moduleId: moduleId,
      subSectionId: subSectionId,
      type: type,
      content: content,
      answer: answer,
      distractors: distractors ?? [],
      metadata: metadata ?? {},
      createdAt: now,
      updatedAt: now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'activityId': activityId,
      'courseId': courseId,
      'moduleId': moduleId,
      'subSectionId': subSectionId,
      'type': type.name,
      'content': content,
      'answer': answer,
      'distractors': distractors,
      'metadata': metadata,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ReviewableItem.fromJson(Map<String, dynamic> json) {
    return ReviewableItem(
      id: json['id'] as String,
      activityId: json['activityId'] as String,
      courseId: json['courseId'] as String,
      moduleId: json['moduleId'] as String?,
      subSectionId: json['subSectionId'] as String?,
      type: ReviewableType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => ReviewableType.flashcard,
      ),
      content: json['content'] as String,
      answer: json['answer'] as String?,
      distractors: (json['distractors'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  ReviewableItem copyWith({
    String? id,
    String? activityId,
    String? courseId,
    String? moduleId,
    String? subSectionId,
    ReviewableType? type,
    String? content,
    String? answer,
    List<String>? distractors,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ReviewableItem(
      id: id ?? this.id,
      activityId: activityId ?? this.activityId,
      courseId: courseId ?? this.courseId,
      moduleId: moduleId ?? this.moduleId,
      subSectionId: subSectionId ?? this.subSectionId,
      type: type ?? this.type,
      content: content ?? this.content,
      answer: answer ?? this.answer,
      distractors: distractors ?? this.distractors,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum ReviewableType {
  flashcard,      // Term/definition pairs (front/back cards)
  multipleChoice, // Question with distractors
  trueFalse,      // Boolean questions
  shortAnswer,    // Open-ended questions
  fillInBlank,    // Cloze deletion
  procedure,      // Step-by-step sequences
  summary,        // Key takeaway statements
}
```

### 2. ReviewSchedule

**Location**: `lib/apps/lms/shared/models/review_schedule.dart`

```dart
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
      id: Uuid().v4(),
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

enum ReviewQuality {
  blackout,    // 0: Complete failure, no recall
  incorrect,   // 1: Incorrect response, but felt familiar
  hard,        // 2: Correct with significant difficulty
  good,        // 3: Correct with some effort
  easy,        // 4: Correct easily
  perfect,     // 5: Perfect recall, effortless
}
```

### 3. LearningStats

**Location**: `lib/apps/lms/shared/models/learning_stats.dart`

```dart
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
```

---

## Concept Extraction System

### Strategy 1: From Video/Audio Transcripts

**Pipeline:**
```
Video Activity → Transcript (DerivativeArtifact) →
LLM Concept Extraction → ReviewableItems
```

**Service**: `lib/services/concept_extraction_service.dart`

```dart
class ConceptExtractionService {
  static ConceptExtractionService? _instance;
  static ConceptExtractionService get instance =>
    _instance ??= ConceptExtractionService._();

  /// Extract concepts from transcript using LLM
  Future<List<ReviewableItem>> extractFromTranscript({
    required String activityId,
    required String courseId,
    required String transcript,
    String? moduleId,
    String? subSectionId,
  }) async {
    final prompt = '''Extract key learning concepts from this lecture transcript.

Create reviewable items in these categories:
1. FLASHCARDS: Term/definition pairs for vocabulary and concepts
2. QUESTIONS: Important principles as multiple-choice questions
3. PROCEDURES: Step-by-step processes

For each item, provide:
- Type (flashcard/multipleChoice/procedure)
- Content (question or term)
- Answer (correct answer or definition)
- Distractors (3 plausible wrong answers for MCQs)

Transcript:
$transcript

Output as JSON array:
[
  {
    "type": "flashcard",
    "content": "What is a StatefulWidget?",
    "answer": "A widget that maintains mutable state that can change over time"
  },
  {
    "type": "multipleChoice",
    "content": "When should you use setState()?",
    "answer": "When you need to update the UI based on changed internal state",
    "distractors": [
      "When you need to initialize widget state",
      "When you need to dispose of resources",
      "When you need to navigate to another screen"
    ]
  }
]''';

    try {
      final response = await AutocompletionService.instance.promptStream(
        prompt,
        temperature: 0.3,  // Lower temperature for consistency
        maxTokens: 2000,
      ).join();

      return _parseJsonToReviewableItems(
        response,
        activityId: activityId,
        courseId: courseId,
        moduleId: moduleId,
        subSectionId: subSectionId,
      );
    } catch (e) {
      print('Concept extraction failed: $e');
      return [];
    }
  }

  /// Extract concepts from document/summary text
  Future<List<ReviewableItem>> extractFromDocument({
    required String activityId,
    required String courseId,
    required String documentText,
    String? moduleId,
    String? subSectionId,
  }) async {
    // Similar to transcript extraction but optimized for written content
    // Focus on: definitions, principles, key facts
    final prompt = '''Extract key concepts from this educational document.

Focus on:
- Important definitions (as flashcards)
- Core principles (as questions)
- Critical facts (as flashcards)

Document:
$documentText

Output as JSON array with type, content, answer, and optional distractors.''';

    try {
      final response = await AutocompletionService.instance.promptStream(
        prompt,
        temperature: 0.3,
        maxTokens: 2000,
      ).join();

      return _parseJsonToReviewableItems(
        response,
        activityId: activityId,
        courseId: courseId,
        moduleId: moduleId,
        subSectionId: subSectionId,
      );
    } catch (e) {
      print('Document concept extraction failed: $e');
      return [];
    }
  }

  /// Parse LLM JSON response to ReviewableItem list
  List<ReviewableItem> _parseJsonToReviewableItems(
    String jsonResponse, {
    required String activityId,
    required String courseId,
    String? moduleId,
    String? subSectionId,
  }) {
    try {
      // Clean JSON (remove markdown code blocks if present)
      final cleanJson = jsonResponse
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*$'), '')
          .trim();

      final List<dynamic> jsonList = json.decode(cleanJson);

      return jsonList.map((item) {
        final type = _parseReviewableType(item['type'] as String);
        return ReviewableItem.create(
          activityId: activityId,
          courseId: courseId,
          moduleId: moduleId,
          subSectionId: subSectionId,
          type: type,
          content: item['content'] as String,
          answer: item['answer'] as String?,
          distractors: (item['distractors'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList(),
        );
      }).toList();
    } catch (e) {
      print('JSON parsing failed: $e');
      return [];
    }
  }

  ReviewableType _parseReviewableType(String typeString) {
    switch (typeString.toLowerCase()) {
      case 'flashcard':
        return ReviewableType.flashcard;
      case 'multiplechoice':
      case 'multiple_choice':
        return ReviewableType.multipleChoice;
      case 'truefalse':
      case 'true_false':
        return ReviewableType.trueFalse;
      case 'shortanswer':
      case 'short_answer':
        return ReviewableType.shortAnswer;
      case 'fillinblank':
      case 'fill_in_blank':
        return ReviewableType.fillInBlank;
      case 'procedure':
        return ReviewableType.procedure;
      case 'summary':
        return ReviewableType.summary;
      default:
        return ReviewableType.flashcard;
    }
  }
}
```

### Strategy 2: From Quizzes (Direct Mapping)

**When QuizActivity is implemented:**

```dart
extension QuizToReviewable on QuizActivity {
  List<ReviewableItem> toReviewableItems() {
    return questions.map((q) {
      return ReviewableItem.create(
        activityId: id,
        courseId: courseId,
        moduleId: moduleId,
        subSectionId: subSectionId,
        type: ReviewableType.multipleChoice,
        content: q.text,
        answer: q.correctAnswer,
        distractors: q.wrongAnswers,
        metadata: {
          'explanation': q.explanation,
          'difficulty': q.difficulty,
        },
      );
    }).toList();
  }
}
```

### Strategy 3: Manual Creation

**UI Screen**: `lib/apps/lms/screens/concept_manager_screen.dart`

Allows instructors to:
- View all concepts extracted from an activity
- Add new concepts manually
- Edit/delete auto-generated concepts
- Bulk import from CSV/JSON

---

## Spaced Repetition Service

**Location**: `lib/services/spaced_repetition_service.dart`

### SM-2 Algorithm Implementation

```dart
import 'dart:math';
import '../core/database/crdt_database.dart';
import '../apps/lms/shared/models/review_schedule.dart';
import '../apps/lms/shared/models/reviewable_item.dart';

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
    final newRetention = totalReviews > 0
      ? newCorrect / totalReviews
      : 0.0;

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
  Future<LearningStats> getStats(String courseId, {String userId = 'default'}) async {
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
      await createSchedule(itemId, userId: userId);
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
    return ReviewSchedule.fromJson(rows.first);
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
      final startOfDay = DateTime(checkDate.year, checkDate.month, checkDate.day);
      final endOfDay = startOfDay.add(Duration(days: 1));

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
        break;  // Streak broken
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
    final item = ReviewableItem.fromJson({
      'id': row['id'],
      'activityId': row['activity_id'],
      'courseId': row['course_id'],
      'moduleId': row['module_id'],
      'subSectionId': row['sub_section_id'],
      'type': row['type'],
      'content': row['content'],
      'answer': row['answer'],
      'distractors': row['distractors'],
      'metadata': row['metadata'],
      'createdAt': DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int,
      ).toIso8601String(),
      'updatedAt': DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int,
      ).toIso8601String(),
    });

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
```

---

## Queue Integration

### Queue Consumer for Concept Extraction

**Location**: `lib/services/concept_extraction_consumer.dart`

```dart
import '../core/app_event.dart';
import '../services/queue_service.dart';
import '../services/concept_extraction_service.dart';
import '../services/spaced_repetition_service.dart';

class ConceptExtractionConsumer extends QueueConsumer {
  @override
  String get queueId => 'concept-extraction';

  @override
  Future<void> consume(AppEvent event, AckFunction ack) async {
    try {
      if (event.type == 'derivative.completed') {
        await _handleDerivativeCompleted(event);
      }
      await ack();
    } catch (e) {
      print('Concept extraction failed: $e');
      throw e;  // Will trigger retry
    }
  }

  Future<void> _handleDerivativeCompleted(AppEvent event) async {
    final derivativeType = event.metadata['derivativeType'] as String?;
    final activityId = event.metadata['activityId'] as String?;
    final courseId = event.metadata['courseId'] as String;
    final content = event.metadata['content'] as String?;

    if (activityId == null || content == null) return;

    List<ReviewableItem> items = [];

    if (derivativeType == 'transcript') {
      items = await ConceptExtractionService.instance.extractFromTranscript(
        activityId: activityId,
        courseId: courseId,
        transcript: content,
      );
    } else if (derivativeType == 'summary') {
      items = await ConceptExtractionService.instance.extractFromDocument(
        activityId: activityId,
        courseId: courseId,
        documentText: content,
      );
    }

    // Save reviewable items
    for (final item in items) {
      await _saveReviewableItem(item);
      // Create initial schedule
      await SpacedRepetitionService.instance.createSchedule(item.id);
    }

    print('Extracted ${items.length} concepts from $derivativeType');
  }

  Future<void> _saveReviewableItem(ReviewableItem item) async {
    final data = item.toJson();
    await CrdtDatabase.instance.execute(
      '''INSERT INTO reviewable_items
         (id, activity_id, course_id, module_id, sub_section_id, type,
          content, answer, distractors, metadata, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        data['id'],
        data['activityId'],
        data['courseId'],
        data['moduleId'],
        data['subSectionId'],
        data['type'],
        data['content'],
        data['answer'],
        json.encode(data['distractors']),
        json.encode(data['metadata']),
        DateTime.parse(data['createdAt'] as String).millisecondsSinceEpoch,
        DateTime.parse(data['updatedAt'] as String).millisecondsSinceEpoch,
      ],
    );
  }
}
```

### Queue Configuration

**Update**: `lib/services/queue_config.dart`

```dart
static final Map<String, QueueConfig> queues = {
  // ... existing queues

  'concept-extraction': QueueConfig(
    id: 'concept-extraction',
    maxRetries: 3,
    retryDelay: Duration(seconds: 10),
    consumers: [
      ConceptExtractionConsumer(),
    ],
  ),
};
```

---

## Database Schema

### Migration Script

**Location**: `lib/core/database/migrations/add_spaced_repetition.dart`

```sql
-- Reviewable items (extracted concepts)
CREATE TABLE IF NOT EXISTS reviewable_items (
  id TEXT PRIMARY KEY,
  activity_id TEXT NOT NULL,
  course_id TEXT NOT NULL,
  module_id TEXT,
  sub_section_id TEXT,
  type TEXT NOT NULL,  -- flashcard, multipleChoice, etc.
  content TEXT NOT NULL,
  answer TEXT,
  distractors TEXT,  -- JSON array
  metadata TEXT,     -- JSON object
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX idx_reviewable_activity ON reviewable_items(activity_id);
CREATE INDEX idx_reviewable_course ON reviewable_items(course_id);
CREATE INDEX idx_reviewable_type ON reviewable_items(type);

-- Review schedules (SM-2 state)
CREATE TABLE IF NOT EXISTS review_schedules (
  id TEXT PRIMARY KEY,
  reviewable_item_id TEXT NOT NULL,
  user_id TEXT NOT NULL DEFAULT 'default',
  repetitions INTEGER NOT NULL DEFAULT 0,
  ease_factor REAL NOT NULL DEFAULT 2.5,
  interval_days INTEGER NOT NULL DEFAULT 0,
  next_review_date INTEGER NOT NULL,
  correct_count INTEGER NOT NULL DEFAULT 0,
  incorrect_count INTEGER NOT NULL DEFAULT 0,
  retention_rate REAL NOT NULL DEFAULT 0.0,
  last_reviewed INTEGER,
  last_quality INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (reviewable_item_id) REFERENCES reviewable_items(id) ON DELETE CASCADE
);

CREATE INDEX idx_schedule_item ON review_schedules(reviewable_item_id);
CREATE INDEX idx_schedule_user ON review_schedules(user_id);
CREATE INDEX idx_schedule_due ON review_schedules(next_review_date, user_id);
CREATE INDEX idx_schedule_last_reviewed ON review_schedules(last_reviewed);
CREATE UNIQUE INDEX idx_schedule_user_item ON review_schedules(reviewable_item_id, user_id);
```

---

## UI Implementation

### 1. Review Session Screen

**Location**: `lib/apps/lms/screens/review_session_screen.dart`

```dart
class ReviewSessionScreen extends StatefulWidget {
  final String courseId;
  final int maxItems;

  const ReviewSessionScreen({
    Key? key,
    required this.courseId,
    this.maxItems = 20,
  }) : super(key: key);

  @override
  State<ReviewSessionScreen> createState() => _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends State<ReviewSessionScreen> {
  List<ReviewableItemWithSchedule> _items = [];
  int _currentIndex = 0;
  bool _showingAnswer = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    final items = await SpacedRepetitionService.instance.getDueReviews(
      courseId: widget.courseId,
      maxItems: widget.maxItems,
    );
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  void _showAnswer() {
    setState(() {
      _showingAnswer = true;
    });
  }

  Future<void> _submitQuality(ReviewQuality quality) async {
    final current = _items[_currentIndex];

    // Update schedule
    await SpacedRepetitionService.instance.updateAfterReview(
      current.schedule,
      quality,
    );

    // Move to next or finish
    if (_currentIndex < _items.length - 1) {
      setState(() {
        _currentIndex++;
        _showingAnswer = false;
      });
    } else {
      // Session complete
      _showCompletionDialog();
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Session Complete!'),
        content: Text('You reviewed ${_items.length} items.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);  // Exit review session
            },
            child: Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('Loading...')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Review Session')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, size: 64, color: Colors.green),
              SizedBox(height: 16),
              Text('No reviews due!', style: Theme.of(context).textTheme.headlineSmall),
              SizedBox(height: 8),
              Text('Come back later for more practice.'),
            ],
          ),
        ),
      );
    }

    final current = _items[_currentIndex];
    final progress = (_currentIndex + 1) / _items.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Review Session'),
        actions: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text('${_currentIndex + 1}/${_items.length}'),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(4),
          child: LinearProgressIndicator(value: progress),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Type badge
            Chip(
              label: Text(current.item.type.name),
              backgroundColor: _getTypeColor(current.item.type),
            ),
            SizedBox(height: 24),

            // Question
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  current.item.content,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            SizedBox(height: 24),

            // Answer section
            if (_showingAnswer) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Answer:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade900,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        current.item.answer ?? '',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 24),

              // Quality rating
              Text(
                'Rate your recall:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildQualityButton('Blackout', ReviewQuality.blackout, Colors.red),
                  _buildQualityButton('Hard', ReviewQuality.hard, Colors.orange),
                  _buildQualityButton('Good', ReviewQuality.good, Colors.blue),
                  _buildQualityButton('Easy', ReviewQuality.easy, Colors.green),
                ],
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: _showAnswer,
                icon: Icon(Icons.visibility),
                label: Text('Show Answer'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.all(16),
                ),
              ),
            ],

            Spacer(),

            // Stats
            Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatColumn(
                      'Repetitions',
                      current.schedule.repetitions.toString(),
                    ),
                    _buildStatColumn(
                      'Interval',
                      '${current.schedule.intervalDays}d',
                    ),
                    _buildStatColumn(
                      'Retention',
                      '${(current.schedule.retentionRate * 100).round()}%',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityButton(String label, ReviewQuality quality, Color color) {
    return ElevatedButton(
      onPressed: () => _submitQuality(quality),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      child: Text(label),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Color _getTypeColor(ReviewableType type) {
    switch (type) {
      case ReviewableType.flashcard:
        return Colors.blue.shade100;
      case ReviewableType.multipleChoice:
        return Colors.purple.shade100;
      case ReviewableType.trueFalse:
        return Colors.green.shade100;
      default:
        return Colors.grey.shade100;
    }
  }
}
```

### 2. Learning Progress Widget

**Location**: `lib/apps/lms/widgets/learning_progress_card.dart`

Add to course detail screen:

```dart
class LearningProgressCard extends StatelessWidget {
  final String courseId;

  const LearningProgressCard({Key? key, required this.courseId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LearningStats>(
      future: SpacedRepetitionService.instance.getStats(courseId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final stats = snapshot.data!;

        return Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.analytics, color: Theme.of(context).primaryColor),
                    SizedBox(width: 8),
                    Text(
                      'Learning Progress',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                SizedBox(height: 16),

                // Stats grid
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat(
                      context,
                      'Due Today',
                      stats.remainingToday.toString(),
                      Icons.today,
                      stats.remainingToday > 0 ? Colors.orange : Colors.green,
                    ),
                    _buildStat(
                      context,
                      'Learned',
                      stats.learnedItems.toString(),
                      Icons.check_circle,
                      Colors.green,
                    ),
                    _buildStat(
                      context,
                      'Retention',
                      '${(stats.overallRetention * 100).round()}%',
                      Icons.trending_up,
                      Colors.blue,
                    ),
                  ],
                ),
                SizedBox(height: 16),

                // Streak
                if (stats.reviewStreak > 0)
                  Row(
                    children: [
                      Icon(Icons.local_fire_department, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('${stats.reviewStreak} day streak!'),
                    ],
                  ),

                SizedBox(height: 16),

                // Action button
                if (stats.remainingToday > 0)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ReviewSessionScreen(
                            courseId: courseId,
                          ),
                        ),
                      );
                    },
                    icon: Icon(Icons.play_arrow),
                    label: Text('Start Review Session'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size(double.infinity, 48),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStat(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}
```

### 3. Activity Completion Flow

After user completes an activity (watches video, reads document):

```dart
void _onActivityCompleted(Activity activity) async {
  // Check if concepts already extracted
  final hasItems = await _hasReviewableItems(activity.id);

  if (!hasItems) {
    // Offer to generate concepts
    final shouldGenerate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Activity Complete!'),
        content: Text(
          'Would you like to generate flashcards and quizzes from this content? '
          'This will help you remember what you learned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Generate'),
          ),
        ],
      ),
    );

    if (shouldGenerate == true) {
      _generateConcepts(activity);
    }
  }
}

Future<void> _generateConcepts(Activity activity) async {
  // Show loading
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('Extracting concepts...'),
        ],
      ),
    ),
  );

  try {
    // Trigger concept extraction via queue
    await AppBus.instance.emit(AppEvent.create(
      type: 'activity.completed',
      appId: 'lms',
      metadata: {
        'activityId': activity.id,
        'courseId': activity.courseId,
        'generateConcepts': true,
      },
    ));

    Navigator.pop(context);  // Close loading

    // Show success
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Concepts will be ready for review soon!'),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
      ),
    );
  } catch (e) {
    Navigator.pop(context);  // Close loading
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to generate concepts')),
    );
  }
}
```

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)

**Goals**: Core data models and database schema

- [ ] Create `ReviewableItem` model (lib/apps/lms/shared/models/reviewable_item.dart)
- [ ] Create `ReviewSchedule` model (lib/apps/lms/shared/models/review_schedule.dart)
- [ ] Create `LearningStats` model (lib/apps/lms/shared/models/learning_stats.dart)
- [ ] Add database migration script for new tables
- [ ] Write unit tests for models (serialization, validation)

### Phase 2: Spaced Repetition Service (Week 2-3)

**Goals**: SM-2 algorithm implementation

- [ ] Create `SpacedRepetitionService` (lib/services/spaced_repetition_service.dart)
- [ ] Implement SM-2 algorithm in `updateAfterReview()`
- [ ] Implement `getDueReviews()` with proper ordering
- [ ] Implement `getStats()` for analytics
- [ ] Write unit tests for SM-2 calculations
- [ ] Write integration tests for database operations

### Phase 3: Concept Extraction (Week 3-4)

**Goals**: Auto-generate reviewable items from content

- [ ] Create `ConceptExtractionService` (lib/services/concept_extraction_service.dart)
- [ ] Implement transcript extraction with LLM
- [ ] Implement document extraction with LLM
- [ ] Create `ConceptExtractionConsumer` queue consumer
- [ ] Register queue in `queue_config.dart`
- [ ] Test extraction with sample transcripts/documents
- [ ] Tune LLM prompts for quality

### Phase 4: Review UI (Week 4-5)

**Goals**: User interface for reviews

- [ ] Create `ReviewSessionScreen` (lib/apps/lms/screens/review_session_screen.dart)
- [ ] Implement flashcard UI (tap to reveal answer)
- [ ] Implement quality rating buttons
- [ ] Add progress bar and session stats
- [ ] Add session completion dialog
- [ ] Create `LearningProgressCard` widget
- [ ] Test review flow end-to-end

### Phase 5: Course Integration (Week 5-6)

**Goals**: Integrate with existing LMS

- [ ] Add `LearningProgressCard` to course detail screen
- [ ] Implement activity completion hooks
- [ ] Add "Generate concepts" dialog after activity
- [ ] Emit appropriate events to app bus
- [ ] Update LMS app to show review counts
- [ ] Add navigation to review sessions from course screen

### Phase 6: Manual Concept Management (Week 6-7)

**Goals**: Allow instructors to refine concepts

- [ ] Create `ConceptManagerScreen` for viewing/editing concepts
- [ ] Add CRUD operations for reviewable items
- [ ] Implement bulk import (CSV/JSON)
- [ ] Add UI to link concepts to activities
- [ ] Test concept editing workflow

### Phase 7: Analytics & Polish (Week 7-8)

**Goals**: Learning analytics and UX improvements

- [ ] Create learning analytics dashboard
- [ ] Add retention curve visualization
- [ ] Implement weak area identification
- [ ] Add daily review notifications (if notification system exists)
- [ ] Implement concept search/filtering
- [ ] Add export functionality (Anki format?)
- [ ] Performance optimization for large datasets
- [ ] Final testing and bug fixes

### Phase 8: Documentation (Week 8)

**Goals**: Document the system

- [ ] Write user guide for learners
- [ ] Write instructor guide for concept management
- [ ] Document API for concept extraction service
- [ ] Create example courses with concepts
- [ ] Update CLAUDE.md with new features

---

## Testing Strategy

### Unit Tests

1. **Model tests** (`test/models/reviewable_item_test.dart`)
   - JSON serialization/deserialization
   - Validation rules
   - copyWith functionality

2. **SM-2 algorithm tests** (`test/services/spaced_repetition_test.dart`)
   - Interval calculation correctness
   - Ease factor updates
   - Edge cases (first review, failures, perfect recalls)

3. **Concept extraction tests** (`test/services/concept_extraction_test.dart`)
   - JSON parsing
   - Error handling
   - Type detection

### Integration Tests

1. **Database operations** (`integration_test/database_test.dart`)
   - CRUD for reviewable items
   - Schedule updates
   - Query performance with 1000+ items

2. **Queue consumer** (`integration_test/queue_test.dart`)
   - Concept extraction triggered correctly
   - Error handling and retries
   - Idempotency

### Widget Tests

1. **Review session** (`test/screens/review_session_test.dart`)
   - Rendering different item types
   - Answer reveal interaction
   - Quality button taps
   - Navigation flow

2. **Progress card** (`test/widgets/learning_progress_card_test.dart`)
   - Stats display
   - Due/overdue highlighting
   - Button states

### E2E Tests

1. **Full learning flow** (`integration_test/learning_flow_test.dart`)
   - Complete activity → generate concepts → review session → rate quality
   - Verify schedule updates correctly
   - Verify stats update correctly

---

## Future Enhancements

### 1. Advanced Scheduling Algorithms

- **FSRS** (Free Spaced Repetition Scheduler): More accurate than SM-2
- **Adaptive difficulty**: Adjust based on individual performance
- **Optimal review time**: Consider circadian rhythms

### 2. Social Learning

- **Shared concept decks**: Import concepts from other users
- **Peer-created quizzes**: Community contributions
- **Leaderboards**: Gamification

### 3. Advanced Question Types

- **Image occlusion**: Hide parts of diagrams
- **Audio questions**: For language learning
- **Code challenges**: For programming courses

### 4. Mobile Notifications

- **Daily review reminders**: "You have 15 reviews due"
- **Streak reminders**: "Don't break your 30-day streak!"
- **Achievement unlocks**: Gamification badges

### 5. Analytics Dashboard

- **Retention curves**: Visualize forgetting curve
- **Heatmap calendar**: Review activity over time
- **Weak area identification**: Topics needing more practice
- **Predicted mastery dates**: When will you master this course?

### 6. Export/Import

- **Anki export**: Convert to Anki deck format
- **CSV export**: For analysis in spreadsheets
- **Shared deck format**: Standard format for sharing

---

## References

### Academic Papers

1. Karpicke, J. D., & Roediger, H. L. (2008). **The critical importance of retrieval for learning**. Science, 319(5865), 966-968.

2. Cepeda, N. J., et al. (2006). **Distributed practice in verbal recall tasks: A review and quantitative synthesis**. Psychological Bulletin, 132(3), 354.

3. Rohrer, D., & Taylor, K. (2007). **The shuffling of mathematics problems improves learning**. Instructional Science, 35(6), 481-498.

4. Dunlosky, J., et al. (2013). **Improving students' learning with effective learning techniques**. Psychological Science in the Public Interest, 14(1), 4-58.

5. Wozniak, P. A., & Gorzelanczyk, E. J. (1994). **Optimization of repetition spacing in the practice of learning**. Acta Neurobiologiae Experimentalis, 54, 59-62. [SM-2 Algorithm]

### Existing Systems

- **Anki**: Open-source SRS with proven effectiveness
- **SuperMemo**: Original SRS implementation (SM-2, SM-15+)
- **Quizlet**: Popular flashcard system with spaced repetition
- **RemNote**: Note-taking + SRS integration

---

## Conclusion

This system implements **evidence-based learning** across all Bloom's taxonomy levels:

1. **Remember**: Flashcards with SM-2 scheduling
2. **Understand**: Comprehension quizzes with explanations
3. **Apply**: Practice problems with spaced repetition
4. **Analyze**: Comparison questions, interleaved practice
5. **Evaluate**: Self-assessment, critique tasks
6. **Create**: Projects, synthesis activities

**Key Success Factors**:
- ✅ Automated concept extraction (reduces manual work)
- ✅ Proven SM-2 algorithm (40+ years of research)
- ✅ Seamless integration with existing LMS
- ✅ Queue-based processing (scalable, reliable)
- ✅ Comprehensive analytics (enables metacognition)

The system transforms passive content consumption into active learning with measurable retention improvements.
