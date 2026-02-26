import 'package:flutter/material.dart';
import '../../core/sub_app.dart';
import 'screens/assistant_chat_screen.dart';

class AssistantApp extends SubApp {
  @override
  String get id => 'assistant';

  @override
  String get name => 'Assistant';

  @override
  IconData get icon => Icons.chat_bubble_outline;

  @override
  Color get themeColor => Colors.blue;

  @override
  void onInit() {
    // No special config needed
  }

  @override
  Widget build(BuildContext context) {
    return const AssistantChatScreen();
  }
}
