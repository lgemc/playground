import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../services/orchestrator_agent_service.dart';
import '../theme/assistant_theme.dart';

class AssistantChatScreen extends StatefulWidget {
  const AssistantChatScreen({super.key});

  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<AssistantChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AssistantMessage> _messages = [];
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _error;
  String? _currentAction;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAgent();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh messages when returning to this screen
    _refreshMessages();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Reload messages when app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      _refreshMessages();
    }
  }

  void _refreshMessages() {
    if (!_isInitialized) return;

    final messages = OrchestratorAgentService.instance.getMessages();

    // Check if messages differ (by length or content of last message)
    bool needsUpdate = messages.length != _messages.length;

    if (!needsUpdate && messages.isNotEmpty && _messages.isNotEmpty) {
      final lastMessage = messages.last;
      final localLastMessage = _messages.last;
      // Check if last message content has changed (streaming update)
      needsUpdate = lastMessage.content != localLastMessage.content;
    }

    if (mounted && needsUpdate) {
      setState(() {
        _messages.clear();
        _messages.addAll(messages);
        // Check if last message is from assistant and is complete
        final lastMessage = messages.isNotEmpty ? messages.last : null;
        if (lastMessage != null && !lastMessage.isUser && lastMessage.content.isNotEmpty) {
          _isLoading = false;
        }
      });
      _scrollToBottom();
    }
  }

  Future<void> _initializeAgent() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      await OrchestratorAgentService.instance.initialize();

      // Load existing messages if any
      final messages = OrchestratorAgentService.instance.getMessages();

      setState(() {
        _messages.clear();
        _messages.addAll(messages);
        _isInitialized = true;
        _isLoading = false;
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize assistant: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLoading) return;

    // Add user message to UI immediately
    final userMessage = AssistantMessage(
      content: text,
      timestamp: DateTime.now(),
      isUser: true,
    );

    if (mounted) {
      setState(() {
        _messages.add(userMessage);
        _isLoading = true;
      });
    }

    _messageController.clear();
    _scrollToBottom();

    // Create placeholder for AI response
    final aiMessage = AssistantMessage(
      content: '',
      timestamp: DateTime.now(),
      isUser: false,
    );

    if (mounted) {
      setState(() {
        _messages.add(aiMessage);
      });
    }

    _scrollToBottom();

    try {
      final buffer = StringBuffer();
      bool hasReceivedContent = false;

      // Stream the response - continue even if widget is disposed
      await for (final event in OrchestratorAgentService.instance.chatStreamEvents(text)) {
        if (event is ContentEvent) {
          buffer.write(event.content);
          hasReceivedContent = true;

          // Only update UI if widget is still mounted
          if (mounted) {
            setState(() {
              _currentAction = null; // Clear action status when content arrives
              _messages[_messages.length - 1] = AssistantMessage(
                content: buffer.toString(),
                timestamp: aiMessage.timestamp,
                isUser: false,
              );
            });

            _scrollToBottom();
          }
        } else if (event is ToolCallStartEvent) {
          // Update current action
          if (mounted) {
            setState(() {
              _currentAction = event.friendlyName;
            });
          }
        }
      }

      // Ensure we always have a response, even if empty after tool calls
      if (mounted) {
        setState(() {
          if (!hasReceivedContent && buffer.isEmpty) {
            // If no content was generated after tools, show a generic message
            _messages[_messages.length - 1] = AssistantMessage(
              content: 'Done.',
              timestamp: aiMessage.timestamp,
              isUser: false,
            );
          }
          _isLoading = false;
          _currentAction = null;
        });
      }
    } catch (e) {
      // Update AI message with error
      if (mounted) {
        setState(() {
          _messages[_messages.length - 1] = AssistantMessage(
            content: 'Error: $e',
            timestamp: aiMessage.timestamp,
            isUser: false,
          );
          _isLoading = false;
          _currentAction = null;
        });
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

  Future<void> _clearConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Conversation'),
        content: const Text('Are you sure you want to clear the conversation history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await OrchestratorAgentService.instance.resetConversation();
      setState(() {
        _messages.clear();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant'),
        backgroundColor: AssistantTheme.appBarBackground,
        foregroundColor: AssistantTheme.appBarForeground,
        actions: [
          if (_isInitialized && _messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearConversation,
              tooltip: 'Clear conversation',
            ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _buildMessagesList(),
          ),
          // Input area
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeAgent,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Ask me anything!',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'I can help with files, courses, and general questions.',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isLoading) {
          // Show loading indicator if AI message is empty
          final lastMessage = _messages.isNotEmpty ? _messages.last : null;
          if (lastMessage != null && !lastMessage.isUser && lastMessage.content.isEmpty) {
            return _buildLoadingBubble();
          }
        }

        if (index >= _messages.length) return const SizedBox.shrink();

        final message = _messages[index];
        return _MessageBubble(
          content: message.content,
          timestamp: message.timestamp,
          isUser: message.isUser,
        );
      },
    );
  }

  Widget _buildLoadingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: AssistantTheme.primary.withValues(alpha: 0.1),
            radius: 16,
            child: const Icon(Icons.smart_toy, size: 18, color: AssistantTheme.primary),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AssistantTheme.aiBubble,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AssistantTheme.primary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _currentAction ?? 'Thinking...',
                    style: TextStyle(
                      color: AssistantTheme.aiBubbleText,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AssistantTheme.surface,
        boxShadow: [AssistantTheme.inputShadow],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              enabled: !_isLoading,
              style: const TextStyle(
                color: AssistantTheme.inputText,
                fontSize: 16,
              ),
              decoration: AssistantTheme.getInputDecoration(
                hintText: _isLoading
                    ? 'Assistant is thinking...'
                    : 'Type a message...',
                enabled: !_isLoading,
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: _isLoading
                ? Colors.grey
                : AssistantTheme.primary,
            child: IconButton(
              icon: const Icon(Icons.send, color: AssistantTheme.textOnPrimary),
              onPressed: _isLoading ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String content;
  final DateTime timestamp;
  final bool isUser;

  const _MessageBubble({
    required this.content,
    required this.timestamp,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              backgroundColor: AssistantTheme.primary.withValues(alpha: 0.1),
              radius: 16,
              child: const Icon(Icons.smart_toy, size: 18, color: AssistantTheme.primary),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: SelectionArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser ? AssistantTheme.userBubble : AssistantTheme.aiBubble,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MarkdownBody(
                      data: content,
                      shrinkWrap: true,
                      styleSheet: isUser
                          ? AssistantTheme.userMarkdownStyle
                          : AssistantTheme.aiMarkdownStyle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTime(timestamp),
                      style: TextStyle(
                        color: isUser
                            ? AssistantTheme.userBubbleText.withValues(alpha: 0.7)
                            : AssistantTheme.aiBubbleText.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: AssistantTheme.primaryDark,
              radius: 16,
              child: const Icon(Icons.person, size: 18, color: AssistantTheme.textOnPrimary),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}
