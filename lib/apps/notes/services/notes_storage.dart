import '../models/note.dart' as model;
import '../../../core/database/crdt_database.dart';
import '../../../core/sync/services/device_id_service.dart';
import '../../../core/app_bus.dart';
import '../../../core/app_event.dart';

/// Storage service using CRDT database for sync support
class NotesStorage {
  static NotesStorage? _instance;
  static NotesStorage get instance => _instance ??= NotesStorage._();

  NotesStorage._();

  /// Load all non-deleted notes
  Future<List<model.Note>> loadNotes() async {
    final results = await CrdtDatabase.instance.query('''
      SELECT id, title, content, created_at, updated_at
      FROM notes
      WHERE deleted_at IS NULL
      ORDER BY updated_at DESC
    ''');

    return results.map((row) {
      return model.Note(
        id: row['id'] as String,
        title: row['title'] as String,
        content: row['content'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      );
    }).toList();
  }

  /// Watch notes with real-time updates
  Stream<List<model.Note>> watchNotes() {
    return CrdtDatabase.instance.watch('''
      SELECT id, title, content, created_at, updated_at
      FROM notes
      WHERE deleted_at IS NULL
      ORDER BY updated_at DESC
    ''').map((results) {
      return results.map((row) {
        return model.Note(
          id: row['id'] as String,
          title: row['title'] as String,
          content: row['content'] as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
        );
      }).toList();
    });
  }

  /// Load a specific note by ID
  Future<model.Note> loadFullNote(String id) async {
    final results = await CrdtDatabase.instance.query('''
      SELECT id, title, content, created_at, updated_at
      FROM notes
      WHERE id = ? AND deleted_at IS NULL
    ''', [id]);

    if (results.isEmpty) {
      throw Exception('Note not found: $id');
    }

    final row = results.first;
    return model.Note(
      id: row['id'] as String,
      title: row['title'] as String,
      content: row['content'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  /// Save (create or update) a note
  Future<void> saveNote(model.Note note) async {
    final deviceId = await DeviceIdService.instance.getDeviceId();

    // Check if note exists
    final existing = await CrdtDatabase.instance.query('''
      SELECT id, sync_version FROM notes WHERE id = ?
    ''', [note.id]);

    final isNew = existing.isEmpty;
    final syncVersion = isNew ? 1 : (existing.first['sync_version'] as int) + 1;

    // Upsert into CRDT database
    await CrdtDatabase.instance.execute('''
      INSERT OR REPLACE INTO notes (
        id, title, content, created_at, updated_at, deleted_at, device_id, sync_version
      ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)
    ''', [
      note.id,
      note.title,
      note.content,
      note.createdAt.millisecondsSinceEpoch,
      note.updatedAt.millisecondsSinceEpoch,
      deviceId,
      syncVersion,
    ]);

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

  /// Delete a note (soft delete)
  Future<void> deleteNote(String id) async {
    final deviceId = await DeviceIdService.instance.getDeviceId();
    final now = DateTime.now();

    // Get current sync version
    final existing = await CrdtDatabase.instance.query('''
      SELECT sync_version FROM notes WHERE id = ?
    ''', [id]);

    if (existing.isEmpty) return;

    final syncVersion = (existing.first['sync_version'] as int) + 1;

    // Soft delete
    await CrdtDatabase.instance.execute('''
      UPDATE notes
      SET deleted_at = ?, updated_at = ?, device_id = ?, sync_version = ?
      WHERE id = ?
    ''', [
      now.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
      deviceId,
      syncVersion,
      id,
    ]);

    // Emit event to app bus
    await AppBus.instance.emit(AppEvent.create(
      type: 'note.deleted',
      appId: 'notes',
      metadata: {'noteId': id},
    ));
  }

  /// Dispose resources
  Future<void> dispose() async {
    // CRDT database is shared, don't close it
  }

  /// Reset for testing
  static void resetInstance() {
    _instance = null;
  }
}
