import 'dart:convert';
import 'autocompletion_service.dart';
import '../apps/lms/shared/models/reviewable_item.dart';

/// Service for extracting reviewable concepts from course content
/// Uses LLM to identify key learning points from transcripts, documents, etc.
class ConceptExtractionService {
  static ConceptExtractionService? _instance;
  static ConceptExtractionService get instance =>
      _instance ??= ConceptExtractionService._();

  ConceptExtractionService._();

  final _autocompletion = AutocompletionService.instance;

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
      final response = await _autocompletion
          .promptStreamContentOnly(
            prompt,
            temperature: 0.3, // Lower temperature for consistency
            maxTokens: 2000,
          )
          .join();

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
    final prompt = '''Extract key concepts from this educational document.

Focus on:
- Important definitions (as flashcards)
- Core principles (as questions)
- Critical facts (as flashcards)

Document:
$documentText

Output as JSON array with type, content, answer, and optional distractors.
Use the same format as:
[
  {
    "type": "flashcard",
    "content": "Term or concept",
    "answer": "Definition or explanation"
  },
  {
    "type": "multipleChoice",
    "content": "Question about a principle",
    "answer": "Correct answer",
    "distractors": ["Wrong answer 1", "Wrong answer 2", "Wrong answer 3"]
  }
]''';

    try {
      final response = await _autocompletion
          .promptStreamContentOnly(
            prompt,
            temperature: 0.3,
            maxTokens: 2000,
          )
          .join();

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
      print('Response was: $jsonResponse');
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
