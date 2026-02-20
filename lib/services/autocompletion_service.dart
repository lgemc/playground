import 'dart:async';
import 'dart:convert';
import 'package:openai_dart/openai_dart.dart';
import 'config_service.dart';
import '../core/tool.dart';
import 'sse_stream_client.dart';

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
  tool,
}

/// Represents a tool call made by the assistant
class ChatToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const ChatToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

/// A chat message with role and content
class ChatMessage {
  final MessageRole role;
  final String content;
  final List<ChatToolCall>? toolCalls;
  final String? toolCallId;

  const ChatMessage({
    required this.role,
    required this.content,
    this.toolCalls,
    this.toolCallId,
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
        if (toolCalls != null && toolCalls!.isNotEmpty) {
          return ChatCompletionMessage.assistant(
            content: content.isEmpty ? null : content,
            toolCalls: toolCalls!
                .map((tc) => ChatCompletionMessageToolCall(
                      id: tc.id,
                      type: ChatCompletionMessageToolCallType.function,
                      function: ChatCompletionMessageFunctionCall(
                        name: tc.name,
                        arguments: jsonEncode(tc.arguments),
                      ),
                    ))
                .toList(),
          );
        }
        return ChatCompletionMessage.assistant(content: content);
      case MessageRole.tool:
        return ChatCompletionMessage.tool(
          toolCallId: toolCallId ?? '',
          content: content,
        );
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

/// Events emitted during streaming completion with tools
sealed class ChatStreamEvent {}

/// A chunk of content from the assistant
class ContentChunk extends ChatStreamEvent {
  final String content;
  ContentChunk(this.content);
}

/// A tool call requested by the assistant
class ToolCallEvent extends ChatStreamEvent {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  ToolCallEvent(this.id, this.name, this.arguments);
}

/// Indicates the completion is done
class CompletionDone extends ChatStreamEvent {}

/// Helper class to build tool calls from streaming chunks
class _ToolCallBuilder {
  String? id;
  String? name;
  final StringBuffer argumentsBuffer = StringBuffer();
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

    final choice = response.choices.firstOrNull;

    // For reasoning models: content is the final answer, reasoningContent is the thinking
    // Some models (vLLM reasoning) only return reasoningContent and never content
    final content = choice?.message.content;
    final reasoning = choice?.message.reasoningContent;

    String finalContent;
    if (content != null && content.isNotEmpty) {
      // Normal case: model returned final answer in content
      finalContent = content;
    } else if (reasoning != null && reasoning.isNotEmpty) {
      // Reasoning model case: need to extract answer from reasoning
      finalContent = reasoning;
    } else {
      finalContent = '';
    }

    return CompletionResponse(
      content: finalContent,
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
      final choice = chunk.choices?.firstOrNull;
      if (choice == null) continue;

      // For reasoning models: prefer content, but fallback to reasoningContent if content is never sent
      // Some vLLM reasoning models ONLY stream reasoningContent in streaming mode
      final delta = choice.delta?.content ?? choice.delta?.reasoningContent;

      if (delta != null && delta.isNotEmpty) {
        yield delta;
      }
    }
  }

  /// Generate a streaming completion with proper separation of reasoning and content.
  ///
  /// Uses raw SSE parsing to correctly handle vLLM reasoning models that send
  /// chain-of-thought in `reasoning_content` and final answer in `content`.
  ///
  /// Set [contentOnly] to true to only yield main content (skip reasoning).
  /// This is useful for structured outputs like definitions where you only want
  /// the final answer without chain-of-thought.
  Stream<StreamChunk> completeStreamStructured(
    List<ChatMessage> messages, {
    String? model,
    int? maxTokens,
    double? temperature,
    bool contentOnly = false,
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
    final baseUrl = config.get(AutocompletionConfig.baseUrl) ??
        AutocompletionConfig.defaultBaseUrl;
    final apiKey = config.get(AutocompletionConfig.apiKey) ?? '';

    final sseClient = SseStreamClient(
      baseUrl: baseUrl,
      apiKey: apiKey,
    );

    final openAIMessages = messages.map((m) => {
      'role': m.role.name,
      'content': m.content,
    }).toList();

    await for (final chunk in sseClient.streamChatCompletion(
      model: effectiveModel,
      messages: openAIMessages,
      temperature: effectiveTemperature,
      maxTokens: effectiveMaxTokens,
    )) {
      if (contentOnly) {
        // Only yield chunks with main content (skip reasoning)
        if (chunk.hasContent || chunk.isDone) {
          yield chunk;
        }
      } else {
        yield chunk;
      }
    }
  }

  /// Generate a completion with tools support (streaming)
  /// Yields ChatStreamEvent objects for content chunks and tool calls
  Stream<ChatStreamEvent> completeWithTools(
    List<ChatMessage> messages, {
    List<Tool>? tools,
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

    // Build tools in OpenAI format
    final openAITools = tools?.map((tool) => ChatCompletionTool(
          type: ChatCompletionToolType.function,
          function: FunctionObject(
            name: tool.name,
            description: tool.description,
            parameters: tool.parameters,
          ),
        )).toList();

    final stream = client.createChatCompletionStream(
      request: CreateChatCompletionRequest(
        model: ChatCompletionModel.modelId(effectiveModel),
        messages: messages.map((m) => m.toOpenAI()).toList(),
        maxCompletionTokens: effectiveMaxTokens,
        temperature: effectiveTemperature,
        tools: openAITools,
      ),
    );

    // Track tool calls being built up from streaming chunks
    final toolCallsInProgress = <String, _ToolCallBuilder>{};

    await for (final chunk in stream) {
      final choice = chunk.choices?.firstOrNull;
      if (choice == null) continue;

      // Only use content, not reasoningContent (reasoning is sent before the actual answer)
      final contentDelta = choice.delta?.content;
      if (contentDelta != null && contentDelta.isNotEmpty) {
        yield ContentChunk(contentDelta);
      }

      // Handle tool call deltas
      final toolCallDeltas = choice.delta?.toolCalls;
      if (toolCallDeltas != null) {
        for (final toolCallDelta in toolCallDeltas) {
          final index = toolCallDelta.index;
          final indexKey = index.toString();

          // Initialize builder if this is a new tool call
          if (!toolCallsInProgress.containsKey(indexKey)) {
            toolCallsInProgress[indexKey] = _ToolCallBuilder();
          }

          final builder = toolCallsInProgress[indexKey]!;

          // Accumulate data from delta
          if (toolCallDelta.id != null) {
            builder.id = toolCallDelta.id!;
          }
          if (toolCallDelta.function?.name != null) {
            builder.name = toolCallDelta.function!.name!;
          }
          if (toolCallDelta.function?.arguments != null) {
            builder.argumentsBuffer.write(toolCallDelta.function!.arguments!);
          }
        }
      }

      // Check if stream is done
      final finishReason = choice.finishReason;
      if (finishReason != null) {
        // If finished with tool_calls, emit the tool call events
        if (finishReason == ChatCompletionFinishReason.toolCalls) {
          for (final builder in toolCallsInProgress.values) {
            if (builder.id != null && builder.name != null) {
              Map<String, dynamic> args = {};
              try {
                final argsString = builder.argumentsBuffer.toString();
                if (argsString.isNotEmpty) {
                  args = jsonDecode(argsString) as Map<String, dynamic>;
                }
              } catch (_) {
                // Skip malformed arguments
              }
              yield ToolCallEvent(builder.id!, builder.name!, args);
            }
          }
        }

        yield CompletionDone();
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

  /// Simple streaming completion with structured output (content only, no reasoning)
  ///
  /// Uses raw SSE streaming to properly separate reasoning from content.
  /// Yields main content immediately. If model only sends reasoning, yields that instead.
  /// This is ideal for structured outputs like titles, definitions, etc.
  Stream<String> promptStreamContentOnly(
    String prompt, {
    String? systemPrompt,
    String? model,
    int? maxTokens,
    double? temperature,
  }) async* {
    final messages = <ChatMessage>[
      if (systemPrompt != null)
        ChatMessage(role: MessageRole.system, content: systemPrompt),
      ChatMessage(role: MessageRole.user, content: prompt),
    ];

    bool hasYieldedContent = false;
    final reasoningBuffer = StringBuffer();

    await for (final chunk in completeStreamStructured(
      messages,
      model: model,
      maxTokens: maxTokens,
      temperature: temperature,
      contentOnly: false,  // Get both reasoning and content
    )) {
      if (chunk.hasContent) {
        hasYieldedContent = true;
        yield chunk.content!;
      } else if (chunk.hasReasoning) {
        // Buffer reasoning — only yield if no content is ever produced
        reasoningBuffer.write(chunk.reasoningContent!);
      }
    }

    // Only fall back to reasoning if the model never sent any content
    if (!hasYieldedContent && reasoningBuffer.isNotEmpty) {
      yield reasoningBuffer.toString();
    }
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
