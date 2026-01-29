import '../../../core/app_bus.dart';
import '../../../core/app_event.dart';
import '../../../services/logger.dart';
import '../../../services/queue_message.dart';
import '../../../services/queue_service.dart';
import '../../../services/autocompletion_service.dart';
import 'chat_storage.dart';

/// Service that listens to the chat title generation queue and processes title tasks using AI
class ChatTitleService {
  static ChatTitleService? _instance;
  static ChatTitleService get instance => _instance ??= ChatTitleService._();

  ChatTitleService._();

  final _queueService = QueueService.instance;
  final _logger = Logger(appId: 'chat_title', appName: 'Chat Title Service');

  ChatStorage? _storage;
  String? _subscriptionId;

  /// Initialize and start listening to the chat title queue
  Future<void> init({
    required ChatStorage storage,
  }) async {
    if (_subscriptionId != null) return;

    _storage = storage;

    await _queueService.init();

    // Subscribe to the chat title generation queue
    _subscriptionId = _queueService.subscribe(
      id: 'chat_title_service',
      queueId: 'chat-title-generator',
      callback: _processTitleTask,
      name: 'Chat Title Service',
    );

    _logger.log('Chat title service initialized', severity: LogSeverity.info);
  }

  /// Process a title generation task from the queue
  Future<bool> _processTitleTask(QueueMessage message) async {
    try {
      final chatId = message.payload['chatId'] as String?;
      if (chatId == null) {
        _logger.log('Title task missing chatId', severity: LogSeverity.error);
        return false;
      }

      _logger.log('Processing title generation for chat: $chatId',
          severity: LogSeverity.info);

      // Load the chat from storage
      final chat = await _storage!.getChat(chatId);
      if (chat == null) {
        _logger.log('Chat not found: $chatId', severity: LogSeverity.error);
        return false;
      }

      // Check if title already exists (not generating and has a real title)
      _logger.log(
          'Chat state - title: "${chat.title}", isTitleGenerating: ${chat.isTitleGenerating}',
          severity: LogSeverity.debug);
      final hasRealTitle = chat.title.isNotEmpty && chat.title != 'New Chat';
      if (!chat.isTitleGenerating && hasRealTitle) {
        _logger.log('Chat already has a title, skipping: $chatId',
            severity: LogSeverity.info);
        return true;
      }

      // Get all messages for the chat
      final messages = await _storage!.getMessages(chatId);
      _logger.log('Found ${messages.length} messages for chat $chatId',
          severity: LogSeverity.debug);
      if (messages.isEmpty) {
        _logger.log('No messages found for chat: $chatId',
            severity: LogSeverity.warning);
        // Set a default title if no messages
        await _updateChatTitle(chatId, 'New Chat');
        return true;
      }

      // Generate title using AI or fallback
      String generatedTitle;
      final autocompletionService = AutocompletionService.instance;
      if (autocompletionService.isConfigured) {
        try {
          generatedTitle = await _generateTitleWithAI(messages);
          // If AI returned empty/default, fall back to message-based title
          if (generatedTitle == 'New Chat' || generatedTitle.isEmpty) {
            _logger.log('AI returned empty title, using fallback',
                severity: LogSeverity.warning);
            generatedTitle = _generateFallbackTitle(messages);
          }
        } catch (e) {
          _logger.log('AI title generation failed: $e, using fallback',
              severity: LogSeverity.warning);
          generatedTitle = _generateFallbackTitle(messages);
        }
      } else {
        _logger.log('AI not configured, using fallback title generation',
            severity: LogSeverity.info);
        generatedTitle = _generateFallbackTitle(messages);
      }

      await _updateChatTitle(chatId, generatedTitle);
      _logger.log('Title generated for chat $chatId: $generatedTitle',
          severity: LogSeverity.info);

      return true;
    } catch (e, stackTrace) {
      _logger.log('Error processing title task: $e\n$stackTrace',
          severity: LogSeverity.error);
      return false;
    }
  }

  /// Generate title using AI based on the entire conversation
  Future<String> _generateTitleWithAI(List<dynamic> messages) async {
    // Build conversation summary for title generation
    final conversationText = messages
        .map((m) => '${m.isUser ? "User" : "Assistant"}: ${m.content}')
        .join('\n');

    // Truncate if too long (to save tokens)
    final truncatedText = conversationText.length > 2000
        ? '${conversationText.substring(0, 2000)}...'
        : conversationText;

    final prompt = '''Based on the following conversation, generate a short, descriptive title (max 50 characters) that captures the main topic. Return ONLY the title, nothing else.

Conversation:
$truncatedText

Title:''';

    final autocompletionService = AutocompletionService.instance;
    // Use streaming since non-streaming returns null content for some providers
    final buffer = StringBuffer();
    await for (final chunk
        in autocompletionService.promptStream(prompt, maxTokens: 60)) {
      buffer.write(chunk);
    }
    final response = buffer.toString();
    _logger.log('AI raw response: "$response"', severity: LogSeverity.debug);

    // Clean up the response
    var title = response.trim();
    _logger.log('AI title after trim: "$title"', severity: LogSeverity.debug);
    // Remove quotes if present
    if (title.startsWith('"') && title.endsWith('"')) {
      title = title.substring(1, title.length - 1);
    }
    if (title.startsWith("'") && title.endsWith("'")) {
      title = title.substring(1, title.length - 1);
    }
    // Truncate if too long
    if (title.length > 50) {
      title = '${title.substring(0, 47)}...';
    }

    final finalTitle = title.isEmpty ? 'New Chat' : title;
    _logger.log('AI final title: "$finalTitle"', severity: LogSeverity.debug);
    return finalTitle;
  }

  /// Fallback title generation when AI is not available
  String _generateFallbackTitle(List<dynamic> messages) {
    // Use the first user message as the basis for the title
    final userMessages = messages.where((m) => m.isUser).toList();
    final firstUserMessage = userMessages.isNotEmpty ? userMessages.first : messages.first;
    final content = firstUserMessage.content as String;
    _logger.log('Fallback title from content: "$content"',
        severity: LogSeverity.debug);

    // Take first few words
    final words = content.split(' ').take(5).toList();
    var title = words.join(' ');
    if (content.split(' ').length > 5) {
      title += '...';
    }
    _logger.log('Fallback title result: "$title"', severity: LogSeverity.debug);
    if (title.isEmpty) return 'New Chat';
    return title.length > 50 ? '${title.substring(0, 47)}...' : title;
  }

  /// Update the chat with the generated title and notify UI
  Future<void> _updateChatTitle(String chatId, String title) async {
    _logger.log('Updating chat $chatId with title: "$title"',
        severity: LogSeverity.debug);
    final chat = await _storage!.getChat(chatId);
    if (chat == null) {
      _logger.log('Chat $chatId not found during update!',
          severity: LogSeverity.error);
      return;
    }
    _logger.log('Chat before update - title: "${chat.title}"',
        severity: LogSeverity.debug);
    final updatedChat = chat.copyWith(
      title: title,
      isTitleGenerating: false,
      updatedAt: DateTime.now(),
    );
    await _storage!.updateChat(updatedChat);

    // Verify the update
    final verifyChat = await _storage!.getChat(chatId);
    _logger.log('Chat after update - title: "${verifyChat?.title}"',
        severity: LogSeverity.debug);

    // Publish event to notify UI
    final titleEvent = AppEvent.create(
      type: 'chat:title_generated',
      appId: 'chat',
      metadata: {
        'chatId': chatId,
        'title': title,
      },
    );
    await AppBus.instance.emit(titleEvent);
    _logger.log('Emitted chat:title_generated event for $chatId',
        severity: LogSeverity.debug);
  }

  /// Stop listening to the queue
  Future<void> dispose() async {
    if (_subscriptionId != null) {
      _queueService.unsubscribe(_subscriptionId!);
      _subscriptionId = null;
    }
    _logger.log('Chat title service disposed', severity: LogSeverity.info);
  }

  /// Reset for testing
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }
}
