import 'package:flutter/material.dart';

import '../../core/sub_app.dart';
import '../../services/share_content.dart';
import 'models/note.dart';
import 'notes_screen.dart';
import 'services/notes_storage_v2.dart';

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
  void onInit() {
    // Define default configs
    defineConfig('sortOrder', 'date');
    defineConfig('theme', 'light');
    defineConfig('fontSize', '14');
  }

  @override
  Widget build(BuildContext context) {
    return const NotesScreen();
  }

  @override
  List<ShareContentType> get acceptedShareTypes => [
    ShareContentType.text,
    ShareContentType.note,
    ShareContentType.url,
  ];

  @override
  Future<void> onReceiveShare(ShareContent content) async {
    switch (content.type) {
      case ShareContentType.text:
        // Create note with text as body
        final text = content.data['text'] as String? ?? '';
        if (text.isNotEmpty) {
          final note = Note.create(title: '', content: text);
          await NotesStorageV2.instance.saveNote(note);
        }
        break;
      case ShareContentType.note:
        // Import note directly
        final title = content.data['title'] as String? ?? '';
        final body = content.data['body'] as String? ?? '';
        final note = Note.create(title: title, content: body);
        await NotesStorageV2.instance.saveNote(note);
        break;
      case ShareContentType.url:
        // Create note with URL as content
        final url = content.data['url'] as String? ?? '';
        final urlTitle = content.data['title'] as String? ?? 'Link';
        final note = Note.create(
          title: urlTitle,
          content: '[$urlTitle]($url)',
        );
        await NotesStorageV2.instance.saveNote(note);
        break;
      default:
        break;
    }
  }
}
