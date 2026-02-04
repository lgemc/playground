import 'package:flutter/material.dart';

import '../../core/sub_app.dart';
import '../../core/search_result.dart';
import '../../services/share_content.dart';
import 'models/note.dart';
import 'notes_screen.dart';
import 'note_editor_screen.dart';
import 'services/notes_storage.dart';

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
          await NotesStorage.instance.saveNote(note);
        }
        break;
      case ShareContentType.note:
        // Import note directly
        final title = content.data['title'] as String? ?? '';
        final body = content.data['body'] as String? ?? '';
        final note = Note.create(title: title, content: body);
        await NotesStorage.instance.saveNote(note);
        break;
      case ShareContentType.url:
        // Create note with URL as content
        final url = content.data['url'] as String? ?? '';
        final urlTitle = content.data['title'] as String? ?? 'Link';
        final note = Note.create(
          title: urlTitle,
          content: '[$urlTitle]($url)',
        );
        await NotesStorage.instance.saveNote(note);
        break;
      default:
        break;
    }
  }

  @override
  bool get supportsSearch => true;

  @override
  Future<List<SearchResult>> search(String query) async {
    final notes = await NotesStorage.instance.search(query);
    return notes.map((note) {
      // Create a preview from the content (first 100 chars)
      String preview = note.content.replaceAll('\n', ' ').trim();
      if (preview.length > 100) {
        preview = '${preview.substring(0, 100)}...';
      }

      return SearchResult(
        id: note.id,
        type: SearchResultType.note,
        appId: id,
        title: note.title.isEmpty ? 'Untitled' : note.title,
        subtitle: null,
        preview: preview,
        navigationData: {'noteId': note.id},
        timestamp: note.updatedAt,
      );
    }).toList();
  }

  @override
  void navigateToSearchResult(BuildContext context, SearchResult result) async {
    final noteId = result.navigationData['noteId'] as String;
    final note = await NotesStorage.instance.loadFullNote(noteId);
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => NoteEditorScreen(note: note),
        ),
      );
    }
  }
}
