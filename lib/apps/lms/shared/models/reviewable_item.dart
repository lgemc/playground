import 'package:uuid/uuid.dart';
import 'dart:convert';

/// Type of reviewable item (flashcard, quiz question, etc.)
enum ReviewableType {
  flashcard, // Term/definition pairs (front/back cards)
  multipleChoice, // Question with distractors
  trueFalse, // Boolean questions
  shortAnswer, // Open-ended questions
  fillInBlank, // Cloze deletion
  procedure, // Step-by-step sequences
  summary, // Key takeaway statements
}

/// A learnable concept extracted from course content
/// Used for spaced repetition and quizzing
class ReviewableItem {
  final String id;
  final String activityId; // Source activity
  final String courseId; // For filtering by course
  final String? moduleId; // Optional: for module-level filtering
  final String? subSectionId; // Optional: for granular filtering
  final ReviewableType type;
  final String content; // Question text or term
  final String? answer; // For flashcards or correct answer
  final List<String> distractors; // For multiple choice questions
  final Map<String, dynamic> metadata; // Extra data (hints, explanations)
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
      id: const Uuid().v4(),
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

  /// Convert to database row format
  Map<String, dynamic> toDbRow() {
    return {
      'id': id,
      'activity_id': activityId,
      'course_id': courseId,
      'module_id': moduleId,
      'subsection_id': subSectionId,
      'type': type.name,
      'content': content,
      'answer': answer,
      'distractors': jsonEncode(distractors),
      'metadata': jsonEncode(metadata),
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
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

  /// Create from database row
  factory ReviewableItem.fromDbRow(Map<String, Object?> row) {
    return ReviewableItem(
      id: row['id'] as String,
      activityId: row['activity_id'] as String,
      courseId: row['course_id'] as String,
      moduleId: row['module_id'] as String?,
      subSectionId: row['subsection_id'] as String?,
      type: ReviewableType.values.firstWhere(
        (t) => t.name == row['type'],
        orElse: () => ReviewableType.flashcard,
      ),
      content: row['content'] as String,
      answer: row['answer'] as String?,
      distractors: row['distractors'] != null
          ? (jsonDecode(row['distractors'] as String) as List<dynamic>)
              .map((e) => e as String)
              .toList()
          : [],
      metadata: row['metadata'] != null
          ? jsonDecode(row['metadata'] as String) as Map<String, dynamic>
          : {},
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
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
