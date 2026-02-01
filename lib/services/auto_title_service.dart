import 'autocompletion_service.dart';

/// Service for generating file titles using AI
class AutoTitleService {
  static AutoTitleService? _instance;
  static AutoTitleService get instance => _instance ??= AutoTitleService._();

  AutoTitleService._();

  final _autocompletion = AutocompletionService.instance;

  static const String _systemPrompt =
      '''You are a helpful assistant that generates concise, descriptive filenames based on document content.

IMPORTANT: Respond with ONLY the filename. Do not include any reasoning, explanation, or additional text.

Rules:
- If the document has an explicit title (e.g., # heading in markdown, title in PDF), use it literally
- Otherwise, generate a concise, descriptive filename (3-8 words) based on the content
- Return ONLY the filename without extension
- Use title case (e.g., "Machine Learning Basics" not "machine learning basics")
- Replace spaces with underscores (e.g., "Machine_Learning_Basics")
- Avoid special characters: only use letters, numbers, underscores, and hyphens
- Keep it under 50 characters if possible

Output format: Just the filename, nothing else.''';

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

    // Build context-aware prompt
    final contextInfo = currentFilename != null
        ? 'Current filename: $currentFilename\n\n'
        : '';

    final fileTypeInfo = fileType == 'markdown'
        ? 'This is a markdown document. Look for # headings at the start.\n\n'
        : 'This is a PDF document. Look for title-like content at the beginning.\n\n';

    final prompt = '''$contextInfo${fileTypeInfo}Content:
$content

Generate a filename based on this content following the rules in the system prompt.''';

    // Use content-only streaming to skip chain-of-thought reasoning
    // This avoids the need to extract titles from quoted reasoning text
    final buffer = StringBuffer();
    await for (final chunk in _autocompletion.promptStreamContentOnly(
      prompt,
      systemPrompt: _systemPrompt,
      temperature: 0.3,
      maxTokens: 200,
    )) {
      buffer.write(chunk);
    }
    final result = buffer.toString();

    // Sanitize the result
    final sanitized = _sanitizeFilename(result.trim());

    return sanitized;
  }

  /// Check if the service is configured
  bool get isConfigured => _autocompletion.isConfigured;

  /// Reset for testing
  static void resetInstance() {
    _instance = null;
  }
}