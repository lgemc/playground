import 'package:flutter/material.dart';

import '../../core/sub_app.dart';
import '../../services/share_content.dart';
import 'models/word.dart';
import 'services/vocabulary_storage.dart';
import 'vocabulary_screen.dart';

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
}
