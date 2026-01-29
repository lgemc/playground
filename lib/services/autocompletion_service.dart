import 'dart:async';
import 'package:openai_dart/openai_dart.dart';
import 'config_service.dart';

/// Configuration keys for the autocompletion service (global scope)
class AutocompletionConfig {
  static const String baseUrl = 'llm.base_url';
  static const String apiKey = 'llm.api_key';
  static const String model = 'llm.model';
  static const String maxTokens = 'llm.max_tokens';
  static const String temperature = 'llm.temperature';
  static const String summaryMaxTokens = 'llm.summary_max_tokens';

  // Default values
  static const String defaultBaseUrl = 'https://api.openai.com/v1';
  static const String defaultModel = 'gpt-4o-mini';
  static const String defaultMaxTokens = '1024';
  static const String defaultTemperature = '0.7';
  static const String defaultSummaryMaxTokens = '4096';
}

/// Message role in a chat conversation
enum MessageRole {
  system,
  user,
  assistant,
}

/// A chat message with role and content
class ChatMessage {
  final MessageRole role;
  final String content;

  const ChatMessage({
    required this.role,
    required this.content,
  });

  ChatCompletionMessage toOpenAI() {
    switch (role) {
      case MessageRole.system:
        return ChatCompletionMessage.system(content: content);
      case MessageRole.user:
        return ChatCompletionMessage.user(
          content: ChatCompletionUserMessageContent.string(content),
        );
      case MessageRole.assistant:
        return ChatCompletionMessage.assistant(content: content);
    }
  }
}

/// Response from a completion request
class CompletionResponse {
  final String content;
  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;

  const CompletionResponse({
    required this.content,
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
  });
}

/// Service for generating text completions using OpenAI-compatible APIs.
/// Supports OpenAI, vLLM, Ollama, and other compatible endpoints.
class AutocompletionService {
  static AutocompletionService? _instance;
  static AutocompletionService get instance =>
      _instance ??= AutocompletionService._();

  AutocompletionService._();

  OpenAIClient? _client;
  String? _currentBaseUrl;
  String? _currentApiKey;

  /// Initialize global config defaults. Call this during app startup.
  static void initializeDefaults() {
    final config = ConfigService.instance;
    config.setDefault(AutocompletionConfig.baseUrl, AutocompletionConfig.defaultBaseUrl);
    config.setDefault(AutocompletionConfig.model, AutocompletionConfig.defaultModel);
    config.setDefault(AutocompletionConfig.maxTokens, AutocompletionConfig.defaultMaxTokens);
    config.setDefault(AutocompletionConfig.temperature, AutocompletionConfig.defaultTemperature);
    config.setDefault(AutocompletionConfig.summaryMaxTokens, AutocompletionConfig.defaultSummaryMaxTokens);
    // API key has no default - must be configured by user
  }

  /// Get or create the OpenAI client with current configuration
  OpenAIClient _getClient() {
    final config = ConfigService.instance;
    final baseUrl = config.get(AutocompletionConfig.baseUrl) ??
        AutocompletionConfig.defaultBaseUrl;
    final apiKey = config.get(AutocompletionConfig.apiKey);

    // Recreate client if config changed
    if (_client == null ||
        _currentBaseUrl != baseUrl ||
        _currentApiKey != apiKey) {
      _client = OpenAIClient(
        apiKey: apiKey ?? '',
        baseUrl: baseUrl,
      );
      _currentBaseUrl = baseUrl;
      _currentApiKey = apiKey;
    }

    return _client!;
  }

  /// Check if the service is configured (has API key)
  bool get isConfigured {
    final apiKey = ConfigService.instance.get(AutocompletionConfig.apiKey);
    return apiKey != null && apiKey.isNotEmpty;
  }

  /// Get the current model
  String get currentModel {
    return ConfigService.instance.get(AutocompletionConfig.model) ??
        AutocompletionConfig.defaultModel;
  }

  /// Get the current base URL
  String get currentBaseUrl {
    return ConfigService.instance.get(AutocompletionConfig.baseUrl) ??
        AutocompletionConfig.defaultBaseUrl;
  }

  /// Generate a completion from a list of messages
  Future<CompletionResponse> complete(
    List<ChatMessage> messages, {
    String? model,
    int? maxTokens,
    double? temperature,
  }) async {
    if (!isConfigured) {
      throw StateError(
        'AutocompletionService not configured. Set ${AutocompletionConfig.apiKey} in config.',
      );
    }

    final config = ConfigService.instance;
    final effectiveModel =
        model ?? config.get(AutocompletionConfig.model) ?? AutocompletionConfig.defaultModel;
    final effectiveMaxTokens = maxTokens ??
        int.tryParse(config.get(AutocompletionConfig.maxTokens) ?? '') ??
        int.parse(AutocompletionConfig.defaultMaxTokens);
    final effectiveTemperature = temperature ??
        double.tryParse(config.get(AutocompletionConfig.temperature) ?? '') ??
        double.parse(AutocompletionConfig.defaultTemperature);

    final client = _getClient();

    final response = await client.createChatCompletion(
      request: CreateChatCompletionRequest(
        model: ChatCompletionModel.modelId(effectiveModel),
        messages: messages.map((m) => m.toOpenAI()).toList(),
        maxCompletionTokens: effectiveMaxTokens,
        temperature: effectiveTemperature,
      ),
    );

    print('API Response - Choices count: ${response.choices.length}');
    final choice = response.choices.firstOrNull;
    print('First choice: $choice');
    print('Message content type: ${choice?.message.content.runtimeType}');
    print('Message content: ${choice?.message.content}');

    final content = choice?.message.content ?? '';

    print('Final content length: ${content.length}');

    return CompletionResponse(
      content: content,
      finishReason: choice?.finishReason?.name,
      promptTokens: response.usage?.promptTokens,
      completionTokens: response.usage?.completionTokens,
    );
  }

  /// Generate a completion with streaming response
  Stream<String> completeStream(
    List<ChatMessage> messages, {
    String? model,
    int? maxTokens,
    double? temperature,
  }) async* {
    if (!isConfigured) {
      throw StateError(
        'AutocompletionService not configured. Set ${AutocompletionConfig.apiKey} in config.',
      );
    }

    final config = ConfigService.instance;
    final effectiveModel =
        model ?? config.get(AutocompletionConfig.model) ?? AutocompletionConfig.defaultModel;
    final effectiveMaxTokens = maxTokens ??
        int.tryParse(config.get(AutocompletionConfig.maxTokens) ?? '') ??
        int.parse(AutocompletionConfig.defaultMaxTokens);
    final effectiveTemperature = temperature ??
        double.tryParse(config.get(AutocompletionConfig.temperature) ?? '') ??
        double.parse(AutocompletionConfig.defaultTemperature);

    final client = _getClient();

    final stream = client.createChatCompletionStream(
      request: CreateChatCompletionRequest(
        model: ChatCompletionModel.modelId(effectiveModel),
        messages: messages.map((m) => m.toOpenAI()).toList(),
        maxCompletionTokens: effectiveMaxTokens,
        temperature: effectiveTemperature,
      ),
    );

    await for (final chunk in stream) {
      final delta = chunk.choices.firstOrNull?.delta.content;
      final finishReason = chunk.choices.firstOrNull?.finishReason;

      if (finishReason != null) {
        print('Stream finished. Reason: $finishReason');
      }

      if (delta != null) {
        yield delta;
      }
    }
  }

  /// Simple completion with a single prompt (no conversation context)
  Future<String> prompt(
    String prompt, {
    String? systemPrompt,
    String? model,
    int? maxTokens,
    double? temperature,
  }) async {
    final messages = <ChatMessage>[
      if (systemPrompt != null)
        ChatMessage(role: MessageRole.system, content: systemPrompt),
      ChatMessage(role: MessageRole.user, content: prompt),
    ];

    final response = await complete(
      messages,
      model: model,
      maxTokens: maxTokens,
      temperature: temperature,
    );

    return response.content;
  }

  /// Simple streaming completion with a single prompt
  Stream<String> promptStream(
    String prompt, {
    String? systemPrompt,
    String? model,
    int? maxTokens,
    double? temperature,
  }) {
    final messages = <ChatMessage>[
      if (systemPrompt != null)
        ChatMessage(role: MessageRole.system, content: systemPrompt),
      ChatMessage(role: MessageRole.user, content: prompt),
    ];

    return completeStream(
      messages,
      model: model,
      maxTokens: maxTokens,
      temperature: temperature,
    );
  }

  /// Update API configuration
  Future<void> configure({
    String? baseUrl,
    String? apiKey,
    String? model,
    int? maxTokens,
    double? temperature,
  }) async {
    final config = ConfigService.instance;

    if (baseUrl != null) {
      await config.set(AutocompletionConfig.baseUrl, baseUrl);
    }
    if (apiKey != null) {
      await config.set(AutocompletionConfig.apiKey, apiKey);
    }
    if (model != null) {
      await config.set(AutocompletionConfig.model, model);
    }
    if (maxTokens != null) {
      await config.set(AutocompletionConfig.maxTokens, maxTokens.toString());
    }
    if (temperature != null) {
      await config.set(AutocompletionConfig.temperature, temperature.toString());
    }

    // Reset client to pick up new config
    _client = null;
  }

  /// Reset instance for testing
  static void resetInstance() {
    _instance?._client = null;
    _instance = null;
  }
}
