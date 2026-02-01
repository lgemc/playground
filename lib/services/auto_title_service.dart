import 'autocompletion_service.dart';

/// Service for generating file titles using AI
class AutoTitleService {
  static AutoTitleService? _instance;
  static AutoTitleService get instance => _instance ??= AutoTitleService._();

  AutoTitleService._();

  final _autocompletion = AutocompletionService.instance;

  static const String _systemPrompt =
      '''Generate a filename for a document.

Rules:
- If the document has a title at the start, use it
- Otherwise create a descriptive filename (3-8 words)
- Use underscores instead of spaces
- Only use letters, numbers, underscores, and hyphens
- Maximum 50 characters

Use this EXACT format (no other text):

FILENAME: <your_filename_here>''';

  /// Extract title from structured response
  String _extractTitle(String response) {
    // Look for "FILENAME: <name>" marker
    final filenameMatch = RegExp(
      r'FILENAME:\s*(.+?)(?:\n|$)',
      multiLine: true,
    ).firstMatch(response);

    if (filenameMatch != null) {
      final title = filenameMatch.group(1)?.trim() ?? '';
      if (title.isNotEmpty) {
        return title;
      }
    }

    // Fallback: return trimmed response
    return response.trim();
  }

  /// Sanitize filename to remove invalid characters
  String _sanitizeFilename(String filename) {
    // Remove leading/trailing whitespace
    var sanitized = filename.trim();

    // Replace invalid characters with hyphens
    sanitized = sanitized.replaceAll(RegExp(r'[/\\:*?"<>|]'), '-');

    // Replace multiple spaces/hyphens with single underscore
    sanitized = sanitized.replaceAll(RegExp(r'[\s-]+'), '_');

    // Remove leading/trailing underscores
    sanitized = sanitized.replaceAll(RegExp(r'^_+|_+$'), '');

    // Truncate to 200 characters (leave room for extension)
    if (sanitized.length > 200) {
      sanitized = sanitized.substring(0, 200);
    }

    // Fallback if empty
    if (sanitized.isEmpty) {
      sanitized = 'Untitled_${DateTime.now().millisecondsSinceEpoch}';
    }

    return sanitized;
  }

  /// Sanitize content for safe inclusion in prompts
  String _sanitizeContent(String content) {
    // Remove null bytes and other control characters that can break JSON
    var sanitized = content
        .replaceAll('\x00', '')  // Remove null bytes
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')  // Remove other control chars
        .replaceAll('\r\n', '\n')  // Normalize line endings
        .trim();

    // Remove invalid Unicode surrogate pairs that break JSON encoding
    // Surrogates are in range U+D800 to U+DFFF
    final runes = <int>[];
    for (final rune in sanitized.runes) {
      // Skip lone surrogates (0xD800-0xDFFF)
      if (rune < 0xD800 || rune > 0xDFFF) {
        runes.add(rune);
      } else {
        // Replace with safe placeholder
        runes.add(0x20); // space
      }
    }

    return String.fromCharCodes(runes).trim();
  }

  /// Generate a title for a file based on its content
  ///
  /// [content] - The text content to analyze
  /// [fileType] - Type of file: 'markdown' or 'pdf'
  /// [currentFilename] - Optional current filename for context
  Future<String> generateTitle({
    required String content,
    required String fileType,
    String? currentFilename,
  }) async {
    if (content.trim().isEmpty) {
      throw ArgumentError('Content cannot be empty');
    }

    // Sanitize content to avoid JSON encoding issues
    final safeContent = _sanitizeContent(content);

    // Build context-aware prompt
    final contextInfo = currentFilename != null
        ? 'Current filename: $currentFilename\n\n'
        : '';

    final fileTypeInfo = fileType == 'markdown'
        ? 'This is a markdown document. Look for # headings at the start.\n\n'
        : 'This is a PDF document. Look for title-like content at the beginning.\n\n';

    final prompt = '''$contextInfo${fileTypeInfo}Content:
$safeContent

Generate a filename based on this content following the rules in the system prompt.''';

    try {
      print('[AutoTitle] Sending prompt (${safeContent.length} chars)');

      // Stream the response - don't limit tokens to allow reasoning models to complete
      final buffer = StringBuffer();
      await for (final chunk in _autocompletion.promptStreamContentOnly(
        prompt,
        systemPrompt: _systemPrompt,
        temperature: 0.3,
      )) {
        buffer.write(chunk);
      }
      final result = buffer.toString();

      print('[AutoTitle] AI response: "$result"');

      // Extract title from structured response
      final extracted = _extractTitle(result);

      print('[AutoTitle] Extracted title: "$extracted"');

      // Sanitize the result
      final sanitized = _sanitizeFilename(extracted);

      print('[AutoTitle] Sanitized result: "$sanitized"');

      return sanitized;
    } catch (e) {
      // If API fails, generate a safe fallback title
      print('[AutoTitle] Error generating title: $e');
      return _sanitizeFilename(currentFilename ?? 'Untitled');
    }
  }

  /// Check if the service is configured
  bool get isConfigured => _autocompletion.isConfigured;

  /// Reset for testing
  static void resetInstance() {
    _instance = null;
  }
}