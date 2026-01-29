import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/app_bus.dart';
import '../../../core/app_event.dart';
import '../models/word.dart';

/// Event types emitted by vocabulary storage (snake_case, infinitive verbs)
class VocabularyEvents {
  static const String create = 'vocabulary.create';
  static const String update = 'vocabulary.update';
  static const String delete = 'vocabulary.delete';
}

class VocabularyStorage {
  static VocabularyStorage? _instance;
  static VocabularyStorage get instance => _instance ??= VocabularyStorage._();

  VocabularyStorage._();

  Directory? _vocabularyDir;

  Future<Directory> get vocabularyDir async {
    if (_vocabularyDir != null) return _vocabularyDir!;

    final appDir = await getApplicationDocumentsDirectory();
    _vocabularyDir = Directory('${appDir.path}/data/vocabulary');

    if (!await _vocabularyDir!.exists()) {
      await _vocabularyDir!.create(recursive: true);
    }

    return _vocabularyDir!;
  }

  File _dataFile(Directory dir) => File('${dir.path}/words.json');

  Future<List<Word>> loadWords() async {
    final dir = await vocabularyDir;
    final dataFile = _dataFile(dir);

    if (!await dataFile.exists()) {
      return [];
    }

    final contents = await dataFile.readAsString();
    final List<dynamic> jsonList = json.decode(contents);

    return jsonList
        .map((e) => Word.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<Word?> getWord(String id) async {
    final words = await loadWords();
    try {
      return words.firstWhere((w) => w.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveWord(Word word, {bool wordChanged = false}) async {
    final words = await loadWords();
    final existingIndex = words.indexWhere((w) => w.id == word.id);
    final isNew = existingIndex < 0;

    String? previousWord;
    if (existingIndex >= 0) {
      previousWord = words[existingIndex].word;
      words[existingIndex] = word;
    } else {
      words.add(word);
    }

    await _saveData(words);

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
    final words = await loadWords();
    words.removeWhere((w) => w.id == id);
    await _saveData(words);

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

    final words = await loadWords();
    final index = words.indexWhere((w) => w.id == wordId);
    if (index >= 0) {
      words[index] = updatedWord;
      await _saveData(words);
    }
  }

  Future<void> _saveData(List<Word> words) async {
    final dir = await vocabularyDir;
    final dataFile = _dataFile(dir);

    final jsonList = words.map((w) => w.toJson()).toList();
    await dataFile.writeAsString(json.encode(jsonList));
  }
}
