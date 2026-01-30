import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../core/app_bus.dart';
import '../../../core/app_event.dart';
import '../../../core/sync/services/device_id_service.dart';
import '../database/vocabulary_database.dart';
import '../models/word.dart';

/// Event types emitted by vocabulary storage (snake_case, infinitive verbs)
class VocabularyEvents {
  static const String create = 'vocabulary.create';
  static const String update = 'vocabulary.update';
  static const String delete = 'vocabulary.delete';
}

/// New vocabulary storage using Drift with sync support
class VocabularyStorageV2 {
  static VocabularyStorageV2? _instance;
  static VocabularyStorageV2 get instance => _instance ??= VocabularyStorageV2._();

  VocabularyStorageV2._();

  final VocabularyDatabase _db = VocabularyDatabase();
  String? _deviceId;

  Future<String> get deviceId async {
    _deviceId ??= await DeviceIdService.instance.getDeviceId();
    return _deviceId!;
  }

  /// Convert Drift VocabularyWord to domain Word model
  Word _toWord(VocabularyWord dbWord) {
    final samplePhrases = (json.decode(dbWord.samplePhrases) as List<dynamic>)
        .map((e) => e as String)
        .toList();

    return Word(
      id: dbWord.id,
      word: dbWord.word,
      meaning: dbWord.meaning,
      samplePhrases: samplePhrases,
      createdAt: dbWord.createdAt,
      updatedAt: dbWord.updatedAt,
    );
  }

  Future<List<Word>> loadWords() async {
    final dbWords = await _db.getAllWords();
    return dbWords.map(_toWord).toList();
  }

  Future<Word?> getWord(String id) async {
    final dbWord = await _db.getWord(id);
    return dbWord != null ? _toWord(dbWord) : null;
  }

  /// Check if a word with the same text already exists (case-insensitive).
  /// Returns the existing word if found, null otherwise.
  /// Excludes the word with the given [excludeId] from the check.
  Future<Word?> findDuplicateWord(String wordText, {String? excludeId}) async {
    final dbWord = await _db.findByWord(wordText, excludeId: excludeId);
    return dbWord != null ? _toWord(dbWord) : null;
  }

  Future<void> saveWord(Word word, {bool wordChanged = false}) async {
    final devId = await deviceId;
    final now = DateTime.now();

    // Check if word exists
    final existing = await _db.getWord(word.id);
    final isNew = existing == null;

    String? previousWord;
    if (existing != null) {
      previousWord = existing.word;
    }

    final samplePhrasesJson = json.encode(word.samplePhrases);

    if (isNew) {
      // Insert new word
      await _db.insertWord(
        VocabularyWordsCompanion(
          id: Value(word.id.isEmpty ? const Uuid().v4() : word.id),
          word: Value(word.word),
          meaning: Value(word.meaning),
          samplePhrases: Value(samplePhrasesJson),
          createdAt: Value(word.createdAt),
          updatedAt: Value(now),
          deletedAt: const Value(null),
          deviceId: Value(devId),
          syncVersion: const Value(1),
        ),
      );
    } else {
      // Update existing word
      await _db.updateWord(
        word.id,
        VocabularyWordsCompanion(
          word: Value(word.word),
          meaning: Value(word.meaning),
          samplePhrases: Value(samplePhrasesJson),
          updatedAt: Value(now),
          deviceId: Value(devId),
          syncVersion: Value(existing.syncVersion + 1),
        ),
      );
    }

    // Determine if word text has changed (for triggering definition lookup)
    final wordTextChanged = isNew || (previousWord != word.word);

    // Emit event to app bus
    await AppBus.instance.emit(AppEvent.create(
      type: isNew ? VocabularyEvents.create : VocabularyEvents.update,
      appId: 'vocabulary',
      metadata: {
        'wordId': word.id,
        'word': word.word,
        'wordChanged': wordTextChanged,
      },
    ));
  }

  Future<void> deleteWord(String id) async {
    final devId = await deviceId;
    await _db.softDeleteWord(id, devId);

    // Emit event to app bus
    await AppBus.instance.emit(AppEvent.create(
      type: VocabularyEvents.delete,
      appId: 'vocabulary',
      metadata: {'wordId': id},
    ));
  }

  Future<void> updateWordDefinition(
    String wordId, {
    required String meaning,
    required List<String> samplePhrases,
  }) async {
    final word = await getWord(wordId);
    if (word == null) return;

    final updatedWord = word.copyWith(
      meaning: meaning,
      samplePhrases: samplePhrases,
      updatedAt: DateTime.now(),
    );

    await saveWord(updatedWord);
  }

  /// Get words that have changed since a given time (for sync)
  Future<List<Word>> getWordsSince(DateTime since) async {
    final dbWords = await _db.getWordsSince(since);
    return dbWords.map(_toWord).toList();
  }

  /// Get changes for sync (callback for DeviceSyncService)
  Future<List<Map<String, dynamic>>> getChangesForSync(DateTime? since) async {
    final List<VocabularyWord> dbWords;

    if (since == null) {
      // Get all words including deleted ones for initial sync
      dbWords = await _db.getAllWordsIncludingDeleted();
    } else {
      // Get words changed since last sync
      dbWords = await _db.getWordsSince(since);
    }

    return dbWords.map((w) => {
      'id': w.id,
      'word': w.word,
      'meaning': w.meaning,
      'samplePhrases': w.samplePhrases,
      'createdAt': w.createdAt.toIso8601String(),
      'updatedAt': w.updatedAt.toIso8601String(),
      'deletedAt': w.deletedAt?.toIso8601String(),
      'deviceId': w.deviceId,
      'syncVersion': w.syncVersion,
    }).toList();
  }

  /// Apply incoming changes from sync (callback for DeviceSyncService)
  Future<void> applyChangesFromSync(List<Map<String, dynamic>> entities) async {
    for (final entity in entities) {
      final remoteId = entity['id'] as String;
      final remoteVersion = entity['syncVersion'] as int;
      final remoteUpdatedAt = DateTime.parse(entity['updatedAt'] as String);
      final remoteDeletedAt = entity['deletedAt'] != null
          ? DateTime.parse(entity['deletedAt'] as String)
          : null;

      // Check if we have this word locally (including soft-deleted for conflict resolution)
      final existing = await _db.getWordIncludingDeleted(remoteId);

      if (existing == null) {
        // New word from remote - insert it
        await _db.insertWord(
          VocabularyWordsCompanion(
            id: Value(remoteId),
            word: Value(entity['word'] as String),
            meaning: Value(entity['meaning'] as String),
            samplePhrases: Value(entity['samplePhrases'] as String),
            createdAt: Value(DateTime.parse(entity['createdAt'] as String)),
            updatedAt: Value(remoteUpdatedAt),
            deletedAt: Value(remoteDeletedAt),
            deviceId: Value(entity['deviceId'] as String),
            syncVersion: Value(remoteVersion),
          ),
        );
      } else {
        // Word exists - check if remote is newer
        if (remoteVersion > existing.syncVersion ||
            (remoteVersion == existing.syncVersion && remoteUpdatedAt.isAfter(existing.updatedAt))) {
          // Remote is newer - update local
          await _db.updateWord(
            remoteId,
            VocabularyWordsCompanion(
              word: Value(entity['word'] as String),
              meaning: Value(entity['meaning'] as String),
              samplePhrases: Value(entity['samplePhrases'] as String),
              updatedAt: Value(remoteUpdatedAt),
              deletedAt: Value(remoteDeletedAt),
              deviceId: Value(entity['deviceId'] as String),
              syncVersion: Value(remoteVersion),
            ),
          );
        }
        // If local is newer or same version, keep local (last-write-wins handled by comparison)
      }
    }
  }

  /// Close the database connection
  Future<void> close() async {
    await _db.close();
  }
}
