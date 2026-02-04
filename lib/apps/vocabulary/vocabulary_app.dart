import 'package:flutter/material.dart';

import '../../core/sub_app.dart';
import '../../core/search_result.dart';
import '../../core/tool.dart';
import '../../services/share_content.dart';
import '../../services/tool_service.dart';
import 'models/word.dart';
import 'services/vocabulary_storage.dart';
import 'vocabulary_screen.dart';
import 'word_editor_screen.dart';

/// Configuration keys for the vocabulary app
class VocabularyConfig {
  static const String samplePhrasesCount = 'samplePhrasesCount';
  static const String defaultSamplePhrasesCount = '5';
}

class VocabularyApp extends SubApp {
  @override
  String get id => 'vocabulary';

  @override
  String get name => 'Vocabulary';

  @override
  IconData get icon => Icons.book;

  @override
  Color get themeColor => Colors.indigo;

  @override
  void onInit() {
    // Define default configs
    defineConfig(
      VocabularyConfig.samplePhrasesCount,
      VocabularyConfig.defaultSamplePhrasesCount,
    );

    // Register vocabulary creation tool for LLM
    ToolService.instance.register(Tool(
      name: 'add_vocabulary',
      description:
          'Add a new word to the vocabulary list. Use this when the user wants to save a word or phrase for learning.',
      parameters: {
        'type': 'object',
        'properties': {
          'word': {
            'type': 'string',
            'description': 'The word or phrase to add to vocabulary',
          },
          'meaning': {
            'type': 'string',
            'description': 'Optional meaning or definition of the word',
          },
        },
        'required': ['word'],
      },
      handler: _handleAddVocabulary,
      appId: id,
    ));
  }

  Future<ToolResult> _handleAddVocabulary(Map<String, dynamic> args) async {
    final wordText = args['word'] as String?;
    if (wordText == null || wordText.isEmpty) {
      return const ToolResult.failure('Word is required');
    }

    final meaning = args['meaning'] as String? ?? '';

    // Check for duplicates
    final duplicate =
        await VocabularyStorage.instance.findDuplicateWord(wordText);
    if (duplicate != null) {
      return ToolResult.success({
        'status': 'exists',
        'message': 'Word "$wordText" already exists in vocabulary',
      });
    }

    // Create and save the word
    final word = Word.create(word: wordText).copyWith(
      meaning: meaning,
      updatedAt: DateTime.now(),
    );
    await VocabularyStorage.instance.saveWord(word, wordChanged: meaning.isEmpty);

    return ToolResult.success({
      'status': 'created',
      'message': 'Added "$wordText" to vocabulary',
      'wordId': word.id,
    });
  }

  @override
  void onDispose() {
    ToolService.instance.unregister('add_vocabulary');
  }

  @override
  Widget build(BuildContext context) {
    return const VocabularyScreen();
  }

  @override
  List<ShareContentType> get acceptedShareTypes => [ShareContentType.text];

  @override
  Future<void> onReceiveShare(ShareContent content) async {
    if (content.type == ShareContentType.text) {
      final text = content.data['text'] as String? ?? '';
      if (text.isNotEmpty) {
        // Create new word entry from shared text
        final word = Word.create(word: text);
        await VocabularyStorage.instance.saveWord(word);
      }
    }
  }

  @override
  bool get supportsSearch => true;

  @override
  Future<List<SearchResult>> search(String query) async {
    final words = await VocabularyStorage.instance.search(query);
    return words.map((word) {
      // Create a preview with the first sample phrase if available
      String? preview;
      if (word.samplePhrases.isNotEmpty) {
        preview = word.samplePhrases.first;
        if (preview.length > 80) {
          preview = '${preview.substring(0, 80)}...';
        }
      }

      return SearchResult(
        id: word.id,
        type: SearchResultType.vocabularyWord,
        appId: id,
        title: word.word,
        subtitle: word.meaning.isEmpty ? null : word.meaning,
        preview: preview,
        navigationData: {'wordId': word.id},
        timestamp: word.updatedAt,
      );
    }).toList();
  }

  @override
  void navigateToSearchResult(BuildContext context, SearchResult result) async {
    final wordId = result.navigationData['wordId'] as String;
    final word = await VocabularyStorage.instance.getWord(wordId);
    if (word == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Word not found')),
        );
      }
      return;
    }
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => WordEditorScreen(word: word),
        ),
      );
    }
  }
}
