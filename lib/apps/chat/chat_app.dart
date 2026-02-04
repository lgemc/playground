import 'package:flutter/material.dart';
import '../../core/sub_app.dart';
import '../../core/search_result.dart';
import '../../services/share_content.dart';
import 'models/chat.dart';
import 'models/message.dart';
import 'screens/chat_list_screen.dart';
import 'screens/chat_detail_screen.dart';
import 'services/chat_storage.dart';

class ChatApp extends SubApp {
  @override
  String get id => 'chat';

  @override
  String get name => 'Chat';

  @override
  IconData get icon => Icons.chat;

  @override
  Color get themeColor => Colors.blue;

  @override
  Future<void> onInit() async {
    // Storage is singleton, no init needed
  }

  @override
  Future<void> onDispose() async {
    await ChatStorage.instance.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const ChatListScreen();
  }

  @override
  List<ShareContentType> get acceptedShareTypes => [ShareContentType.text];

  @override
  Future<void> onReceiveShare(ShareContent content) async {
    if (content.type == ShareContentType.text) {
      final text = content.data['text'] as String? ?? '';
      if (text.isNotEmpty) {
        // Create a new chat with the shared text as the first message
        final now = DateTime.now();
        final chatId = now.millisecondsSinceEpoch.toString();

        final chat = Chat(
          id: chatId,
          title: 'Shared: ${text.length > 30 ? '${text.substring(0, 30)}...' : text}',
          createdAt: now,
          updatedAt: now,
        );
        await ChatStorage.instance.createChat(chat);

        final message = Message(
          id: '${chatId}_0',
          chatId: chatId,
          content: text,
          isUser: true,
          createdAt: now,
        );
        await ChatStorage.instance.createMessage(message);
      }
    }
  }

  @override
  bool get supportsSearch => true;

  @override
  Future<List<SearchResult>> search(String query) async {
    final results = <SearchResult>[];

    // Search chats by title
    final chats = await ChatStorage.instance.searchChats(query);
    for (final chat in chats) {
      results.add(SearchResult(
        id: chat.id,
        type: SearchResultType.chat,
        appId: id,
        title: chat.title,
        subtitle: null,
        preview: null,
        navigationData: {'chatId': chat.id},
        timestamp: chat.updatedAt,
      ));
    }

    // Search messages by content
    final messages = await ChatStorage.instance.searchMessages(query);
    for (final message in messages) {
      // Get the chat title for this message
      final chat = await ChatStorage.instance.getChat(message.chatId);

      // Create a preview from the message content
      String preview = message.content.replaceAll('\n', ' ').trim();
      if (preview.length > 100) {
        preview = '${preview.substring(0, 100)}...';
      }

      results.add(SearchResult(
        id: message.id,
        type: SearchResultType.chatMessage,
        appId: id,
        title: chat?.title ?? 'Chat',
        subtitle: message.isUser ? 'You' : 'Assistant',
        preview: preview,
        navigationData: {'chatId': message.chatId, 'messageId': message.id},
        timestamp: message.createdAt,
      ));
    }

    return results;
  }

  @override
  void navigateToSearchResult(BuildContext context, SearchResult result) async {
    final chatId = result.navigationData['chatId'] as String;
    final chat = await ChatStorage.instance.getChat(chatId);
    if (chat == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat not found')),
        );
      }
      return;
    }
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatDetailScreen(
            chat: chat,
            onChatUpdated: () {},
          ),
        ),
      );
    }
  }
}
