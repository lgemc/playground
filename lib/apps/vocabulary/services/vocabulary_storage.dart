import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../../core/app_bus.dart';
import '../../../core/app_event.dart';
import '../../../core/sync/services/device_id_service.dart';
import '../../../core/database/crdt_database.dart';
import '../models/word.dart';

/// Event types emitted by vocabulary storage (snake_case, infinitive verbs)
class VocabularyEvents {
  static const String create = 'vocabulary.create';
  static const String update = 'vocabulary.update';
  static const String delete = 'vocabulary.delete';
}

/// Vocabulary storage using shared CRDT database
class VocabularyStorage {
  static VocabularyStorage? _instance;
  static VocabularyStorage get instance => _instance ??= VocabularyStorage._();

  VocabularyStorage._();

  String? _deviceId;

  Future<String> get deviceId async {
    _deviceId ??= await DeviceIdService.instance.getDeviceId();
    return _deviceId!;
  }

  /// Convert database row to domain Word model
  Word _toWord(Map<String, Object?> row) {
    final samplePhrases = (json.decode(row['sample_phrases'] as String) as List<dynamic>)
        .map((e) => e as String)
        .toList();

    return Word(
      id: row['id'] as String,
      word: row['word'] as String,
      meaning: row['meaning'] as String,
      samplePhrases: samplePhrases,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  Future<List<Word>> loadWords() async {
    final rows = await CrdtDatabase.instance.query(
      'SELECT * FROM vocabulary_words WHERE deleted_at IS NULL ORDER BY created_at DESC',
    );
    return rows.map(_toWord).toList();
  }

  Future<Word?> getWord(String id) async {
    final rows = await CrdtDatabase.instance.query(
      'SELECT * FROM vocabulary_words WHERE id = ? AND deleted_at IS NULL',
      [id],
    );
    return rows.isNotEmpty ? _toWord(rows.first) : null;
  }

  /// Search words by word text or meaning
  Future<List<Word>> search(String query) async {
    final rows = await CrdtDatabase.instance.query(
      '''SELECT * FROM vocabulary_words
         WHERE (word LIKE ? OR meaning LIKE ?) AND deleted_at IS NULL
         ORDER BY created_at DESC
         LIMIT 50''',
      ['%$query%', '%$query%'],
    );
    return rows.map(_toWord).toList();
  }

  /// Check if a word with the same text already exists (case-insensitive).
  /// Returns the existing word if found, null otherwise.
  /// Excludes the word with the given [excludeId] from the check.
  Future<Word?> findDuplicateWord(String wordText, {String? excludeId}) async {
    final normalized = wordText.trim().toLowerCase();
    final rows = await CrdtDatabase.instance.query(
      'SELECT * FROM vocabulary_words WHERE LOWER(word) = ? AND deleted_at IS NULL ${excludeId != null ? 'AND id != ?' : ''}',
      excludeId != null ? [normalized, excludeId] : [normalized],
    );
    return rows.isNotEmpty ? _toWord(rows.first) : null;
  }

  Future<void> saveWord(Word word, {bool wordChanged = false}) async {
    final devId = await deviceId;
    final now = DateTime.now();

    // Check if word exists
    final existingRows = await CrdtDatabase.instance.query(
      'SELECT * FROM vocabulary_words WHERE id = ?',
      [word.id],
    );
    final isNew = existingRows.isEmpty;

    String? previousWord;
    if (existingRows.isNotEmpty) {
      previousWord = existingRows.first['word'] as String;
    }

    final samplePhrasesJson = json.encode(word.samplePhrases);
    final wordId = word.id.isEmpty ? const Uuid().v4() : word.id;

    if (isNew) {
      // Insert new word
      await CrdtDatabase.instance.execute(
        '''INSERT INTO vocabulary_words
           (id, word, meaning, sample_phrases, created_at, updated_at, deleted_at, device_id, sync_version)
           VALUES (?, ?, ?, ?, ?, ?, NULL, ?, 1)''',
        [
          wordId,
          word.word,
          word.meaning,
          samplePhrasesJson,
          word.createdAt.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch,
          devId,
        ],
      );
    } else {
      // Update existing word
      final currentVersion = existingRows.first['sync_version'] as int;
      await CrdtDatabase.instance.execute(
        '''UPDATE vocabulary_words
           SET word = ?, meaning = ?, sample_phrases = ?, updated_at = ?, device_id = ?, sync_version = ?
           WHERE id = ?''',
        [
          word.word,
          word.meaning,
          samplePhrasesJson,
          now.millisecondsSinceEpoch,
          devId,
          currentVersion + 1,
          word.id,
        ],
      );
    }

    // Determine if word text has changed (for triggering definition lookup)
    final wordTextChanged = isNew || (previousWord != word.word);

    // Emit event to app bus
    await AppBus.instance.emit(AppEvent.create(
      type: isNew ? VocabularyEvents.create : VocabularyEvents.update,
      appId: 'vocabulary',
      metadata: {
        'wordId': wordId,
        'word': word.word,
        'wordChanged': wordTextChanged,
      },
    ));
  }

  Future<void> deleteWord(String id) async {
    final devId = await deviceId;
    final now = DateTime.now();

    // Get current sync version
    final rows = await CrdtDatabase.instance.query(
      'SELECT sync_version FROM vocabulary_words WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return;

    final currentVersion = rows.first['sync_version'] as int;

    // Soft delete
    await CrdtDatabase.instance.execute(
      '''UPDATE vocabulary_words
         SET deleted_at = ?, updated_at = ?, device_id = ?, sync_version = ?
         WHERE id = ?''',
      [
        now.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
        devId,
        currentVersion + 1,
        id,
      ],
    );

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

  /// Watch words for reactive updates
  Stream<List<Word>> watchWords() {
    return CrdtDatabase.instance
        .watch('SELECT * FROM vocabulary_words WHERE deleted_at IS NULL ORDER BY created_at DESC')
        .map((rows) => rows.map(_toWord).toList());
  }
}
