import '../../../services/autocompletion_service.dart';
import '../../../services/config_service.dart';
import '../../../services/logger.dart';
import '../../../services/queue_consumer.dart';
import '../../../services/queue_message.dart';
import '../vocabulary_app.dart';
import 'vocabulary_storage.dart';
import 'vocabulary_streaming_service.dart';

/// Service that listens to vocabulary queue and fetches definitions using LLM.
/// Extends QueueConsumer to get both push notifications and polling for reliability.
class VocabularyDefinitionService extends QueueConsumer {
  static VocabularyDefinitionService? _instance;
  static VocabularyDefinitionService get instance =>
      _instance ??= VocabularyDefinitionService._();

  VocabularyDefinitionService._();

  final Logger _logger = Logger(
    appId: 'vocabulary',
    appName: 'Vocabulary Definition Service',
  );

  @override
  String get id => 'vocabulary-definition-consumer';

  @override
  String get name => 'Vocabulary Definition Consumer';

  @override
  String get queueId => 'vocabulary-definition';

  @override
  void onStart() {
    _logger.info(
      'Vocabulary definition service started',
      eventType: 'service_start',
    );
  }

  @override
  void onStop() {
    _logger.info(
      'Vocabulary definition service stopped',
      eventType: 'service_stop',
    );
  }

  @override
  void onError(QueueMessage message, Object error) {
    _logger.error(
      'Error processing message: $error',
      eventType: 'message_error',
      metadata: {'messageId': message.id},
    );
  }

  /// Process a message from the queue
  @override
  Future<bool> processMessage(QueueMessage message) async {
    try {
      final wordId = message.payload['wordId'] as String?;
      final wordText = message.payload['word'] as String?;
      final wordChanged = message.payload['wordChanged'] as bool? ?? false;

      await _logger.info(
        'Processing vocabulary message',
        eventType: 'message_receive',
        metadata: {
          'messageId': message.id,
          'wordId': wordId,
          'word': wordText,
          'wordChanged': wordChanged,
          'eventType': message.eventType,
          'deliveryCount': message.deliveryCount,
        },
      );

      // Only process if the word text actually changed
      if (!wordChanged) {
        await _logger.debug(
          'Skipping message - word text not changed (only content edited)',
          eventType: 'message_skip',
          metadata: {'wordId': wordId, 'reason': 'word_not_changed'},
        );
        return true;
      }

      if (wordId == null || wordText == null || wordText.isEmpty) {
        await _logger.warning(
          'Invalid message payload - missing wordId or word',
          eventType: 'message_invalid',
          metadata: {'wordId': wordId, 'word': wordText},
        );
        return true; // Acknowledge to remove from queue
      }

      // Verify word still exists
      final existingWord = await VocabularyStorage.instance.getWord(wordId);
      if (existingWord == null) {
        await _logger.warning(
          'Word no longer exists, skipping definition lookup',
          eventType: 'word_not_found',
          metadata: {'wordId': wordId},
        );
        return true;
      }

      // Get definition from LLM with streaming
      final result = await _fetchDefinition(wordText, wordId: wordId);

      if (result != null) {
        await VocabularyStorage.instance.updateWordDefinition(
          wordId,
          meaning: result.meaning,
          samplePhrases: result.samplePhrases,
        );

        await _logger.info(
          'Successfully updated word definition',
          eventType: 'definition_save',
          metadata: {
            'wordId': wordId,
            'word': wordText,
            'meaningLength': result.meaning.length,
            'phrasesCount': result.samplePhrases.length,
          },
        );

        return true;
      } else {
        await _logger.error(
          'Failed to fetch definition from LLM',
          eventType: 'definition_fetch_failed',
          metadata: {'wordId': wordId, 'word': wordText},
        );
        return false; // Will retry
      }
    } catch (e, stackTrace) {
      await _logger.error(
        'Error processing vocabulary message: $e',
        eventType: 'message_error',
        metadata: {
          'messageId': message.id,
          'error': e.toString(),
          'stackTrace': stackTrace.toString().split('\n').take(5).join('\n'),
        },
      );
      return false; // Will retry
    }
  }

  /// Fetch definition from LLM with streaming support
  Future<_DefinitionResult?> _fetchDefinition(String word, {String? wordId}) async {
    final autocompletion = AutocompletionService.instance;
    final streaming = VocabularyStreamingService.instance;

    // Log LLM configuration check
    await _logger.debug(
      'Checking LLM configuration',
      eventType: 'llm_config_check',
      metadata: {
        'isConfigured': autocompletion.isConfigured,
        'baseUrl': autocompletion.currentBaseUrl,
        'model': autocompletion.currentModel,
      },
    );

    if (!autocompletion.isConfigured) {
      await _logger.error(
        'LLM not configured - API key is missing',
        eventType: 'llm_not_configured',
        metadata: {
          'requiredConfig': AutocompletionConfig.apiKey,
          'suggestion': 'Set the LLM API key in Settings',
        },
      );
      if (wordId != null) {
        streaming.failGeneration(wordId, 'LLM not configured');
      }
      return null;
    }

    // Get sample phrases count from config
    final config = ConfigService.instance;
    final phrasesCountStr = config.get(
          VocabularyConfig.samplePhrasesCount,
          appId: 'vocabulary',
        ) ??
        VocabularyConfig.defaultSamplePhrasesCount;
    final phrasesCount = int.tryParse(phrasesCountStr) ?? 5;

    await _logger.info(
      'Starting LLM streaming request',
      eventType: 'llm_request_start',
      metadata: {
        'word': word,
        'wordId': wordId,
        'requestedPhrases': phrasesCount,
        'model': autocompletion.currentModel,
        'baseUrl': autocompletion.currentBaseUrl,
        'streaming': true,
      },
    );

    // Start streaming state
    if (wordId != null) {
      streaming.startGeneration(wordId);
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Use a streaming-friendly plain text format
      final systemPrompt = '''You are a dictionary assistant. Given a word, provide:
1. A clear, concise meaning/definition
2. Exactly $phrasesCount example sentences using the word

Use this EXACT format (no other text):

MEANING: <your definition here>

EXAMPLES:
1. <first example sentence>
2. <second example sentence>
3. <third example sentence>
(continue for all $phrasesCount examples)''';

      final userPrompt = 'Define the word: "$word"';

      await _logger.debug(
        'Sending streaming prompt to LLM',
        eventType: 'llm_prompt',
        metadata: {
          'systemPromptLength': systemPrompt.length,
          'userPromptLength': userPrompt.length,
          'word': word,
        },
      );

      // Use structured streaming that properly separates reasoning from content
      // contentOnly=true skips chain-of-thought reasoning and only yields final content
      final buffer = StringBuffer();
      var charCount = 0;

      await for (final chunk in autocompletion.completeStreamStructured([
        ChatMessage(role: MessageRole.system, content: systemPrompt),
        ChatMessage(role: MessageRole.user, content: userPrompt),
      ], contentOnly: true)) {
        // Only process main content (reasoning is filtered by contentOnly: true)
        if (chunk.hasContent) {
          buffer.write(chunk.content);
          charCount += chunk.content!.length;

          // Emit streaming updates to UI
          if (wordId != null) {
            _emitStreamingUpdate(wordId, buffer.toString());
          }
        }
      }

      stopwatch.stop();
      final content = buffer.toString();

      await _logger.info(
        'LLM streaming completed',
        eventType: 'llm_request_success',
        metadata: {
          'word': word,
          'durationMs': stopwatch.elapsedMilliseconds,
          'responseLength': content.length,
          'charCount': charCount,
        },
      );

      await _logger.debug(
        'LLM response',
        eventType: 'llm_response',
        metadata: {
          'word': word,
          'content': content.length > 500
              ? '${content.substring(0, 500)}...'
              : content,
        },
      );

      // Parse the final response
      final result = _parseResponse(content, word);

      if (result != null) {
        await _logger.info(
          'Successfully parsed LLM response',
          eventType: 'llm_parse_success',
          metadata: {
            'word': word,
            'meaningPreview': result.meaning.length > 100
                ? '${result.meaning.substring(0, 100)}...'
                : result.meaning,
            'phrasesCount': result.samplePhrases.length,
          },
        );

        // Complete streaming with final result
        if (wordId != null) {
          streaming.completeGeneration(
            wordId,
            meaning: result.meaning,
            examples: result.samplePhrases,
          );
        }
      } else {
        await _logger.error(
          'Failed to parse LLM response',
          eventType: 'llm_parse_failed',
          metadata: {
            'word': word,
            'responsePreview': content.length > 200
                ? '${content.substring(0, 200)}...'
                : content,
          },
        );

        if (wordId != null) {
          streaming.failGeneration(wordId, 'Failed to parse response');
        }
      }

      return result;
    } catch (e, stackTrace) {
      stopwatch.stop();

      await _logger.error(
        'LLM streaming failed: $e',
        eventType: 'llm_request_failed',
        metadata: {
          'word': word,
          'durationMs': stopwatch.elapsedMilliseconds,
          'errorType': e.runtimeType.toString(),
          'errorMessage': e.toString(),
          'stackTrace': stackTrace.toString().split('\n').take(10).join('\n'),
          'model': autocompletion.currentModel,
          'baseUrl': autocompletion.currentBaseUrl,
        },
      );

      String errorMessage = 'Unknown error';

      // Log specific error types for better debugging
      if (e.toString().contains('401') || e.toString().contains('Unauthorized')) {
        errorMessage = 'Invalid API key';
        await _logger.error(
          'LLM authentication failed - invalid or expired API key',
          eventType: 'llm_auth_error',
          metadata: {
            'suggestion': 'Check that your API key is valid and has not expired',
          },
        );
      } else if (e.toString().contains('429') || e.toString().contains('rate limit')) {
        errorMessage = 'Rate limit exceeded';
        await _logger.warning(
          'LLM rate limit exceeded',
          eventType: 'llm_rate_limit',
          metadata: {
            'suggestion': 'Wait before retrying or check your API quota',
          },
        );
      } else if (e.toString().contains('timeout') || e.toString().contains('TimeoutException')) {
        errorMessage = 'Request timed out';
        await _logger.error(
          'LLM request timed out',
          eventType: 'llm_timeout',
          metadata: {
            'suggestion': 'The LLM service may be slow or unavailable',
          },
        );
      } else if (e.toString().contains('SocketException') || e.toString().contains('network')) {
        errorMessage = 'Network error';
        await _logger.error(
          'Network error connecting to LLM service',
          eventType: 'llm_network_error',
          metadata: {
            'suggestion': 'Check your internet connection and the API base URL',
          },
        );
      }

      if (wordId != null) {
        streaming.failGeneration(wordId, errorMessage);
      }

      return null;
    }
  }

  /// Emit streaming updates by parsing current buffer content
  void _emitStreamingUpdate(String wordId, String content) {
    final streaming = VocabularyStreamingService.instance;
    final parsed = _parsePartialResponse(content);

    if (parsed.meaning.isNotEmpty) {
      streaming.setMeaning(wordId, parsed.meaning);
    }

    for (var i = 0; i < parsed.samplePhrases.length; i++) {
      streaming.setExample(wordId, i, parsed.samplePhrases[i]);
    }
  }

  /// Parse partial response during streaming
  _DefinitionResult _parsePartialResponse(String content) {
    var meaning = '';
    final examples = <String>[];

    // Extract meaning
    final meaningMatch = RegExp(r'MEANING:\s*(.+?)(?=\n\nEXAMPLES:|\n\n|$)', dotAll: true)
        .firstMatch(content);
    if (meaningMatch != null) {
      meaning = meaningMatch.group(1)?.trim() ?? '';
    }

    // Extract examples
    final examplesSection = RegExp(r'EXAMPLES:\s*(.+)', dotAll: true).firstMatch(content);
    if (examplesSection != null) {
      final examplesText = examplesSection.group(1) ?? '';
      // Match numbered examples: "1. text", "2. text", etc.
      final exampleMatches = RegExp(r'(\d+)\.\s*(.+?)(?=\n\d+\.|\n*$)')
          .allMatches(examplesText);
      for (final match in exampleMatches) {
        final text = match.group(2)?.trim() ?? '';
        if (text.isNotEmpty) {
          examples.add(text);
        }
      }
    }

    return _DefinitionResult(meaning: meaning, samplePhrases: examples);
  }

  /// Parse the final response from LLM
  _DefinitionResult? _parseResponse(String content, String word) {
    try {
      final result = _parsePartialResponse(content);

      if (result.meaning.isEmpty) {
        _logger.warning(
          'Parsed response has empty meaning',
          eventType: 'llm_parse_warning',
          metadata: {'word': word},
        );
        return null;
      }

      return result;
    } catch (e) {
      _logger.error(
        'Parsing error: $e',
        eventType: 'llm_parse_error',
        metadata: {
          'word': word,
          'error': e.toString(),
          'contentPreview': content.length > 100
              ? '${content.substring(0, 100)}...'
              : content,
        },
      );
      return null;
    }
  }

  /// Dispose the service
  void dispose() {
    stop();
    _logger.info(
      'Vocabulary definition service disposed',
      eventType: 'service_dispose',
    );
  }

  /// Reset instance for testing
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }
}

/// Result of a definition lookup
class _DefinitionResult {
  final String meaning;
  final List<String> samplePhrases;

  _DefinitionResult({
    required this.meaning,
    required this.samplePhrases,
  });
}
