import 'package:flutter/material.dart';

import '../../core/sub_app.dart';
import 'notes_screen.dart';

class NotesApp extends SubApp {
  @override
  String get id => 'notes';

  @override
  String get name => 'Notes';

  @override
  IconData get icon => Icons.note;

  @override
  Color get themeColor => Colors.amber;

  @override
  Widget build(BuildContext context) {
    return const NotesScreen();
  }
}
