import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../services/chat_storage.dart';
import 'package:uuid/uuid.dart';
import '../../../core/app_bus.dart';
import '../../../core/app_event.dart';
import '../../../services/autocompletion_service.dart';
import '../../../services/share_content.dart';
import '../../../services/share_service.dart';
import '../../../services/tool_service.dart';
import '../theme/chat_theme.dart';
import '../../file_system/services/file_system_storage.dart';
import '../../file_system/screens/image_viewer_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  final Chat chat;
  final VoidCallback onChatUpdated;

  const ChatDetailScreen({
    super.key,
    required this.chat,
    required this.onChatUpdated,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final List<Message> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Uuid _uuid = const Uuid();
  late Chat _currentChat;
  bool _isGeneratingResponse = false;
  bool _hasUserSentMessage = false;
  String? _selectedText;

  @override
  void initState() {
    super.initState();
    _currentChat = widget.chat;
    _loadMessages();
    _subscribeToChatEvents();
  }

  @override
  void dispose() {
    AppBus.instance.unsubscribe('chat_detail_${_currentChat.id}');
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _subscribeToChatEvents() {
    AppBus.instance.subscribe(
      id: 'chat_detail_${_currentChat.id}',
      eventTypes: ['chat:title_generated'],
      callback: (event) async {
        if (event.metadata['chatId'] == _currentChat.id) {
          if (!mounted) return;

          setState(() {
            _currentChat = _currentChat.copyWith(
              title: event.metadata['title'] as String,
              isTitleGenerating: false,
            );
          });
          widget.onChatUpdated();
        }
      },
    );
  }

  Future<void> _loadMessages() async {
    final messages = await ChatStorage.instance.getMessages(widget.chat.id);

    if (!mounted) return;

    setState(() {
      _messages.clear();
      _messages.addAll(messages);
      // If there are existing messages, consider them as sent
      _hasUserSentMessage = messages.isNotEmpty;
    });
    _scrollToBottom();

    // Check if this is a file/derivative share and generate AI response
    if (messages.length == 1 && messages.first.isUser) {
      final metadata = messages.first.metadata;
      if (metadata != null) {
        final isFileContent = metadata['isFileContent'] as bool? ?? false;
        final isDerivativeContent = metadata['isDerivativeContent'] as bool? ?? false;

        if (isFileContent || isDerivativeContent) {
          // Auto-generate AI response for file/derivative shares
          _generateAIResponseForFileShare();
        }
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final message = Message(
      id: _uuid.v4(),
      chatId: widget.chat.id,
      content: text,
      isUser: true,
      createdAt: DateTime.now(),
    );

    await ChatStorage.instance.createMessage(message);
    _messageController.clear();

    if (!mounted) return;

    setState(() {
      _messages.add(message);
      _hasUserSentMessage = true;
    });

    // Update chat's updatedAt timestamp
    final updatedChat = _currentChat.copyWith(updatedAt: DateTime.now());
    await ChatStorage.instance.updateChat(updatedChat);

    if (!mounted) return;

    setState(() {
      _currentChat = updatedChat;
    });

    _scrollToBottom();

    // Generate AI response
    _generateAIResponse();
  }

  Future<void> _enqueueTitleGeneration() async {
    // Only generate if title is still pending and there are messages
    if (!_currentChat.isTitleGenerating || _messages.isEmpty) return;

    print('[ChatDetail] Enqueuing title generation for chat: ${_currentChat.id}');

    // Verify chat exists before emitting event
    final chatExists = await ChatStorage.instance.getChat(_currentChat.id);
    print('[ChatDetail] Chat exists check: ${chatExists != null}');
    if (chatExists == null) {
      print('[ChatDetail] ERROR: Chat ${_currentChat.id} does not exist in database!');
      return;
    }

    // Emit event to trigger title generation via queue
    final event = AppEvent.create(
      type: 'chat.title_generate',
      appId: 'chat',
      metadata: {
        'chatId': _currentChat.id,
      },
    );
    await AppBus.instance.emit(event);
    print('[ChatDetail] Title generation event emitted for chat: ${_currentChat.id}');
  }

  Future<void> _shareText(String text) async {
    // Share selected text as markdown note to preserve formatting
    final content = ShareContent.note(
      sourceAppId: 'chat',
      title: '',
      body: text,
      format: 'markdown',
    );

    final success = await ShareService.instance.share(context, content);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Text shared successfully')),
      );
    }
  }

  Future<void> _shareMessage(Message message) async {
    // Share the full message as a markdown note
    final content = ShareContent.note(
      sourceAppId: 'chat',
      title: message.isUser ? 'Chat message' : 'AI response',
      body: message.content,
      format: 'markdown',
    );

    final success = await ShareService.instance.share(context, content);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message shared successfully')),
      );
    }
  }

  Future<void> _generateAIResponseForFileShare() async {
    if (!mounted) return;

    setState(() {
      _isGeneratingResponse = true;
    });

    // Create placeholder message for streaming
    final aiMessageId = _uuid.v4();
    final aiMessage = Message(
      id: aiMessageId,
      chatId: widget.chat.id,
      content: '',
      isUser: false,
      createdAt: DateTime.now(),
    );

    if (!mounted) return;

    setState(() {
      _messages.add(aiMessage);
    });

    _scrollToBottom();

    try {
      final autocompletionService = AutocompletionService.instance;

      if (!autocompletionService.isConfigured) {
        final errorMessage = aiMessage.copyWith(
          content: 'AI service not configured. Please set your LLM API key in Settings.',
        );
        await ChatStorage.instance.createMessage(errorMessage);

        if (!mounted) return;

        setState(() {
          _messages[_messages.length - 1] = errorMessage;
          _isGeneratingResponse = false;
        });
        return;
      }

      // Get the shared content
      final userMessage = _messages.first;
      final content = userMessage.content;

      // Build special prompt for file content
      final systemPrompt = '''You are a helpful AI assistant. The user has shared a document or file content with you.

IMPORTANT INSTRUCTIONS:
1. Do NOT generate any content, summaries, or analysis until the user explicitly asks for it
2. First, acknowledge that you've received the content
3. Then, analyze the content and suggest 3-5 specific actions the user might want to perform with this content
4. Format your response EXACTLY as follows:

Nice, I see the content you just shared. I suggest you to perform the next actions:

ACTION: [First action suggestion]
ACTION: [Second action suggestion]
ACTION: [Third action suggestion]
(etc.)

Make the action suggestions specific to the content type and what you see in the document.''';

      try {
        final buffer = StringBuffer();

        await for (final chunk in autocompletionService.promptStream(
          content,
          systemPrompt: systemPrompt,
          temperature: 0.7,
          maxTokens: 500,
        )) {
          buffer.write(chunk);

          if (!mounted) return;

          // Update the message in real-time
          final updatedMessage = aiMessage.copyWith(content: buffer.toString());
          setState(() {
            _messages[_messages.length - 1] = updatedMessage;
          });

          _scrollToBottom();
        }

        final finalContent = buffer.toString();

        // Parse suggested actions from the response
        final actions = <String>[];
        final actionRegex = RegExp(r'ACTION:\s*(.+)$', multiLine: true);
        final matches = actionRegex.allMatches(finalContent);

        for (final match in matches) {
          final action = match.group(1)?.trim();
          if (action != null && action.isNotEmpty) {
            actions.add(action);
          }
        }

        // Store the message with suggested actions
        final finalMessage = aiMessage.copyWith(
          content: finalContent,
          metadata: {
            'suggestedActions': actions,
            'isFileShareResponse': true,
          },
        );
        await ChatStorage.instance.createMessage(finalMessage);

        if (!mounted) return;

        setState(() {
          _messages[_messages.length - 1] = finalMessage;
          _isGeneratingResponse = false;
        });

        final updatedChat = _currentChat.copyWith(updatedAt: DateTime.now());
        await ChatStorage.instance.updateChat(updatedChat);

        if (!mounted) return;

        setState(() {
          _currentChat = updatedChat;
        });

        _scrollToBottom();
      } catch (e) {
        final errorMessage = aiMessage.copyWith(
          content: 'Error generating AI response: ${e.toString()}',
        );
        await ChatStorage.instance.createMessage(errorMessage);

        if (!mounted) return;

        setState(() {
          _messages[_messages.length - 1] = errorMessage;
          _isGeneratingResponse = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isGeneratingResponse = false;
      });
    }
  }

  Future<void> _generateAIResponse() async {
    if (!mounted) return;

    setState(() {
      _isGeneratingResponse = true;
    });

    // Create placeholder message for streaming
    final aiMessageId = _uuid.v4();
    final aiMessage = Message(
      id: aiMessageId,
      chatId: widget.chat.id,
      content: '',
      isUser: false,
      createdAt: DateTime.now(),
    );

    if (!mounted) return;

    setState(() {
      _messages.add(aiMessage);
    });

    _scrollToBottom();

    try {
      final autocompletionService = AutocompletionService.instance;

      if (!autocompletionService.isConfigured) {
        final errorMessage = aiMessage.copyWith(
          content: 'AI service not configured. Please set your LLM API key in Settings.',
        );
        await ChatStorage.instance.createMessage(errorMessage);

        if (!mounted) return;

        setState(() {
          _messages[_messages.length - 1] = errorMessage;
          _isGeneratingResponse = false;
        });
        return;
      }

      try {
        // Get registered tools
        final tools = ToolService.instance.tools;

        // Build conversation history for the LLM (exclude the placeholder)
        List<ChatMessage> conversationHistory =
            _messages.sublist(0, _messages.length - 1).map((msg) {
          return ChatMessage(
            role: msg.isUser ? MessageRole.user : MessageRole.assistant,
            content: msg.content,
          );
        }).toList();

        // Tool calling loop - continue until LLM responds without tool calls
        final toolResults = <String, Map<String, dynamic>>{};

        while (true) {
          final buffer = StringBuffer();
          final toolCalls = <ToolCallEvent>[];

          await for (final event in autocompletionService.completeWithTools(
            conversationHistory,
            tools: tools.isNotEmpty ? tools : null,
          )) {
            if (event is ContentChunk) {
              buffer.write(event.content);

              if (!mounted) return;

              // Update the message in real-time
              final updatedMessage =
                  aiMessage.copyWith(content: buffer.toString());
              setState(() {
                _messages[_messages.length - 1] = updatedMessage;
              });

              _scrollToBottom();
            } else if (event is ToolCallEvent) {
              toolCalls.add(event);
            }
          }

          // If no tool calls, we're done
          if (toolCalls.isEmpty) {
            final finalContent = buffer.toString();
            print(
                'AI Response completed - Length: ${finalContent.length} chars');

            // Include any tool results collected during this conversation
            final finalMessage = aiMessage.copyWith(
              content: finalContent,
              metadata: toolResults.isNotEmpty
                  ? {'tool_results': toolResults}
                  : null,
            );
            await ChatStorage.instance.createMessage(finalMessage);

            if (!mounted) return;

            setState(() {
              _messages[_messages.length - 1] = finalMessage;
              _isGeneratingResponse = false;
            });

            break;
          }

          // Execute tool calls and add results to conversation history
          for (final toolCall in toolCalls) {
            print('Executing tool: ${toolCall.name} with args: ${toolCall.arguments}');

            final result = await ToolService.instance.execute(
              toolCall.name,
              toolCall.arguments,
            );

            print('Tool result: ${result.toJson()}');

            // Store tool results for metadata
            toolResults[toolCall.name] = result.toJson();

            // Add assistant message with tool call to history
            conversationHistory.add(ChatMessage(
              role: MessageRole.assistant,
              content: buffer.toString(),
              toolCalls: [
                ChatToolCall(
                  id: toolCall.id,
                  name: toolCall.name,
                  arguments: toolCall.arguments,
                )
              ],
            ));

            // Add tool result to history
            conversationHistory.add(ChatMessage(
              role: MessageRole.tool,
              toolCallId: toolCall.id,
              content: jsonEncode(result.toJson()),
            ));

            if (!mounted) return;

            // Update UI to show tool execution
            final toolStatusMessage = aiMessage.copyWith(
              content:
                  '${buffer.toString()}\n\n_Executing ${toolCall.name}..._',
            );
            setState(() {
              _messages[_messages.length - 1] = toolStatusMessage;
            });
          }

          // Clear buffer for next iteration
          buffer.clear();
        }

        final updatedChat = _currentChat.copyWith(updatedAt: DateTime.now());
        await ChatStorage.instance.updateChat(updatedChat);

        if (!mounted) return;

        setState(() {
          _currentChat = updatedChat;
        });

        _scrollToBottom();
      } catch (e) {
        final errorMessage = aiMessage.copyWith(
          content: 'Error generating AI response: ${e.toString()}',
        );
        await ChatStorage.instance.createMessage(errorMessage);

        if (!mounted) return;

        setState(() {
          _messages[_messages.length - 1] = errorMessage;
          _isGeneratingResponse = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isGeneratingResponse = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          if (!_hasUserSentMessage) {
            // Delete the chat if no message was sent
            await ChatStorage.instance.deleteChat(_currentChat.id);
            widget.onChatUpdated();
          } else {
            _enqueueTitleGeneration();
          }
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Text(
                _currentChat.title,
                style: TextStyle(
                  fontStyle: _currentChat.isTitleGenerating
                      ? FontStyle.italic
                      : FontStyle.normal,
                  color: ChatTheme.appBarForeground,
                ),
              ),
            ),
            if (_currentChat.isTitleGenerating)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ChatTheme.appBarForeground,
                ),
              ),
          ],
        ),
        backgroundColor: ChatTheme.appBarBackground,
        foregroundColor: ChatTheme.appBarForeground,
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'Start a conversation',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  )
                : SelectionArea(
                    onSelectionChanged: (value) {
                      _selectedText = value?.plainText;
                    },
                    contextMenuBuilder: (context, selectableRegionState) {
                      return AdaptiveTextSelectionToolbar.buttonItems(
                        anchors: selectableRegionState.contextMenuAnchors,
                        buttonItems: [
                          ...selectableRegionState.contextMenuButtonItems,
                          ContextMenuButtonItem(
                            label: 'Share',
                            onPressed: () {
                              if (_selectedText != null && _selectedText!.isNotEmpty) {
                                selectableRegionState.hideToolbar();
                                _shareText(_selectedText!);
                              }
                            },
                          ),
                        ],
                      );
                    },
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_isGeneratingResponse ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length && _isGeneratingResponse) {
                          return _buildLoadingBubble();
                        }
                        final message = _messages[index];
                        return _buildMessageBubble(message);
                      },
                    ),
                  ),
          ),
          _buildMessageInput(),
        ],
      ),
      ),
    );
  }

  Widget _buildMessageBubble(Message message) {
    final isUser = message.isUser;

    print('Rendering message ${message.id} - isUser: $isUser - Length: ${message.content.length}');

    // Extract image attachments from metadata
    final images = <Widget>[];
    final suggestedActions = <String>[];
    if (message.metadata != null) {
      final toolResults = message.metadata!['tool_results'] as Map<String, dynamic>?;
      if (toolResults != null) {
        // Check for generate_image tool result
        final imageResult = toolResults['generate_image'] as Map<String, dynamic>?;
        if (imageResult != null && imageResult['success'] == true) {
          final data = imageResult['data'] as Map<String, dynamic>?;
          if (data != null) {
            final fileId = data['file_id'] as String?;
            final fileName = data['file_name'] as String?;
            final relativePath = data['relative_path'] as String?;

            if (fileId != null && relativePath != null) {
              images.add(_buildImageAttachment(fileId, fileName ?? 'image.png', relativePath));
            }
          }
        }
      }

      // Extract suggested actions
      final actions = message.metadata!['suggestedActions'] as List?;
      if (actions != null) {
        suggestedActions.addAll(actions.cast<String>());
      }
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? ChatTheme.userBubble : ChatTheme.aiBubble,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: message.content,
                    shrinkWrap: true,
                    styleSheet: isUser ? ChatTheme.userMarkdownStyle : ChatTheme.aiMarkdownStyle,
                  ),
                  if (images.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...images,
                  ],
                ],
              ),
            ),
            // Suggested actions as clickable buttons
            if (suggestedActions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: suggestedActions.map((action) {
                  return ElevatedButton(
                    onPressed: () => _sendActionMessage(action),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ChatTheme.primary.withOpacity(0.1),
                      foregroundColor: ChatTheme.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: ChatTheme.primary.withOpacity(0.3)),
                      ),
                    ),
                    child: Text(
                      action,
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                }).toList(),
              ),
            ],
            // Share button below message
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: GestureDetector(
                onTap: () => _shareMessage(message),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.share_outlined,
                      size: 14,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Share',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendActionMessage(String action) {
    // Set the message text and send
    _messageController.text = action;
    _sendMessage();
  }

  Widget _buildImageAttachment(String fileId, String fileName, String relativePath) {
    return FutureBuilder<String?>(
      future: _getImagePath(relativePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.image, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(fileName, style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          );
        }

        final imagePath = snapshot.data!;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ImageViewerScreen(
                  filePath: imagePath,
                  fileName: fileName,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(imagePath),
              width: 200,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text(fileName, style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<String?> _getImagePath(String relativePath) async {
    try {
      final storageDir = FileSystemStorage.instance.storageDir;
      final imagePath = '${storageDir.path}/$relativePath';
      final file = File(imagePath);
      if (await file.exists()) {
        return imagePath;
      }
      return null;
    } catch (e) {
      print('Error getting image path: $e');
      return null;
    }
  }

  Widget _buildLoadingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: ChatTheme.aiBubble,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(ChatTheme.primary),
              ),
            ),
            SizedBox(width: 8),
            Text(
              'Thinking...',
              style: TextStyle(
                color: ChatTheme.aiBubbleText,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ChatTheme.surface,
        boxShadow: [ChatTheme.inputShadow],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              enabled: !_isGeneratingResponse,
              style: const TextStyle(
                color: ChatTheme.inputText,
                fontSize: 16,
              ),
              decoration: ChatTheme.getInputDecoration(
                hintText: _isGeneratingResponse
                    ? 'AI is thinking...'
                    : 'Type a message...',
                enabled: !_isGeneratingResponse,
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: _isGeneratingResponse
                ? Colors.grey
                : ChatTheme.primary,
            child: IconButton(
              icon: const Icon(Icons.send, color: ChatTheme.textOnPrimary),
              onPressed: _isGeneratingResponse ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
