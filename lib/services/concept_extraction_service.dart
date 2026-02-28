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

  /// Maximum characters for input text (approx 20k tokens)
  /// This ensures we don't exceed model context limits
  static const int _maxInputChars = 80000;

  /// Truncate text to fit within token limits
  String _truncateText(String text, {int maxChars = _maxInputChars}) {
    if (text.length <= maxChars) return text;

    // Truncate and add indicator
    print('[ConceptExtraction] Truncating input from ${text.length} to $maxChars chars');
    return '${text.substring(0, maxChars)}\n\n[... content truncated due to length ...]';
  }

  /// Extract concepts from transcript using LLM
  Future<List<ReviewableItem>> extractFromTranscript({
    required String activityId,
    required String courseId,
    required String transcript,
    String? moduleId,
    String? subSectionId,
  }) async {
    final truncatedTranscript = _truncateText(transcript);

    final prompt = '''Extract key learning concepts from this lecture transcript.

Create a DIVERSE mix of reviewable items:

1. FLASHCARDS (30%): Simple term/definition pairs for vocabulary
   - Use for key terms and basic concepts
   - Will be converted to quiz questions later

2. MULTIPLE CHOICE (30%): Questions with 3-4 wrong answers
   - Test understanding of principles
   - Distractors must be plausible

3. TRUE/FALSE (20%): Statements that are true or false
   - Answer must be exactly "true" or "false"
   - Make statements clear and unambiguous

4. FILL IN BLANK (10%): Sentences with missing words
   - Use _____ for the blank (1-2 words only)
   - Answer should be the word(s) that fill the blank

5. SHORT ANSWER (10%): Open-ended questions
   - For concepts requiring brief explanations
   - Answer should be 1-3 sentences

IMPORTANT: Generate variety! Don't just create flashcards and multiple choice.

Transcript:
$truncatedTranscript

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
  },
  {
    "type": "trueFalse",
    "content": "setState() can only be called inside StatefulWidget classes",
    "answer": "true"
  },
  {
    "type": "fillInBlank",
    "content": "The _____ method is called when a StatefulWidget's state changes",
    "answer": "build"
  },
  {
    "type": "shortAnswer",
    "content": "Explain the lifecycle of a StatefulWidget",
    "answer": "A StatefulWidget goes through initState, build, and dispose phases during its lifecycle"
  }
]''';

    try {
      final response = await _autocompletion
          .promptStreamContentOnlyHigh(
            prompt,
            temperature: 0.3, // Lower temperature for consistency
            maxTokens: 8000, // Allow more space for comprehensive extraction
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
    final truncatedDocument = _truncateText(documentText);

    final prompt = '''Extract key concepts from this educational document.

Create a DIVERSE mix of reviewable items:

1. FLASHCARDS (30%): Simple term/definition pairs
2. MULTIPLE CHOICE (30%): Questions with 3-4 distractors
3. TRUE/FALSE (20%): Clear true/false statements (answer: "true" or "false")
4. FILL IN BLANK (10%): Sentences with _____ for missing words
5. SHORT ANSWER (10%): Brief explanation questions

IMPORTANT: Generate variety! Include all question types, not just flashcards and multiple choice.

Document:
$truncatedDocument

Output as JSON array:
[
  {
    "type": "flashcard",
    "content": "What is X?",
    "answer": "Definition of X"
  },
  {
    "type": "multipleChoice",
    "content": "Question?",
    "answer": "Correct answer",
    "distractors": ["Wrong 1", "Wrong 2", "Wrong 3"]
  },
  {
    "type": "trueFalse",
    "content": "Statement about concept",
    "answer": "true"
  },
  {
    "type": "fillInBlank",
    "content": "Sentence with _____ missing",
    "answer": "word"
  },
  {
    "type": "shortAnswer",
    "content": "Explain concept X",
    "answer": "Brief explanation"
  }
]''';

    try {
      final response = await _autocompletion
          .promptStreamContentOnlyHigh(
            prompt,
            temperature: 0.3,
            maxTokens: 8000, // Allow more space for comprehensive extraction
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
      default:
        return ReviewableType.flashcard;
    }
  }
}
