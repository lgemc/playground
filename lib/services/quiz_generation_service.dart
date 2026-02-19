import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../core/database/crdt_database.dart';
import '../apps/lms/shared/models/reviewable_item.dart';
import '../apps/lms/shared/models/quiz.dart';
import '../services/autocompletion_service.dart';

/// Service for generating quizzes from reviewable items using LLM
class QuizGenerationService {
  static final QuizGenerationService instance = QuizGenerationService._();
  QuizGenerationService._();

  final AutocompletionService _autocompletion = AutocompletionService.instance;

  /// Generate a quiz from reviewable items
  ///
  /// [courseId] - Course ID for the quiz
  /// [reviewableItems] - List of concepts to use for the quiz
  /// [difficulty] - Difficulty level (beginner, intermediate, advanced, expert)
  /// [questionCount] - Number of questions in the quiz (default: 10)
  /// [title] - Optional custom title for the quiz
  /// [description] - Optional description for the quiz
  /// [moduleId] - Optional module ID
  /// [subSectionId] - Optional subsection ID
  /// [activityId] - Optional activity ID
  Future<Quiz> generateQuiz({
    required String courseId,
    required List<ReviewableItem> reviewableItems,
    required QuizDifficulty difficulty,
    int questionCount = 10,
    String? title,
    String? description,
    String? moduleId,
    String? subSectionId,
    String? activityId,
    int? timeLimit,
    bool shuffleQuestions = true,
    bool shuffleAnswers = true,
    int passingScore = 70,
  }) async {
    if (reviewableItems.isEmpty) {
      throw Exception('Cannot generate quiz: no reviewable items provided');
    }

    // Select questions based on difficulty level
    final selectedItems = _selectQuestionsByDifficulty(
      reviewableItems,
      difficulty,
      questionCount,
    );

    // Generate title if not provided
    final quizTitle = title ?? await _generateQuizTitle(
      selectedItems,
      difficulty,
    );

    // Create the quiz
    final quiz = Quiz.create(
      courseId: courseId,
      moduleId: moduleId,
      subSectionId: subSectionId,
      activityId: activityId,
      title: quizTitle,
      description: description,
      difficulty: difficulty,
      questionCount: selectedItems.length,
      timeLimit: timeLimit,
      shuffleQuestions: shuffleQuestions,
      shuffleAnswers: shuffleAnswers,
      passingScore: passingScore,
    );

    // Save quiz to database
    final quizRow = quiz.toDbRow();
    await CrdtDatabase.instance.execute('''
      INSERT INTO quizzes (id, course_id, module_id, subsection_id, activity_id,
                           title, description, difficulty, question_count, time_limit,
                           shuffle_questions, shuffle_answers, passing_score, metadata,
                           created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      quizRow['id'], quizRow['course_id'], quizRow['module_id'], quizRow['subsection_id'],
      quizRow['activity_id'], quizRow['title'], quizRow['description'], quizRow['difficulty'],
      quizRow['question_count'], quizRow['time_limit'], quizRow['shuffle_questions'],
      quizRow['shuffle_answers'], quizRow['passing_score'], quizRow['metadata'],
      quizRow['created_at'], quizRow['updated_at'],
    ]);

    // Create quiz questions (links between quiz and reviewable items)
    for (int i = 0; i < selectedItems.length; i++) {
      final quizQuestion = QuizQuestion.create(
        quizId: quiz.id,
        reviewableItemId: selectedItems[i].id,
        orderIndex: i,
        points: _calculatePoints(selectedItems[i].type, difficulty),
      );
      final qqRow = quizQuestion.toDbRow();
      await CrdtDatabase.instance.execute('''
        INSERT INTO quiz_questions (id, quiz_id, reviewable_item_id, order_index, points, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
      ''', [qqRow['id'], qqRow['quiz_id'], qqRow['reviewable_item_id'],
            qqRow['order_index'], qqRow['points'], qqRow['created_at']]);
    }

    return quiz;
  }

  /// Generate additional question variations using LLM
  ///
  /// This method takes existing concepts and generates new variations
  /// with different question types and difficulty levels
  Future<List<ReviewableItem>> generateQuestionVariations({
    required String courseId,
    required String activityId,
    required List<ReviewableItem> existingItems,
    required QuizDifficulty difficulty,
    int count = 5,
    String? moduleId,
    String? subSectionId,
  }) async {
    if (existingItems.isEmpty) {
      throw Exception('Cannot generate variations: no existing items provided');
    }

    // Prepare context for LLM
    final context = existingItems.map((item) {
      return {
        'type': item.type.name,
        'content': item.content,
        'answer': item.answer,
      };
    }).toList();

    final systemPrompt = '''You are a quiz generation expert. Generate $count new quiz questions based on the provided concepts.

Requirements:
1. Generate questions at ${difficulty.name} difficulty level
2. Use variety of question types: multiple choice, fill-in-blank, true/false, short answer
3. For ${difficulty.name} level:
   ${_getDifficultyGuidelines(difficulty)}
4. Output ONLY valid JSON, no other text

Output format:
{
  "questions": [
    {
      "type": "multipleChoice|fillInBlank|trueFalse|shortAnswer",
      "content": "question text",
      "answer": "correct answer",
      "distractors": ["wrong answer 1", "wrong answer 2", "wrong answer 3"],
      "explanation": "why this is the answer"
    }
  ]
}

Notes:
- For fill-in-blank: use _____ for blanks (1-2 words)
- For multiple choice: provide 3-4 distractors
- For true/false: content should be a statement, answer should be "true" or "false"
- Keep questions clear and concise
''';

    final prompt = '''
Existing concepts:
${jsonEncode(context)}

Generate $count new questions at ${difficulty.name} level.
''';

    // Use streaming to handle reasoning models
    final resultBuffer = StringBuffer();
    await for (final chunk in _autocompletion.promptStreamContentOnly(
      prompt,
      systemPrompt: systemPrompt,
      temperature: 0.7,
      maxTokens: 2000,
    )) {
      resultBuffer.write(chunk);
    }

    final response = resultBuffer.toString();
    final newItems = <ReviewableItem>[];

    try {
      // Extract JSON from response
      final jsonStr = _extractJson(response);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final questions = data['questions'] as List<dynamic>;

      for (final q in questions) {
        final questionMap = q as Map<String, dynamic>;
        final typeStr = questionMap['type'] as String;

        ReviewableType type;
        switch (typeStr) {
          case 'multipleChoice':
            type = ReviewableType.multipleChoice;
            break;
          case 'fillInBlank':
            type = ReviewableType.fillInBlank;
            break;
          case 'trueFalse':
            type = ReviewableType.trueFalse;
            break;
          case 'shortAnswer':
            type = ReviewableType.shortAnswer;
            break;
          default:
            type = ReviewableType.multipleChoice;
        }

        final item = ReviewableItem.create(
          activityId: activityId,
          courseId: courseId,
          moduleId: moduleId,
          subSectionId: subSectionId,
          type: type,
          content: questionMap['content'] as String,
          answer: questionMap['answer'] as String,
          distractors: (questionMap['distractors'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ?? [],
          metadata: {
            'difficulty': difficulty.name,
            'explanation': questionMap['explanation'] ?? '',
            'generated': true,
          },
        );

        newItems.add(item);
      }

      // Save to database
      for (final item in newItems) {
        final row = item.toDbRow();
        await CrdtDatabase.instance.execute('''
          INSERT INTO reviewable_items (id, activity_id, course_id, module_id, subsection_id,
                                       type, content, answer, distractors, metadata,
                                       created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', [row['id'], row['activity_id'], row['course_id'], row['module_id'],
              row['subsection_id'], row['type'], row['content'], row['answer'],
              row['distractors'], row['metadata'], row['created_at'], row['updated_at']]);
      }
    } catch (e) {
      print('Error parsing LLM response for quiz variations: $e');
      print('Response was: $response');
      throw Exception('Failed to generate question variations: $e');
    }

    return newItems;
  }

  /// Select questions based on difficulty level
  List<ReviewableItem> _selectQuestionsByDifficulty(
    List<ReviewableItem> items,
    QuizDifficulty difficulty,
    int count,
  ) {
    // Shuffle for randomness
    final shuffled = List<ReviewableItem>.from(items)..shuffle(Random());

    // For different difficulty levels, prefer different question types
    final selected = <ReviewableItem>[];

    switch (difficulty) {
      case QuizDifficulty.beginner:
        // Prefer flashcards, true/false, simple multiple choice
        selected.addAll(_filterByTypes(shuffled, [
          ReviewableType.flashcard,
          ReviewableType.trueFalse,
          ReviewableType.multipleChoice,
        ]));
        break;

      case QuizDifficulty.intermediate:
        // Mix of question types, avoid flashcards
        selected.addAll(_filterByTypes(shuffled, [
          ReviewableType.multipleChoice,
          ReviewableType.fillInBlank,
          ReviewableType.shortAnswer,
        ]));
        break;

      case QuizDifficulty.advanced:
        // Prefer short answer, fill-in-blank, procedures
        selected.addAll(_filterByTypes(shuffled, [
          ReviewableType.shortAnswer,
          ReviewableType.fillInBlank,
          ReviewableType.procedure,
          ReviewableType.multipleChoice,
        ]));
        break;

      case QuizDifficulty.expert:
        // Most challenging: procedures, summaries, complex questions
        selected.addAll(_filterByTypes(shuffled, [
          ReviewableType.procedure,
          ReviewableType.summary,
          ReviewableType.shortAnswer,
        ]));
        break;
    }

    // If we don't have enough, add more from shuffled list
    if (selected.length < count) {
      for (final item in shuffled) {
        if (!selected.contains(item) && selected.length < count) {
          selected.add(item);
        }
      }
    }

    // Return up to count items
    return selected.take(count).toList();
  }

  /// Filter items by preferred types
  List<ReviewableItem> _filterByTypes(
    List<ReviewableItem> items,
    List<ReviewableType> preferredTypes,
  ) {
    final filtered = <ReviewableItem>[];

    // First, add items of preferred types
    for (final type in preferredTypes) {
      filtered.addAll(items.where((item) => item.type == type));
    }

    return filtered;
  }

  /// Calculate points for a question based on type and difficulty
  int _calculatePoints(ReviewableType type, QuizDifficulty difficulty) {
    int basePoints = 1;

    // Base points by type
    switch (type) {
      case ReviewableType.flashcard:
      case ReviewableType.trueFalse:
        basePoints = 1;
        break;
      case ReviewableType.multipleChoice:
        basePoints = 2;
        break;
      case ReviewableType.fillInBlank:
      case ReviewableType.shortAnswer:
        basePoints = 3;
        break;
      case ReviewableType.procedure:
      case ReviewableType.summary:
        basePoints = 5;
        break;
    }

    // Multiply by difficulty
    switch (difficulty) {
      case QuizDifficulty.beginner:
        return basePoints;
      case QuizDifficulty.intermediate:
        return (basePoints * 1.5).round();
      case QuizDifficulty.advanced:
        return basePoints * 2;
      case QuizDifficulty.expert:
        return (basePoints * 2.5).round();
    }
  }

  /// Generate quiz title using LLM
  Future<String> _generateQuizTitle(
    List<ReviewableItem> items,
    QuizDifficulty difficulty,
  ) async {
    final topics = items.map((item) => item.content).take(3).join('; ');

    final systemPrompt = '''Generate a short, engaging quiz title (max 50 characters).
The title should reflect the topic and difficulty level.

Output ONLY the title, nothing else. No explanation, no reasoning, no other text.''';

    final prompt = '''
Topics: $topics
Difficulty: ${difficulty.name}

Generate a quiz title.''';

    // Use streaming to handle reasoning models
    final resultBuffer = StringBuffer();
    await for (final chunk in _autocompletion.promptStreamContentOnly(
      prompt,
      systemPrompt: systemPrompt,
      temperature: 0.7,
      maxTokens: 100,
    )) {
      resultBuffer.write(chunk);
    }

    final response = resultBuffer.toString();

    // Extract title from response (work backwards from end)
    final lines = response.trim().split('\n');
    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      // Skip reasoning artifacts
      if (line.isEmpty || line.endsWith('?') || line.contains('let\'s') || line.length < 3) {
        continue;
      }
      // Remove quotes if present
      var title = line;
      if ((title.startsWith('"') && title.endsWith('"')) ||
          (title.startsWith("'") && title.endsWith("'"))) {
        title = title.substring(1, title.length - 1);
      }
      if (title.length <= 50) {
        return title;
      }
    }

    // Fallback
    return '${difficulty.name.substring(0, 1).toUpperCase()}${difficulty.name.substring(1)} Quiz';
  }

  /// Get difficulty-specific guidelines for LLM
  String _getDifficultyGuidelines(QuizDifficulty difficulty) {
    switch (difficulty) {
      case QuizDifficulty.beginner:
        return '''- Use simple, direct language
   - Focus on basic recall and recognition
   - Provide clear, obvious distractors for multiple choice
   - Questions should be straightforward''';

      case QuizDifficulty.intermediate:
        return '''- Use standard terminology
   - Test understanding and application
   - Distractors should be plausible but clearly wrong
   - Require some reasoning''';

      case QuizDifficulty.advanced:
        return '''- Use technical language
   - Test analysis and synthesis
   - Distractors should be subtle and require careful thought
   - Require deeper understanding''';

      case QuizDifficulty.expert:
        return '''- Use advanced technical language
   - Test evaluation and creation
   - Distractors should be very subtle
   - Require expert-level understanding and critical thinking''';
    }
  }

  /// Extract JSON from LLM response (handle markdown code blocks)
  String _extractJson(String response) {
    // Try to find JSON in code block
    final codeBlockMatch = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```', multiLine: true)
        .firstMatch(response);
    if (codeBlockMatch != null) {
      return codeBlockMatch.group(1)!;
    }

    // Try to find raw JSON
    final jsonMatch = RegExp(r'\{[\s\S]*\}', multiLine: true).firstMatch(response);
    if (jsonMatch != null) {
      return jsonMatch.group(0)!;
    }

    // Return as-is and let JSON parser fail with proper error
    return response;
  }

  /// Get quiz by ID
  Future<Quiz?> getQuiz(String quizId) async {
    final results = await CrdtDatabase.instance.query(
      'SELECT * FROM quizzes WHERE id = ?',
      [quizId],
    );

    if (results.isEmpty) return null;
    return Quiz.fromDbRow(results.first);
  }

  /// Get all quizzes for a course
  Future<List<Quiz>> getQuizzesForCourse(String courseId) async {
    final results = await CrdtDatabase.instance.query(
      'SELECT * FROM quizzes WHERE course_id = ? ORDER BY created_at DESC',
      [courseId],
    );

    return results.map((row) => Quiz.fromDbRow(row)).toList();
  }

  /// Get questions for a quiz with their reviewable items
  Future<List<Map<String, dynamic>>> getQuizQuestionsWithItems(String quizId) async {
    final results = await CrdtDatabase.instance.query('''
      SELECT qq.*, ri.*
      FROM quiz_questions qq
      JOIN reviewable_items ri ON qq.reviewable_item_id = ri.id
      WHERE qq.quiz_id = ?
      ORDER BY qq.order_index ASC
    ''', [quizId]);

    return results.map((row) {
      final quizQuestion = QuizQuestion.fromDbRow({
        'id': row['id'],
        'quiz_id': row['quiz_id'],
        'reviewable_item_id': row['reviewable_item_id'],
        'order_index': row['order_index'],
        'points': row['points'],
        'created_at': row['created_at'],
      });

      final reviewableItem = ReviewableItem.fromDbRow({
        'id': row['reviewable_item_id'],
        'activity_id': row['activity_id'],
        'course_id': row['course_id'],
        'module_id': row['module_id'],
        'subsection_id': row['subsection_id'],
        'type': row['type'],
        'content': row['content'],
        'answer': row['answer'],
        'distractors': row['distractors'],
        'metadata': row['metadata'],
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
      });

      return {
        'quizQuestion': quizQuestion,
        'reviewableItem': reviewableItem,
      };
    }).toList();
  }

  /// Delete a quiz and all associated data
  Future<void> deleteQuiz(String quizId) async {
    // Foreign keys will cascade delete quiz_questions, quiz_attempts, and quiz_answers
    await CrdtDatabase.instance.execute('DELETE FROM quizzes WHERE id = ?', [quizId]);
  }
}
