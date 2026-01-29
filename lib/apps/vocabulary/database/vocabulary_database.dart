import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/sync/database/syncable_table.dart';

part 'vocabulary_database.g.dart';

/// Vocabulary words table with sync support
class VocabularyWords extends Table with SyncableTable {
  /// The word text
  TextColumn get word => text()();

  /// Meaning/definition of the word
  TextColumn get meaning => text().withDefault(const Constant(''))();

  /// Sample phrases using the word (JSON-encoded list)
  TextColumn get samplePhrases => text().withDefault(const Constant('[]'))();
}

@DriftDatabase(tables: [VocabularyWords])
class VocabularyDatabase extends _$VocabularyDatabase {
  VocabularyDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // Queries
  Future<List<VocabularyWord>> getAllWords() {
    return (select(vocabularyWords)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<VocabularyWord?> getWord(String id) {
    return (select(vocabularyWords)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<VocabularyWord?> findByWord(String wordText, {String? excludeId}) {
    final normalized = wordText.trim().toLowerCase();
    return (select(vocabularyWords)
          ..where((t) =>
              t.word.lower().equals(normalized) &
              t.deletedAt.isNull() &
              (excludeId != null ? t.id.equals(excludeId).not() : const Constant(true))))
        .getSingleOrNull();
  }

  Future<int> insertWord(VocabularyWordsCompanion word) {
    return into(vocabularyWords).insert(word);
  }

  Future<bool> updateWord(String id, VocabularyWordsCompanion word) async {
    final count = await (update(vocabularyWords)..where((t) => t.id.equals(id)))
        .write(word);
    return count > 0;
  }

  Future<void> softDeleteWord(String id, String deviceId) async {
    final now = DateTime.now();
    final word = await getWord(id);
    if (word == null) return;

    await (update(vocabularyWords)..where((t) => t.id.equals(id))).write(
      VocabularyWordsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        deviceId: Value(deviceId),
        syncVersion: Value(word.syncVersion + 1),
      ),
    );
  }

  // Sync queries
  Future<List<VocabularyWord>> getWordsSince(DateTime since) {
    return (select(vocabularyWords)
          ..where((t) => t.updatedAt.isBiggerOrEqualValue(since))
          ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)]))
        .get();
  }

  Future<List<VocabularyWord>> getAllWordsIncludingDeleted() {
    return (select(vocabularyWords)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'data', 'vocabulary', 'words.db'));

    // Ensure directory exists
    await file.parent.create(recursive: true);

    return NativeDatabase(file);
  });
}
