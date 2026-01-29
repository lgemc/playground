import 'package:flutter/material.dart';

import '../../core/sub_app.dart';
import 'logs_screen.dart';

class LogsApp extends SubApp {
  @override
  String get id => 'logs';

  @override
  String get name => 'Logs';

  @override
  IconData get icon => Icons.terminal;

  @override
  Color get themeColor => Colors.blueGrey;

  @override
  Widget build(BuildContext context) {
    return const LogsScreen();
  }
}