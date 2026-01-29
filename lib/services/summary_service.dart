import 'autocompletion_service.dart';
import 'config_service.dart';

/// Service for generating summaries using the completions API
class SummaryService {
  static SummaryService? _instance;
  static SummaryService get instance => _instance ??= SummaryService._();

  SummaryService._();

  final _autocompletion = AutocompletionService.instance;
  final _config = ConfigService.instance;

  static const String _systemPrompt = '''You are a helpful assistant that creates concise summaries of documents.
Your summaries should:
- Be clear and well-structured
- Capture the main points and key ideas
- Be formatted in markdown
- Be approximately 200-500 words unless the document is very short or very long
- Use bullet points, headings, and other markdown formatting for clarity''';

  /// Truncate text to fit within token limits
  /// Rough estimation: 1 token ≈ 4 characters for English text
  String _truncateText(String text, int maxInputChars) {
    if (text.length <= maxInputChars) {
      return text;
    }

    final truncated = text.substring(0, maxInputChars);
    return '$truncated\n\n[... text truncated due to length ...]';
  }

  /// Generate a summary from raw text
  /// Returns a stream of text chunks as the summary is generated
  Stream<String> summarizeStream(String text) {
    if (text.trim().isEmpty) {
      throw ArgumentError('Text cannot be empty');
    }

    // Use summary-specific max tokens configuration
    final summaryMaxTokens = int.tryParse(
      _config.get(AutocompletionConfig.summaryMaxTokens) ?? '',
    ) ?? int.parse(AutocompletionConfig.defaultSummaryMaxTokens);

    // Truncate text to fit within model context window
    // Assuming: system prompt (~100 tokens) + input text + max completion tokens < model limit
    // For gpt-4o-mini: 128k context window, but let's be conservative
    // Reserve space: 100 (system) + summaryMaxTokens (output) = need headroom
    // Max input tokens ≈ 120000 - summaryMaxTokens - 500 (safety margin + system prompt)
    final maxInputTokens = 120000 - summaryMaxTokens - 500;
    final maxInputChars = maxInputTokens * 4; // Rough estimation: 1 token ≈ 4 chars

    final truncatedText = _truncateText(text, maxInputChars);
    final prompt = 'Please summarize the following text:\n\n$truncatedText';

    return _autocompletion.promptStream(
      prompt,
      systemPrompt: _systemPrompt,
      temperature: 0.3, // Lower temperature for more focused summaries
      maxTokens: summaryMaxTokens,
    );
  }

  /// Generate a summary from raw text (non-streaming)
  Future<String> summarize(String text) async {
    if (text.trim().isEmpty) {
      throw ArgumentError('Text cannot be empty');
    }

    // Use summary-specific max tokens configuration
    final summaryMaxTokens = int.tryParse(
      _config.get(AutocompletionConfig.summaryMaxTokens) ?? '',
    ) ?? int.parse(AutocompletionConfig.defaultSummaryMaxTokens);

    // Truncate text to fit within model context window (same logic as stream)
    final maxInputTokens = 120000 - summaryMaxTokens - 500;
    final maxInputChars = maxInputTokens * 4;

    final truncatedText = _truncateText(text, maxInputChars);
    final prompt = 'Please summarize the following text:\n\n$truncatedText';

    return _autocompletion.prompt(
      prompt,
      systemPrompt: _systemPrompt,
      temperature: 0.3, // Lower temperature for more focused summaries
      maxTokens: summaryMaxTokens,
    );
  }

  /// Check if the service is configured
  bool get isConfigured => _autocompletion.isConfigured;

  /// Reset for testing
  static void resetInstance() {
    _instance = null;
  }
}
