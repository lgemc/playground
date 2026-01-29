import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/note.dart';

class NotesStorage {
  static NotesStorage? _instance;
  static NotesStorage get instance => _instance ??= NotesStorage._();

  NotesStorage._();

  Directory? _notesDir;

  Future<Directory> get notesDir async {
    if (_notesDir != null) return _notesDir!;

    final appDir = await getApplicationDocumentsDirectory();
    _notesDir = Directory('${appDir.path}/data/notes');

    if (!await _notesDir!.exists()) {
      await _notesDir!.create(recursive: true);
    }

    return _notesDir!;
  }

  File _metadataFile(Directory dir) => File('${dir.path}/metadata.json');

  File _noteFile(Directory dir, String id) => File('${dir.path}/$id.md');

  Future<List<Note>> loadNotes() async {
    final dir = await notesDir;
    final metaFile = _metadataFile(dir);

    if (!await metaFile.exists()) {
      return [];
    }

    final contents = await metaFile.readAsString();
    final List<dynamic> jsonList = json.decode(contents);

    return jsonList
        .map((e) => Note.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<String> loadNoteContent(String id) async {
    final dir = await notesDir;
    final file = _noteFile(dir, id);

    if (!await file.exists()) {
      return '';
    }

    return file.readAsString();
  }

  Future<Note> loadFullNote(String id) async {
    final notes = await loadNotes();
    final note = notes.firstWhere((n) => n.id == id);
    final content = await loadNoteContent(id);
    return note.copyWith(content: content);
  }

  Future<void> saveNote(Note note) async {
    final dir = await notesDir;

    // Save content to .md file
    final contentFile = _noteFile(dir, note.id);
    await contentFile.writeAsString(note.content);

    // Update metadata
    final notes = await loadNotes();
    final existingIndex = notes.indexWhere((n) => n.id == note.id);

    if (existingIndex >= 0) {
      notes[existingIndex] = note;
    } else {
      notes.add(note);
    }

    await _saveMetadata(notes);
  }

  Future<void> deleteNote(String id) async {
    final dir = await notesDir;

    // Delete .md file
    final contentFile = _noteFile(dir, id);
    if (await contentFile.exists()) {
      await contentFile.delete();
    }

    // Update metadata
    final notes = await loadNotes();
    notes.removeWhere((n) => n.id == id);
    await _saveMetadata(notes);
  }

  Future<void> _saveMetadata(List<Note> notes) async {
    final dir = await notesDir;
    final metaFile = _metadataFile(dir);

    final jsonList = notes.map((n) => n.toJson()).toList();
    await metaFile.writeAsString(json.encode(jsonList));
  }
}
