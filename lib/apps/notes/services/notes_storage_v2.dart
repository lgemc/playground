import 'dart:io';
import 'package:drift/drift.dart';
import '../database/notes_database.dart';
import '../models/note.dart' as model;
import '../../../core/sync/services/device_id_service.dart';
import '../../../core/app_bus.dart';
import '../../../core/app_event.dart';

/// V2 storage service using Drift for sync support
class NotesStorageV2 {
  static NotesStorageV2? _instance;
  static NotesStorageV2 get instance => _instance ??= NotesStorageV2._();

  NotesStorageV2._();

  final _database = NotesDatabase();
  Directory? _notesDir;

  Future<Directory> get notesDir async {
    if (_notesDir != null) return _notesDir!;

    final dbPath = await _getDatabasePath();
    _notesDir = Directory(dbPath);

    if (!await _notesDir!.exists()) {
      await _notesDir!.create(recursive: true);
    }

    return _notesDir!;
  }

  Future<String> _getDatabasePath() async {
    final result = await _database.customSelect('PRAGMA database_list').get();
    if (result.isNotEmpty) {
      final path = result.first.data['file'] as String?;
      if (path != null) {
        return File(path).parent.path;
      }
    }
    return '';
  }

  File _noteFile(Directory dir, String id) => File('${dir.path}/$id.md');

  Future<List<model.Note>> loadNotes() async {
    final notes = await _database.getAllNotes();
    return notes
        .map((n) => model.Note(
              id: n.id,
              title: n.title,
              content: '',
              createdAt: n.createdAt,
              updatedAt: n.updatedAt,
            ))
        .toList();
  }

  Future<String> loadNoteContent(String id) async {
    final dir = await notesDir;
    final file = _noteFile(dir, id);

    if (!await file.exists()) {
      return '';
    }

    return file.readAsString();
  }

  Future<model.Note> loadFullNote(String id) async {
    final note = await _database.getNote(id);
    if (note == null) {
      throw Exception('Note not found: $id');
    }

    final content = await loadNoteContent(id);
    return model.Note(
      id: note.id,
      title: note.title,
      content: content,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
    );
  }

  Future<void> saveNote(model.Note note) async {
    final dir = await notesDir;
    final deviceId = await DeviceIdService.instance.getDeviceId();

    // Save content to .md file
    final contentFile = _noteFile(dir, note.id);
    await contentFile.writeAsString(note.content);

    // Check if note exists
    final existing = await _database.getNote(note.id);
    final isNew = existing == null;

    final preview = note.content.substring(
      0,
      note.content.length < 200 ? note.content.length : 200,
    );

    if (isNew) {
      await _database.insertNote(
        NotesCompanion.insert(
          id: note.id,
          title: note.title,
          contentPreview: Value(preview),
          createdAt: note.createdAt,
          updatedAt: note.updatedAt,
          deviceId: deviceId,
          syncVersion: const Value(1),
        ),
      );
    } else {
      await _database.updateNote(
        note.id,
        NotesCompanion(
          title: Value(note.title),
          contentPreview: Value(preview),
          updatedAt: Value(note.updatedAt),
          deviceId: Value(deviceId),
          syncVersion: Value(existing.syncVersion + 1),
        ),
      );
    }

    // Emit event to app bus
    await AppBus.instance.emit(AppEvent.create(
      type: isNew ? 'note.created' : 'note.updated',
      appId: 'notes',
      metadata: {
        'noteId': note.id,
        'title': note.title,
      },
    ));
  }

  Future<void> deleteNote(String id) async {
    final dir = await notesDir;
    final deviceId = await DeviceIdService.instance.getDeviceId();

    // Delete .md file
    final contentFile = _noteFile(dir, id);
    if (await contentFile.exists()) {
      await contentFile.delete();
    }

    // Soft delete in database
    await _database.softDeleteNote(id, deviceId);

    // Emit event to app bus
    await AppBus.instance.emit(AppEvent.create(
      type: 'note.deleted',
      appId: 'notes',
      metadata: {'noteId': id},
    ));
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _database.close();
  }

  /// Reset for testing
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }
}
