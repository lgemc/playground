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
            maxTokens: 4000,
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
            maxTokens: 4000,
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

  /// Parse LLM JSON response to ReviewableItem list.
  /// If the response is truncated (e.g. due to token limit), salvages all
  /// complete items that appeared before the cut-off.
  List<ReviewableItem> _parseJsonToReviewableItems(
    String jsonResponse, {
    required String activityId,
    required String courseId,
    String? moduleId,
    String? subSectionId,
  }) {
    // Clean JSON (remove markdown code blocks if present)
    var cleanJson = jsonResponse
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*$'), '')
        .trim();

    // Try parsing as-is first
    List<dynamic>? jsonList = _tryDecodeJsonArray(cleanJson);

    // If that failed, the response is likely truncated — repair it by
    // finding the last complete object and closing the array.
    if (jsonList == null) {
      print('JSON parsing failed on raw response, attempting truncation repair...');
      cleanJson = _repairTruncatedJsonArray(cleanJson);
      jsonList = _tryDecodeJsonArray(cleanJson);
    }

    if (jsonList == null) {
      print('JSON parsing failed even after repair.');
      print('Response was: $jsonResponse');
      return [];
    }

    final items = <ReviewableItem>[];
    for (final item in jsonList) {
      try {
        final type = _parseReviewableType(item['type'] as String);
        items.add(ReviewableItem.create(
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
        ));
      } catch (e) {
        print('Skipping malformed concept item: $e');
      }
    }
    return items;
  }

  /// Attempt to decode a JSON array; returns null on failure.
  List<dynamic>? _tryDecodeJsonArray(String text) {
    try {
      final decoded = json.decode(text);
      if (decoded is List) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Repair a truncated JSON array by finding the last complete `}` that
  /// closes a top-level object, then closing the array after it.
  String _repairTruncatedJsonArray(String text) {
    // Find the start of the array
    final arrayStart = text.indexOf('[');
    if (arrayStart < 0) return '[]';

    // Walk backwards from the end to find the last `}` that closes a
    // top-level object in the array (depth == 1 inside the array).
    int depth = 0;
    int lastCompleteObjectEnd = -1;

    for (int i = arrayStart; i < text.length; i++) {
      final ch = text[i];
      if (ch == '{' || ch == '[') {
        depth++;
      } else if (ch == '}' || ch == ']') {
        depth--;
        // A closing `}` at depth 1 means we just closed a top-level object
        if (ch == '}' && depth == 1) {
          lastCompleteObjectEnd = i;
        }
      }
    }

    if (lastCompleteObjectEnd < 0) return '[]';

    // Everything up to and including the last complete object, then close array
    return '${text.substring(arrayStart, lastCompleteObjectEnd + 1)}]';
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
