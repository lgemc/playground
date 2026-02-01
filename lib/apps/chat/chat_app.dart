import 'package:flutter/material.dart';
import '../../core/sub_app.dart';
import '../../services/share_content.dart';
import 'models/chat.dart';
import 'models/message.dart';
import 'screens/chat_list_screen.dart';
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
}
