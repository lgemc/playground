import 'dart:convert';
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

class ChatDetailScreen extends StatefulWidget {
  final ChatStorage storage;
  final Chat chat;
  final VoidCallback onChatUpdated;

  const ChatDetailScreen({
    super.key,
    required this.storage,
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
    final messages = await widget.storage.getMessages(widget.chat.id);
    setState(() {
      _messages.clear();
      _messages.addAll(messages);
      // If there are existing messages, consider them as sent
      _hasUserSentMessage = messages.isNotEmpty;
    });
    _scrollToBottom();
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

    await widget.storage.createMessage(message);
    _messageController.clear();

    setState(() {
      _messages.add(message);
      _hasUserSentMessage = true;
    });

    // Update chat's updatedAt timestamp
    final updatedChat = _currentChat.copyWith(updatedAt: DateTime.now());
    await widget.storage.updateChat(updatedChat);
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

    // Emit event to trigger title generation via queue
    final event = AppEvent.create(
      type: 'chat.title_generate',
      appId: 'chat',
      metadata: {
        'chatId': _currentChat.id,
      },
    );
    await AppBus.instance.emit(event);
  }

  Future<void> _shareText(String text) async {
    final content = ShareContent.text(
      sourceAppId: 'chat',
      text: text,
    );

    final success = await ShareService.instance.share(context, content);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Text shared successfully')),
      );
    }
  }

  Future<void> _generateAIResponse() async {
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
        await widget.storage.createMessage(errorMessage);
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
        while (true) {
          final buffer = StringBuffer();
          final toolCalls = <ToolCallEvent>[];

          await for (final event in autocompletionService.completeWithTools(
            conversationHistory,
            tools: tools.isNotEmpty ? tools : null,
          )) {
            if (event is ContentChunk) {
              buffer.write(event.content);

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

            final finalMessage = aiMessage.copyWith(content: finalContent);
            await widget.storage.createMessage(finalMessage);

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
        await widget.storage.updateChat(updatedChat);
        setState(() {
          _currentChat = updatedChat;
        });

        _scrollToBottom();
      } catch (e) {
        final errorMessage = aiMessage.copyWith(
          content: 'Error generating AI response: ${e.toString()}',
        );
        await widget.storage.createMessage(errorMessage);
        setState(() {
          _messages[_messages.length - 1] = errorMessage;
          _isGeneratingResponse = false;
        });
      }
    } catch (e) {
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
            await widget.storage.deleteChat(_currentChat.id);
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

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        decoration: BoxDecoration(
          color: isUser ? ChatTheme.userBubble : ChatTheme.aiBubble,
          borderRadius: BorderRadius.circular(16),
        ),
        child: MarkdownBody(
          data: message.content,
          shrinkWrap: true,
          styleSheet: isUser ? ChatTheme.userMarkdownStyle : ChatTheme.aiMarkdownStyle,
        ),
      ),
    );
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
