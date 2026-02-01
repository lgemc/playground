import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// A chunk from the SSE stream with separate reasoning and content
class StreamChunk {
  /// Chain-of-thought reasoning content (for reasoning models)
  final String? reasoningContent;

  /// Main response content
  final String? content;

  /// Finish reason when stream completes (e.g., 'stop', 'length')
  final String? finishReason;

  const StreamChunk({
    this.reasoningContent,
    this.content,
    this.finishReason,
  });

  bool get hasContent => content != null && content!.isNotEmpty;
  bool get hasReasoning => reasoningContent != null && reasoningContent!.isNotEmpty;
  bool get isDone => finishReason != null;
}

/// Low-level SSE streaming client for OpenAI-compatible APIs.
/// Properly handles both regular content and reasoning content (for models like vLLM's gpt-oss).
///
/// This bypasses openai_dart for streaming to correctly parse reasoning_content
/// which some library versions don't handle properly.
class SseStreamClient {
  final String baseUrl;
  final String apiKey;
  final Duration timeout;

  SseStreamClient({
    required this.baseUrl,
    required this.apiKey,
    this.timeout = const Duration(seconds: 120),
  });

  /// Stream chat completions with proper handling of both content and reasoning_content.
  ///
  /// Yields [StreamChunk] objects that separate reasoning from main content,
  /// allowing consumers to handle them differently (e.g., skip reasoning for definitions).
  Stream<StreamChunk> streamChatCompletion({
    required String model,
    required List<Map<String, String>> messages,
    double? temperature,
    int? maxTokens,
    bool includeReasoning = true,
  }) async* {
    final url = Uri.parse('$baseUrl/chat/completions');

    final payload = {
      'model': model,
      'messages': messages,
      'stream': true,
      if (temperature != null) 'temperature': temperature,
      if (maxTokens != null) 'max_tokens': maxTokens,
      if (includeReasoning) 'include_reasoning': true,
    };

    final request = http.Request('POST', url);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'text/event-stream';
    if (apiKey.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $apiKey';
    }
    request.body = jsonEncode(payload);

    final client = http.Client();
    try {
      final response = await client.send(request).timeout(timeout);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw Exception('HTTP ${response.statusCode}: $body');
      }

      // Parse SSE stream
      final lineBuffer = StringBuffer();
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        lineBuffer.write(chunk);

        // Process complete lines
        while (true) {
          final content = lineBuffer.toString();
          final newlineIndex = content.indexOf('\n');
          if (newlineIndex == -1) break;

          final line = content.substring(0, newlineIndex).trim();
          lineBuffer.clear();
          lineBuffer.write(content.substring(newlineIndex + 1));

          if (line.isEmpty) continue;

          // SSE format: data: {json}
          if (line.startsWith('data: ')) {
            final data = line.substring(6); // Remove "data: " prefix

            if (data == '[DONE]') {
              return;
            }

            try {
              final parsed = jsonDecode(data) as Map<String, dynamic>;
              final choices = parsed['choices'] as List?;
              if (choices == null || choices.isEmpty) continue;

              final choice = choices[0] as Map<String, dynamic>;
              final delta = choice['delta'] as Map<String, dynamic>?;
              final finishReason = choice['finish_reason'] as String?;

              if (delta != null || finishReason != null) {
                yield StreamChunk(
                  reasoningContent: delta?['reasoning_content'] as String?,
                  content: delta?['content'] as String?,
                  finishReason: finishReason,
                );
              }
            } catch (_) {
              // Skip malformed JSON chunks silently
            }
          }
        }
      }
    } finally {
      client.close();
    }
  }
}
