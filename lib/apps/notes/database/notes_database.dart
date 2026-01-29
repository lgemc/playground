import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/sync/database/syncable_table.dart';

part 'notes_database.g.dart';

/// Notes table with sync support
class Notes extends Table with SyncableTable {
  /// Note title
  TextColumn get title => text()();

  /// Note content (markdown)
  /// Note: The actual content is stored in .md files, this is just for metadata
  TextColumn get contentPreview => text().withDefault(const Constant(''))();
}

@DriftDatabase(tables: [Notes])
class NotesDatabase extends _$NotesDatabase {
  NotesDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // Queries
  Future<List<Note>> getAllNotes() {
    return (select(notes)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  Future<Note?> getNote(String id) {
    return (select(notes)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<int> insertNote(NotesCompanion note) {
    return into(notes).insert(note);
  }

  Future<bool> updateNote(String id, NotesCompanion note) async {
    final count = await (update(notes)..where((t) => t.id.equals(id)))
        .write(note);
    return count > 0;
  }

  Future<void> softDeleteNote(String id, String deviceId) async {
    final now = DateTime.now();
    final note = await getNote(id);
    if (note == null) return;

    await (update(notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        deviceId: Value(deviceId),
        syncVersion: Value(note.syncVersion + 1),
      ),
    );
  }

  // Sync queries
  Future<List<Note>> getNotesSince(DateTime since) {
    return (select(notes)
          ..where((t) => t.updatedAt.isBiggerOrEqualValue(since))
          ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)]))
        .get();
  }

  Future<List<Note>> getAllNotesIncludingDeleted() {
    return (select(notes)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'data', 'notes', 'notes.db'));

    // Ensure directory exists
    await file.parent.create(recursive: true);

    return NativeDatabase(file);
  });
}
