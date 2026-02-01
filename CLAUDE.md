# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

```bash
# Run the app
flutter run

# Analyze code (linting)
flutter analyze   # or: make analyze

# Run tests
flutter test      # or: make test

# Run a single test file
flutter test test/widget_test.dart

# Get dependencies
flutter pub get
```

## Architecture

This is a Flutter-based modular application container. The core concept is a "playground" that hosts multiple self-contained sub-apps, similar to how a mobile OS hosts applications.

### Key Components

**SubApp Interface** (`lib/core/sub_app.dart`): Abstract class all sub-apps must implement. Defines `id`, `name`, `icon`, `themeColor`, `build()`, and lifecycle hooks (`onInit`, `onDispose`).

**AppRegistry** (`lib/core/app_registry.dart`): Singleton that registers sub-apps, provides navigation between apps, and manages app lifecycle.

**Launcher** (`lib/apps/launcher/`): The default "home" sub-app that displays a grid of available apps. It implements SubApp itself, making it replaceable.

### Adding a New Sub-App

1. Create a folder under `lib/apps/{app_name}/`
2. Implement a class extending `SubApp`
3. Register it in `main.dart` via `AppRegistry.instance.register(YourApp())`

### Data Storage Convention

- Each sub-app gets its own data directory: `data/{app_id}/`
- Preferences stored as: `data/{app_id}/settings.json`
- Complex data uses SQLite

### Inter-App Communication

**AppBus** (`lib/core/app_bus.dart`): Event bus for pub/sub messaging between apps. Events are persisted in SQLite. Subscribe with `AppBus.instance.subscribe()` and emit with `AppBus.instance.emit()`.

**QueueService** (`lib/services/queue_service.dart`): Message queue system that routes AppBus events to specific queues. Provides RabbitMQ-like consumption with acknowledgment, exponential backoff, and dead letter queues (DLQ). Queue configurations are in `lib/services/queue_config.dart`.

**ShareService** (`lib/services/share_service.dart`): Enables content sharing between apps. Apps declare accepted content types via `acceptedShareTypes` and implement `onReceiveShare()` in their SubApp class.

### Configuration System

**ConfigService** (`lib/services/config_service.dart`): Two-layer configuration: user overrides (persistent) and defaults (in-memory). Sub-apps can define defaults in `onInit()` using `defineConfig()` and access values via `getConfig()`.

### Shared Modules

**LMS Module** (`lib/shared/lms/`): Shared domain models and services for learning management system features. Can be used across multiple sub-apps. Contains models for courses, lessons, activities, and storage services.

### UI Interaction Guidelines

**List Item Actions**: Use swipe gestures (`Dismissible` widget) instead of popup menus for list item actions:
- Swipe left (endToStart): Delete action with red background
- Swipe right (startToEnd): Secondary action (e.g., restart, archive) with blue background
- Always show confirmation dialogs before destructive actions
- Reference implementation: `lib/apps/vocabulary/widgets/word_list_tile.dart`

### Planning Documents

The `ai/` folder contains planning documents for features (e.g., `ai/_launcher.md`).

## AI/LLM Integration

### AutocompletionService

**Location**: `lib/services/autocompletion_service.dart`

The `AutocompletionService` provides access to OpenAI-compatible LLM APIs. It supports both streaming and non-streaming completions.

#### Known Issue: Non-streaming API with Token Limits

When using the non-streaming `prompt()` or `complete()` methods with tight token limits:

- **Problem**: If the response hits `maxTokens` limit, the API returns `content: null` with `finishReason: length`
- **Symptom**: You get empty string results even though the model generated content
- **Root Cause**: The non-streaming API at line 239 returns empty string when `content` is null

**Solutions**:

1. **Use Streaming API (Recommended)**: The streaming API (`promptStream()` or `completeStream()`) correctly handles partial responses:
   ```dart
   final resultBuffer = StringBuffer();
   await for (final chunk in _autocompletion.promptStream(
     prompt,
     systemPrompt: systemPrompt,
     temperature: 0.3,
     maxTokens: 200,
   )) {
     resultBuffer.write(chunk);
   }
   final result = resultBuffer.toString();
   ```

2. **Increase maxTokens**: Ensure `maxTokens` is high enough for complete responses (100 may be too low for some tasks, try 200-500)

3. **Check finish_reason**: In non-streaming mode, check the `finishReason` in the response to detect truncation

**Reference Implementation**: See `lib/services/auto_title_service.dart` which switched from non-streaming to streaming to fix "Untitled" filename issue.

#### Reasoning Models and Non-Standard Response Fields

Some OpenAI-compatible APIs (especially vLLM-based models like `openai/gpt-oss-120b`) implement reasoning models that return content in non-standard fields:

- **Standard OpenAI**: Uses `delta.content` in streaming responses
- **Reasoning models**: Use `delta.reasoning_content` instead of `delta.content`

**Problem**: Older versions of `openai_dart` (< 0.6.0) don't support `reasoning_content`, causing streaming to return empty results even though the model is generating content.

**Solution**: Upgrade to `openai_dart` version 0.6.0 or higher, which includes native support for reasoning content:

```yaml
dependencies:
  openai_dart: ^0.6.0  # Minimum version for reasoning support
```

The `completeStream()` method in `lib/services/autocompletion_service.dart` uses a fallback:

```dart
// Support both regular content and reasoning content (for o1-style models)
final delta = choice.delta.content ?? choice.delta.reasoningContent;
```

**How to Detect Reasoning Models**:
- Run `curl http://{your-api-url}/v1/models` to check available models
- Test with: `curl -X POST http://{url}/v1/chat/completions` with `"stream": true`
- Look for `reasoning_content` in the response chunks instead of `content`
- Check the `max_model_len` field - small values (e.g., 41,440 tokens) can cause input truncation

**Common Symptoms**:
- Streaming returns 0 chunks but finishes with `reason: length`
- Non-streaming returns `content: null`
- Model appears to work in direct API tests but fails in the app
- Chat/vocabulary work but other features don't (version mismatch issue)

**Important**:
- Always use `openai_dart >= 0.6.0` for reasoning model support
- Verify the model name matches exactly what's returned by `/v1/models`
- Using wrong model names (e.g., `gpt-4o-mini` when server only has `openai/gpt-oss-120b`) results in 404 errors

**Handling Reasoning in Structured Responses**:

Reasoning models may send ONLY `reasoning_content` and never send `content`. This means they include chain-of-thought in the response. Two approaches:

**Approach 1: Use Structured Prompts with Markers (Recommended)**

Use explicit markers in your system prompt and parse them:

```dart
// System prompt
final systemPrompt = '''You are a dictionary assistant.

Use this EXACT format (no other text):

MEANING: <your definition here>

EXAMPLES:
1. <first example>
2. <second example>''';

// Extraction
String _extractMeaning(String response) {
  final meaningMatch = RegExp(r'MEANING:\s*(.+?)(?=\n\nEXAMPLES:|\n\n|$)', dotAll: true)
      .firstMatch(response);
  if (meaningMatch != null) {
    return meaningMatch.group(1)?.trim() ?? '';
  }
  return response.trim();
}
```

**Approach 2: Extract from End of Response**

For simple outputs (like filenames), instruct the model to output ONLY the answer, then take the last substantial line:

```dart
// System prompt
final systemPrompt = '''Generate a filename for a document.
Output ONLY the filename, nothing else.

Rules:
- Use underscores instead of spaces
- Maximum 50 characters

Output only the filename. No explanation, no reasoning, no other text.''';

// Extraction - work backwards from end of response
String _extractAnswer(String response) {
  final lines = response.trim().split('\n');
  for (int i = lines.length - 1; i >= 0; i--) {
    final line = lines[i].trim();
    // Skip reasoning artifacts
    if (line.isEmpty || line.endsWith('?') || line.contains('let\'s') || line.length < 3) {
      continue;
    }
    return line; // Last substantial line is the answer
  }
  return response.trim();
}
```

**Important**:
- Use `promptStreamContentOnly()` which handles both `content` and `reasoning_content` fields
- Don't use tight `maxTokens` limits - let reasoning models complete their thought
- Keep extraction simple - work backwards from response end or use clear markers
- Avoid complex regex hacks that try to guess what the answer looks like

**Reference Implementations**:
- **File titles**: `lib/services/auto_title_service.dart` - extracts from end of reasoning output
- **Vocabulary definitions**: `lib/apps/vocabulary/services/vocabulary_definition_service.dart` - uses `MEANING:` marker