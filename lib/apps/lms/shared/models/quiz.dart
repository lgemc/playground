import 'package:uuid/uuid.dart';
import 'dart:convert';

/// Difficulty level for quizzes
enum QuizDifficulty {
  beginner, // Easy questions, more guidance
  intermediate, // Medium difficulty
  advanced, // Harder questions, less guidance
  expert, // Most challenging, minimal guidance
}

/// A quiz composed of multiple questions from reviewable items
class Quiz {
  final String id;
  final String courseId;
  final String? moduleId;
  final String? subSectionId;
  final String? activityId; // Optional: quiz for specific activity
  final String title;
  final String? description;
  final QuizDifficulty difficulty;
  final int questionCount; // Number of questions in this quiz
  final int? timeLimit; // Time limit in seconds (null = no limit)
  final bool shuffleQuestions; // Randomize question order
  final bool shuffleAnswers; // Randomize answer options
  final int passingScore; // Minimum score to pass (0-100)
  final Map<String, dynamic> metadata; // Extra settings
  final DateTime createdAt;
  final DateTime updatedAt;

  Quiz({
    required this.id,
    required this.courseId,
    this.moduleId,
    this.subSectionId,
    this.activityId,
    required this.title,
    this.description,
    required this.difficulty,
    required this.questionCount,
    this.timeLimit,
    this.shuffleQuestions = true,
    this.shuffleAnswers = true,
    this.passingScore = 70,
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory Quiz.create({
    required String courseId,
    String? moduleId,
    String? subSectionId,
    String? activityId,
    required String title,
    String? description,
    required QuizDifficulty difficulty,
    required int questionCount,
    int? timeLimit,
    bool shuffleQuestions = true,
    bool shuffleAnswers = true,
    int passingScore = 70,
    Map<String, dynamic>? metadata,
  }) {
    final now = DateTime.now();
    return Quiz(
      id: const Uuid().v4(),
      courseId: courseId,
      moduleId: moduleId,
      subSectionId: subSectionId,
      activityId: activityId,
      title: title,
      description: description,
      difficulty: difficulty,
      questionCount: questionCount,
      timeLimit: timeLimit,
      shuffleQuestions: shuffleQuestions,
      shuffleAnswers: shuffleAnswers,
      passingScore: passingScore,
      metadata: metadata ?? {},
      createdAt: now,
      updatedAt: now,
    );
  }

  Map<String, dynamic> toDbRow() {
    return {
      'id': id,
      'course_id': courseId,
      'module_id': moduleId,
      'subsection_id': subSectionId,
      'activity_id': activityId,
      'title': title,
      'description': description,
      'difficulty': difficulty.name,
      'question_count': questionCount,
      'time_limit': timeLimit,
      'shuffle_questions': shuffleQuestions ? 1 : 0,
      'shuffle_answers': shuffleAnswers ? 1 : 0,
      'passing_score': passingScore,
      'metadata': jsonEncode(metadata),
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Quiz.fromDbRow(Map<String, Object?> row) {
    return Quiz(
      id: row['id'] as String,
      courseId: row['course_id'] as String,
      moduleId: row['module_id'] as String?,
      subSectionId: row['subsection_id'] as String?,
      activityId: row['activity_id'] as String?,
      title: row['title'] as String,
      description: row['description'] as String?,
      difficulty: QuizDifficulty.values.firstWhere(
        (d) => d.name == row['difficulty'],
        orElse: () => QuizDifficulty.intermediate,
      ),
      questionCount: row['question_count'] as int,
      timeLimit: row['time_limit'] as int?,
      shuffleQuestions: (row['shuffle_questions'] as int) == 1,
      shuffleAnswers: (row['shuffle_answers'] as int) == 1,
      passingScore: row['passing_score'] as int,
      metadata: row['metadata'] != null
          ? jsonDecode(row['metadata'] as String) as Map<String, dynamic>
          : {},
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  Quiz copyWith({
    String? id,
    String? courseId,
    String? moduleId,
    String? subSectionId,
    String? activityId,
    String? title,
    String? description,
    QuizDifficulty? difficulty,
    int? questionCount,
    int? timeLimit,
    bool? shuffleQuestions,
    bool? shuffleAnswers,
    int? passingScore,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Quiz(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      moduleId: moduleId ?? this.moduleId,
      subSectionId: subSectionId ?? this.subSectionId,
      activityId: activityId ?? this.activityId,
      title: title ?? this.title,
      description: description ?? this.description,
      difficulty: difficulty ?? this.difficulty,
      questionCount: questionCount ?? this.questionCount,
      timeLimit: timeLimit ?? this.timeLimit,
      shuffleQuestions: shuffleQuestions ?? this.shuffleQuestions,
      shuffleAnswers: shuffleAnswers ?? this.shuffleAnswers,
      passingScore: passingScore ?? this.passingScore,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Links a quiz to a specific reviewable item (question)
class QuizQuestion {
  final String id;
  final String quizId;
  final String reviewableItemId;
  final int orderIndex; // Position in quiz (0-based)
  final int points; // Points awarded for correct answer
  final DateTime createdAt;

  QuizQuestion({
    required this.id,
    required this.quizId,
    required this.reviewableItemId,
    required this.orderIndex,
    this.points = 1,
    required this.createdAt,
  });

  factory QuizQuestion.create({
    required String quizId,
    required String reviewableItemId,
    required int orderIndex,
    int points = 1,
  }) {
    return QuizQuestion(
      id: const Uuid().v4(),
      quizId: quizId,
      reviewableItemId: reviewableItemId,
      orderIndex: orderIndex,
      points: points,
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toDbRow() {
    return {
      'id': id,
      'quiz_id': quizId,
      'reviewable_item_id': reviewableItemId,
      'order_index': orderIndex,
      'points': points,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory QuizQuestion.fromDbRow(Map<String, Object?> row) {
    return QuizQuestion(
      id: row['id'] as String,
      quizId: row['quiz_id'] as String,
      reviewableItemId: row['reviewable_item_id'] as String,
      orderIndex: row['order_index'] as int,
      points: row['points'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }
}

/// User's attempt at a quiz
class QuizAttempt {
  final String id;
  final String quizId;
  final String userId; // Future: link to user profile
  final DateTime startedAt;
  final DateTime? completedAt;
  final int score; // 0-100 percentage
  final int totalPoints; // Points earned
  final int maxPoints; // Maximum possible points
  final bool passed; // Whether user passed based on passing score
  final Map<String, dynamic> metadata; // Extra data (time taken, etc.)

  QuizAttempt({
    required this.id,
    required this.quizId,
    required this.userId,
    required this.startedAt,
    this.completedAt,
    this.score = 0,
    this.totalPoints = 0,
    required this.maxPoints,
    this.passed = false,
    this.metadata = const {},
  });

  factory QuizAttempt.create({
    required String quizId,
    required String userId,
    required int maxPoints,
  }) {
    return QuizAttempt(
      id: const Uuid().v4(),
      quizId: quizId,
      userId: userId,
      startedAt: DateTime.now(),
      maxPoints: maxPoints,
    );
  }

  Map<String, dynamic> toDbRow() {
    return {
      'id': id,
      'quiz_id': quizId,
      'user_id': userId,
      'started_at': startedAt.millisecondsSinceEpoch,
      'completed_at': completedAt?.millisecondsSinceEpoch,
      'score': score,
      'total_points': totalPoints,
      'max_points': maxPoints,
      'passed': passed ? 1 : 0,
      'metadata': jsonEncode(metadata),
    };
  }

  factory QuizAttempt.fromDbRow(Map<String, Object?> row) {
    return QuizAttempt(
      id: row['id'] as String,
      quizId: row['quiz_id'] as String,
      userId: row['user_id'] as String,
      startedAt: DateTime.fromMillisecondsSinceEpoch(row['started_at'] as int),
      completedAt: row['completed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['completed_at'] as int)
          : null,
      score: row['score'] as int,
      totalPoints: row['total_points'] as int,
      maxPoints: row['max_points'] as int,
      passed: (row['passed'] as int) == 1,
      metadata: row['metadata'] != null
          ? jsonDecode(row['metadata'] as String) as Map<String, dynamic>
          : {},
    );
  }

  QuizAttempt copyWith({
    String? id,
    String? quizId,
    String? userId,
    DateTime? startedAt,
    DateTime? completedAt,
    int? score,
    int? totalPoints,
    int? maxPoints,
    bool? passed,
    Map<String, dynamic>? metadata,
  }) {
    return QuizAttempt(
      id: id ?? this.id,
      quizId: quizId ?? this.quizId,
      userId: userId ?? this.userId,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      score: score ?? this.score,
      totalPoints: totalPoints ?? this.totalPoints,
      maxPoints: maxPoints ?? this.maxPoints,
      passed: passed ?? this.passed,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// User's answer to a specific question in a quiz attempt
class QuizAnswer {
  final String id;
  final String attemptId;
  final String quizQuestionId;
  final String userAnswer; // User's submitted answer
  final bool isCorrect;
  final int pointsEarned;
  final DateTime answeredAt;
  final Map<String, dynamic> metadata; // Extra data (time taken, hints used, etc.)

  QuizAnswer({
    required this.id,
    required this.attemptId,
    required this.quizQuestionId,
    required this.userAnswer,
    required this.isCorrect,
    this.pointsEarned = 0,
    required this.answeredAt,
    this.metadata = const {},
  });

  factory QuizAnswer.create({
    required String attemptId,
    required String quizQuestionId,
    required String userAnswer,
    required bool isCorrect,
    int pointsEarned = 0,
    Map<String, dynamic>? metadata,
  }) {
    return QuizAnswer(
      id: const Uuid().v4(),
      attemptId: attemptId,
      quizQuestionId: quizQuestionId,
      userAnswer: userAnswer,
      isCorrect: isCorrect,
      pointsEarned: pointsEarned,
      answeredAt: DateTime.now(),
      metadata: metadata ?? {},
    );
  }

  Map<String, dynamic> toDbRow() {
    return {
      'id': id,
      'attempt_id': attemptId,
      'quiz_question_id': quizQuestionId,
      'user_answer': userAnswer,
      'is_correct': isCorrect ? 1 : 0,
      'points_earned': pointsEarned,
      'answered_at': answeredAt.millisecondsSinceEpoch,
      'metadata': jsonEncode(metadata),
    };
  }

  factory QuizAnswer.fromDbRow(Map<String, Object?> row) {
    return QuizAnswer(
      id: row['id'] as String,
      attemptId: row['attempt_id'] as String,
      quizQuestionId: row['quiz_question_id'] as String,
      userAnswer: row['user_answer'] as String,
      isCorrect: (row['is_correct'] as int) == 1,
      pointsEarned: row['points_earned'] as int,
      answeredAt: DateTime.fromMillisecondsSinceEpoch(row['answered_at'] as int),
      metadata: row['metadata'] != null
          ? jsonDecode(row['metadata'] as String) as Map<String, dynamic>
          : {},
    );
  }
}
