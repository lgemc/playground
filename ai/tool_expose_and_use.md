# Tool Calling Implementation Plan

## Overview

Expose tool usage to the chat app from other apps, starting with vocabulary creation. When a user writes "add nuances to vocabulary", the chat will call the vocabulary creation functionality via LLM tool calling.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Tool Calling Flow                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. User sends message in Chat                                  │
│           │                                                      │
│           ▼                                                      │
│  2. ChatDetailScreen calls AutocompletionService                │
│     with registered tools                                        │
│           │                                                      │
│           ▼                                                      │
│  3. LLM returns response (may include tool_calls)               │
│           │                                                      │
│           ├── No tool calls → Display response                  │
│           │                                                      │
│           └── Has tool calls ──▶ 4. ToolService.execute()       │
│                                         │                        │
│                                         ▼                        │
│                                  5. Tool handler runs            │
│                                  (e.g., VocabularyTool)          │
│                                         │                        │
│                                         ▼                        │
│                                  6. Result sent back to LLM      │
│                                         │                        │
│                                         ▼                        │
│                                  7. Final response displayed     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## New Files

### 1. Tool Model (`lib/core/tool.dart`)

```dart
/// Represents a tool that can be called by the LLM
class Tool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters; // JSON Schema
  final Future<ToolResult> Function(Map<String, dynamic> args) handler;
  final String? appId; // Optional: which app registered this tool

  const Tool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.handler,
    this.appId,
  });
}

class ToolResult {
  final bool success;
  final dynamic data;
  final String? error;

  const ToolResult.success(this.data) : success = true, error = null;
  const ToolResult.failure(this.error) : success = false, data = null;

  Map<String, dynamic> toJson() => {
    'success': success,
    if (data != null) 'data': data,
    if (error != null) 'error': error,
  };
}
```

### 2. Tool Service (`lib/services/tool_service.dart`)

```dart
/// Central registry for tools that LLM can call
class ToolService {
  static final ToolService instance = ToolService._();
  ToolService._();

  final Map<String, Tool> _tools = {};

  /// Register a tool
  void register(Tool tool) {
    _tools[tool.name] = tool;
  }

  /// Unregister a tool
  void unregister(String name) {
    _tools.remove(name);
  }

  /// Get all registered tools
  List<Tool> get tools => _tools.values.toList();

  /// Get tool by name
  Tool? getTool(String name) => _tools[name];

  /// Execute a tool by name with arguments
  Future<ToolResult> execute(String name, Map<String, dynamic> args) async {
    final tool = _tools[name];
    if (tool == null) {
      return ToolResult.failure('Tool not found: $name');
    }
    try {
      return await tool.handler(args);
    } catch (e) {
      return ToolResult.failure('Tool execution failed: $e');
    }
  }

  /// Convert tools to OpenAI format for API calls
  List<Map<String, dynamic>> toOpenAIFormat() {
    return _tools.values.map((tool) => {
      'type': 'function',
      'function': {
        'name': tool.name,
        'description': tool.description,
        'parameters': tool.parameters,
      },
    }).toList();
  }
}
```

## Modified Files

### 3. AutocompletionService (`lib/services/autocompletion_service.dart`)

Add tool calling support:

```dart
// New imports
import 'package:playground/core/tool.dart';
import 'package:playground/services/tool_service.dart';

// New method for chat with tools
Stream<ChatStreamEvent> completeWithTools(
  List<ChatMessage> messages, {
  List<Tool>? tools,
}) async* {
  // ... implementation using openai_dart's tool support
}

// ChatStreamEvent to handle both content and tool calls
abstract class ChatStreamEvent {}

class ContentChunk extends ChatStreamEvent {
  final String content;
  ContentChunk(this.content);
}

class ToolCallEvent extends ChatStreamEvent {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  ToolCallEvent(this.id, this.name, this.arguments);
}

class CompletionDone extends ChatStreamEvent {}
```

### 4. VocabularyApp (`lib/apps/vocabulary/vocabulary_app.dart`)

Register vocabulary tool in `onInit()`:

```dart
@override
Future<void> onInit() async {
  // ... existing init code

  // Register vocabulary creation tool
  ToolService.instance.register(Tool(
    name: 'add_vocabulary',
    description: 'Add a new word to the vocabulary list. Use this when the user wants to save a word or phrase for learning.',
    parameters: {
      'type': 'object',
      'properties': {
        'word': {
          'type': 'string',
          'description': 'The word or phrase to add to vocabulary',
        },
        'meaning': {
          'type': 'string',
          'description': 'Optional meaning or definition of the word',
        },
      },
      'required': ['word'],
    },
    handler: _handleAddVocabulary,
    appId: id,
  ));
}

Future<ToolResult> _handleAddVocabulary(Map<String, dynamic> args) async {
  final wordText = args['word'] as String?;
  if (wordText == null || wordText.isEmpty) {
    return ToolResult.failure('Word is required');
  }

  final meaning = args['meaning'] as String? ?? '';

  // Check for duplicates
  final duplicate = await VocabularyStorage.instance.findDuplicateWord(wordText);
  if (duplicate != null) {
    return ToolResult.success({
      'status': 'exists',
      'message': 'Word "$wordText" already exists in vocabulary',
    });
  }

  // Create and save the word
  final word = Word.create(word: wordText).copyWith(
    meaning: meaning,
    updatedAt: DateTime.now(),
  );
  await VocabularyStorage.instance.saveWord(word, wordChanged: meaning.isEmpty);

  return ToolResult.success({
    'status': 'created',
    'message': 'Added "$wordText" to vocabulary',
    'wordId': word.id,
  });
}

@override
Future<void> onDispose() async {
  ToolService.instance.unregister('add_vocabulary');
  // ... existing dispose code
}
```

### 5. ChatDetailScreen (`lib/apps/chat/screens/chat_detail_screen.dart`)

Update `_generateAIResponse()` to handle tool calls:

```dart
Future<void> _generateAIResponse() async {
  // ... existing setup code

  final tools = ToolService.instance.tools;
  List<ChatMessage> conversationHistory = [..._messages];

  while (true) {
    final buffer = StringBuffer();
    final toolCalls = <ToolCallEvent>[];

    // Call LLM with tools
    await for (final event in autocompletionService.completeWithTools(
      conversationHistory,
      tools: tools.isNotEmpty ? tools : null,
    )) {
      if (event is ContentChunk) {
        buffer.write(event.content);
        // Update UI with streaming content
        setState(() {
          _messages[_messages.length - 1] = aiMessage.copyWith(
            content: buffer.toString(),
          );
        });
      } else if (event is ToolCallEvent) {
        toolCalls.add(event);
      }
    }

    // If no tool calls, we're done
    if (toolCalls.isEmpty) {
      break;
    }

    // Execute tool calls and add results to history
    for (final toolCall in toolCalls) {
      final result = await ToolService.instance.execute(
        toolCall.name,
        toolCall.arguments,
      );

      // Add tool call and result to conversation for next iteration
      conversationHistory.add(ChatMessage(
        role: MessageRole.assistant,
        content: '', // Tool call message
        toolCalls: [toolCall],
      ));
      conversationHistory.add(ChatMessage(
        role: MessageRole.tool,
        toolCallId: toolCall.id,
        content: jsonEncode(result.toJson()),
      ));
    }

    // Continue loop to get LLM's response after tool execution
  }

  // Save final message
  await widget.storage.createMessage(_messages.last);
}
```

## Implementation Steps

### Phase 1: Core Infrastructure

1. **Create `lib/core/tool.dart`**
   - Tool class with name, description, parameters, handler
   - ToolResult class for success/failure responses

2. **Create `lib/services/tool_service.dart`**
   - Singleton service for tool registration
   - Methods: register, unregister, execute, toOpenAIFormat

3. **Update `lib/services/autocompletion_service.dart`**
   - Add `completeWithTools()` method
   - Create ChatStreamEvent classes
   - Handle tool_calls in OpenAI response format

### Phase 2: Vocabulary Tool

4. **Update `lib/apps/vocabulary/vocabulary_app.dart`**
   - Register `add_vocabulary` tool in onInit()
   - Implement handler using existing VocabularyStorage
   - Unregister in onDispose()

### Phase 3: Chat Integration

5. **Update `lib/apps/chat/screens/chat_detail_screen.dart`**
   - Modify `_generateAIResponse()` for tool calling loop
   - Handle tool execution and result display
   - Show user-friendly messages for tool actions

### Phase 4: Testing & Polish

6. **Test the flow**
   - "add nuances to vocabulary" → should create word
   - "add the word 'serendipity' to my vocabulary" → should work
   - Duplicate handling
   - Error cases

## OpenAI Tool Calling Format Reference

Request with tools:
```json
{
  "model": "gpt-4",
  "messages": [...],
  "tools": [{
    "type": "function",
    "function": {
      "name": "add_vocabulary",
      "description": "Add a word to vocabulary",
      "parameters": {
        "type": "object",
        "properties": {
          "word": {"type": "string"}
        },
        "required": ["word"]
      }
    }
  }]
}
```

Response with tool call:
```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": null,
      "tool_calls": [{
        "id": "call_abc123",
        "type": "function",
        "function": {
          "name": "add_vocabulary",
          "arguments": "{\"word\": \"nuances\"}"
        }
      }]
    }
  }]
}
```

## Compatibility Notes

- **OpenAI**: Full tool calling support
- **vLLM**: Supports OpenAI-compatible tool calling (v0.4.0+)
- **Ollama**: Supports tool calling for compatible models (llama3.1+)

The `openai_dart` package handles all of these through the standard OpenAI API format.

## Future Extensions

1. **More tools**: Notes creation, file operations, settings changes
2. **Tool discovery**: Apps auto-register tools based on capabilities
3. **Tool permissions**: User approval before tool execution
4. **Tool UI**: Show tool execution status in chat bubbles
5. **Parallel tool calls**: Handle multiple simultaneous tool calls
