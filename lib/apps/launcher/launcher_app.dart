import 'package:flutter/material.dart';
import '../../core/sub_app.dart';
import 'launcher_screen.dart';

/// The launcher is itself a sub-app, allowing it to be replaced
/// with a custom launcher in the future.
class LauncherApp extends SubApp {
  @override
  String get id => 'launcher';

  @override
  String get name => 'Home';

  @override
  IconData get icon => Icons.home;

  @override
  Color get themeColor => Colors.blue;

  @override
  Widget build(BuildContext context) {
    return const LauncherScreen();
  }
}
