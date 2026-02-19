import 'dart:convert';
import '../core/database/crdt_database.dart';
import '../apps/lms/shared/models/reviewable_item.dart';
import '../apps/lms/shared/models/quiz.dart';

/// Service for managing quiz attempts, scoring, and answer validation
class QuizService {
  static final QuizService instance = QuizService._();
  QuizService._();

  /// Start a new quiz attempt
  Future<QuizAttempt> startAttempt({
    required String quizId,
    required String userId,
  }) async {
    // Get quiz to calculate max points
    final quizResult = await CrdtDatabase.instance.query(
      'SELECT * FROM quizzes WHERE id = ?',
      [quizId],
    );

    if (quizResult.isEmpty) {
      throw Exception('Quiz not found: $quizId');
    }

    // Get quiz questions to calculate max points
    final questionsResult = await CrdtDatabase.instance.query(
      'SELECT * FROM quiz_questions WHERE quiz_id = ?',
      [quizId],
    );

    final maxPoints = questionsResult.fold<int>(
      0,
      (sum, row) => sum + (row['points'] as int),
    );

    final attempt = QuizAttempt.create(
      quizId: quizId,
      userId: userId,
      maxPoints: maxPoints,
    );

    final row = attempt.toDbRow();
    await CrdtDatabase.instance.execute('''
      INSERT INTO quiz_attempts (id, quiz_id, user_id, started_at, completed_at,
                                 score, total_points, max_points, passed, metadata)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [row['id'], row['quiz_id'], row['user_id'], row['started_at'],
          row['completed_at'], row['score'], row['total_points'], row['max_points'],
          row['passed'], row['metadata']]);
    return attempt;
  }

  /// Submit an answer to a question
  Future<QuizAnswer> submitAnswer({
    required String attemptId,
    required String quizQuestionId,
    required String userAnswer,
    required ReviewableItem reviewableItem,
    required int questionPoints,
  }) async {
    // Validate answer
    final isCorrect = _validateAnswer(userAnswer, reviewableItem);
    final pointsEarned = isCorrect ? questionPoints : 0;

    final answer = QuizAnswer.create(
      attemptId: attemptId,
      quizQuestionId: quizQuestionId,
      userAnswer: userAnswer,
      isCorrect: isCorrect,
      pointsEarned: pointsEarned,
    );

    final row = answer.toDbRow();
    await CrdtDatabase.instance.execute('''
      INSERT INTO quiz_answers (id, attempt_id, quiz_question_id, user_answer,
                                is_correct, points_earned, answered_at, metadata)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''', [row['id'], row['attempt_id'], row['quiz_question_id'], row['user_answer'],
          row['is_correct'], row['points_earned'], row['answered_at'], row['metadata']]);

    return answer;
  }

  /// Complete a quiz attempt and calculate final score
  Future<QuizAttempt> completeAttempt(String attemptId) async {
    // Get the attempt
    final attemptResult = await CrdtDatabase.instance.query(
      'SELECT * FROM quiz_attempts WHERE id = ?',
      [attemptId],
    );

    if (attemptResult.isEmpty) {
      throw Exception('Attempt not found: $attemptId');
    }

    final attempt = QuizAttempt.fromDbRow(attemptResult.first);

    // Get all answers for this attempt
    final answersResult = await CrdtDatabase.instance.query(
      'SELECT * FROM quiz_answers WHERE attempt_id = ?',
      [attemptId],
    );

    final answers = answersResult.map((row) => QuizAnswer.fromDbRow(row)).toList();

    // Calculate total points
    final totalPoints = answers.fold<int>(
      0,
      (sum, answer) => sum + answer.pointsEarned,
    );

    // Calculate percentage score
    final score = attempt.maxPoints > 0
        ? ((totalPoints / attempt.maxPoints) * 100).round()
        : 0;

    // Get quiz to check passing score
    final quizResult = await CrdtDatabase.instance.query(
      'SELECT * FROM quizzes WHERE id = ?',
      [attempt.quizId],
    );

    final quiz = Quiz.fromDbRow(quizResult.first);
    final passed = score >= quiz.passingScore;

    // Update attempt
    final updatedAttempt = attempt.copyWith(
      completedAt: DateTime.now(),
      score: score,
      totalPoints: totalPoints,
      passed: passed,
    );

    final row = updatedAttempt.toDbRow();
    await CrdtDatabase.instance.execute('''
      UPDATE quiz_attempts
      SET quiz_id = ?, user_id = ?, started_at = ?, completed_at = ?,
          score = ?, total_points = ?, max_points = ?, passed = ?, metadata = ?
      WHERE id = ?
    ''', [row['quiz_id'], row['user_id'], row['started_at'], row['completed_at'],
          row['score'], row['total_points'], row['max_points'], row['passed'],
          row['metadata'], row['id']]);

    return updatedAttempt;
  }

  /// Validate user answer against correct answer
  bool _validateAnswer(String userAnswer, ReviewableItem item) {
    final cleanUser = userAnswer.trim().toLowerCase();
    final cleanCorrect = item.answer?.trim().toLowerCase() ?? '';

    switch (item.type) {
      case ReviewableType.multipleChoice:
        // Exact match for multiple choice
        return cleanUser == cleanCorrect;

      case ReviewableType.trueFalse:
        // Match true/false (with variations)
        final userBool = _parseBool(cleanUser);
        final correctBool = _parseBool(cleanCorrect);
        return userBool != null && userBool == correctBool;

      case ReviewableType.fillInBlank:
        // More lenient matching for fill-in-blank
        // Allow minor spelling variations
        return _fuzzyMatch(cleanUser, cleanCorrect);

      case ReviewableType.shortAnswer:
        // Keyword-based matching for short answers
        return _containsKeywords(cleanUser, cleanCorrect);

      case ReviewableType.flashcard:
        // Fuzzy match for flashcards
        return _fuzzyMatch(cleanUser, cleanCorrect);

      case ReviewableType.procedure:
      case ReviewableType.summary:
        // Keyword-based for complex types
        return _containsKeywords(cleanUser, cleanCorrect);
    }
  }

  /// Parse boolean value from string
  bool? _parseBool(String value) {
    final cleaned = value.toLowerCase().trim();
    if (cleaned == 'true' || cleaned == 't' || cleaned == 'yes' || cleaned == 'y' || cleaned == '1') {
      return true;
    }
    if (cleaned == 'false' || cleaned == 'f' || cleaned == 'no' || cleaned == 'n' || cleaned == '0') {
      return false;
    }
    return null;
  }

  /// Fuzzy string matching (allows minor differences)
  bool _fuzzyMatch(String a, String b) {
    // Direct match
    if (a == b) return true;

    // Check if one contains the other
    if (a.contains(b) || b.contains(a)) return true;

    // Calculate Levenshtein distance
    final distance = _levenshteinDistance(a, b);
    final maxLength = a.length > b.length ? a.length : b.length;

    // Allow up to 20% difference
    return distance <= (maxLength * 0.2);
  }

  /// Check if answer contains key words from correct answer
  bool _containsKeywords(String userAnswer, String correctAnswer) {
    // Split into words and filter out common words
    final stopWords = {'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'is', 'are', 'was', 'were'};

    final correctWords = correctAnswer
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 2 && !stopWords.contains(word))
        .toList();

    if (correctWords.isEmpty) return false;

    // Check how many keywords are present
    int matchCount = 0;
    for (final word in correctWords) {
      if (userAnswer.contains(word)) {
        matchCount++;
      }
    }

    // Require at least 50% of keywords to match
    return matchCount >= (correctWords.length * 0.5);
  }

  /// Calculate Levenshtein distance between two strings
  int _levenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final matrix = List<List<int>>.generate(
      a.length + 1,
      (i) => List<int>.filled(b.length + 1, 0),
    );

    for (int i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }

    for (int j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1, // deletion
          matrix[i][j - 1] + 1, // insertion
          matrix[i - 1][j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return matrix[a.length][b.length];
  }

  /// Get attempt by ID
  Future<QuizAttempt?> getAttempt(String attemptId) async {
    final results = await CrdtDatabase.instance.query(
      'SELECT * FROM quiz_attempts WHERE id = ?',
      [attemptId],
    );

    if (results.isEmpty) return null;
    return QuizAttempt.fromDbRow(results.first);
  }

  /// Get all attempts for a quiz
  Future<List<QuizAttempt>> getAttemptsForQuiz(String quizId) async {
    final results = await CrdtDatabase.instance.query(
      'SELECT * FROM quiz_attempts WHERE quiz_id = ? ORDER BY started_at DESC',
      [quizId],
    );

    return results.map((row) => QuizAttempt.fromDbRow(row)).toList();
  }

  /// Get all attempts for a user
  Future<List<QuizAttempt>> getAttemptsForUser(String userId) async {
    final results = await CrdtDatabase.instance.query(
      'SELECT * FROM quiz_attempts WHERE user_id = ? ORDER BY started_at DESC',
      [userId],
    );

    return results.map((row) => QuizAttempt.fromDbRow(row)).toList();
  }

  /// Get answers for an attempt
  Future<List<QuizAnswer>> getAnswersForAttempt(String attemptId) async {
    final results = await CrdtDatabase.instance.query(
      'SELECT * FROM quiz_answers WHERE attempt_id = ? ORDER BY answered_at ASC',
      [attemptId],
    );

    return results.map((row) => QuizAnswer.fromDbRow(row)).toList();
  }

  /// Get detailed attempt results with questions and answers
  Future<Map<String, dynamic>> getAttemptDetails(String attemptId) async {
    // Get attempt
    final attemptResult = await CrdtDatabase.instance.query(
      'SELECT * FROM quiz_attempts WHERE id = ?',
      [attemptId],
    );

    if (attemptResult.isEmpty) {
      throw Exception('Attempt not found: $attemptId');
    }

    final attempt = QuizAttempt.fromDbRow(attemptResult.first);

    // Get quiz
    final quizResult = await CrdtDatabase.instance.query(
      'SELECT * FROM quizzes WHERE id = ?',
      [attempt.quizId],
    );

    final quiz = Quiz.fromDbRow(quizResult.first);

    // Get answers with questions and reviewable items
    final answersResult = await CrdtDatabase.instance.query('''
      SELECT
        qa.*,
        qq.order_index,
        qq.points,
        ri.type,
        ri.content,
        ri.answer as correct_answer,
        ri.distractors,
        ri.metadata
      FROM quiz_answers qa
      JOIN quiz_questions qq ON qa.quiz_question_id = qq.id
      JOIN reviewable_items ri ON qq.reviewable_item_id = ri.id
      WHERE qa.attempt_id = ?
      ORDER BY qq.order_index ASC
    ''', [attemptId]);

    final details = answersResult.map((row) {
      return {
        'answer': QuizAnswer.fromDbRow({
          'id': row['id'],
          'attempt_id': row['attempt_id'],
          'quiz_question_id': row['quiz_question_id'],
          'user_answer': row['user_answer'],
          'is_correct': row['is_correct'],
          'points_earned': row['points_earned'],
          'answered_at': row['answered_at'],
          'metadata': row['metadata'],
        }),
        'orderIndex': row['order_index'],
        'points': row['points'],
        'type': row['type'],
        'content': row['content'],
        'correctAnswer': row['correct_answer'],
        'distractors': row['distractors'] != null
            ? jsonDecode(row['distractors'] as String)
            : null,
      };
    }).toList();

    return {
      'attempt': attempt,
      'quiz': quiz,
      'details': details,
    };
  }

  /// Calculate quiz statistics
  Future<Map<String, dynamic>> getQuizStatistics(String quizId) async {
    final db = CrdtDatabase.instance.db;

    final attempts = await getAttemptsForQuiz(quizId);
    final completedAttempts = attempts.where((a) => a.completedAt != null).toList();

    if (completedAttempts.isEmpty) {
      return {
        'totalAttempts': 0,
        'averageScore': 0.0,
        'passRate': 0.0,
        'highestScore': 0,
        'lowestScore': 0,
      };
    }

    final scores = completedAttempts.map((a) => a.score).toList();
    final passedCount = completedAttempts.where((a) => a.passed).length;

    return {
      'totalAttempts': completedAttempts.length,
      'averageScore': scores.reduce((a, b) => a + b) / scores.length,
      'passRate': (passedCount / completedAttempts.length) * 100,
      'highestScore': scores.reduce((a, b) => a > b ? a : b),
      'lowestScore': scores.reduce((a, b) => a < b ? a : b),
    };
  }
}
