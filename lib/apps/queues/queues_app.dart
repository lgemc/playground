import 'package:flutter/material.dart';

import '../../core/sub_app.dart';
import '../../services/queue_service.dart';
import 'screens/queue_list_screen.dart';

/// Queue Debugger App - Monitor queues, messages, and perform manual retries
class QueuesApp extends SubApp {
  @override
  String get id => 'queues';

  @override
  String get name => 'Queue Debugger';

  @override
  IconData get icon => Icons.queue;

  @override
  Color get themeColor => const Color(0xFF9C27B0); // Purple

  @override
  Widget build(BuildContext context) {
    return const QueueListScreen();
  }

  @override
  Future<void> onInit() async {
    // Ensure queue service is initialized
    await QueueService.instance.init();
  }

  @override
  Future<void> onDispose() async {
    // Nothing to dispose
  }
}