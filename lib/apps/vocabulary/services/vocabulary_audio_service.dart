import '../../../services/audio_generation_service.dart';
import '../../../services/logger.dart';
import '../../../services/queue_consumer.dart';
import '../../../services/queue_message.dart';
import '../../../apps/file_system/models/file_item.dart';
import 'vocabulary_storage.dart';

/// Service that listens to vocabulary-audio queue and generates audio for words and samples.
/// Extends QueueConsumer to get both push notifications and polling for reliability.
class VocabularyAudioService extends QueueConsumer {
  static VocabularyAudioService? _instance;
  static VocabularyAudioService get instance =>
      _instance ??= VocabularyAudioService._();

  VocabularyAudioService._();

  final Logger _logger = Logger(
    appId: 'vocabulary',
    appName: 'Vocabulary Audio Service',
  );

  @override
  String get id => 'vocabulary-audio-consumer';

  @override
  String get name => 'Vocabulary Audio Consumer';

  @override
  String get queueId => 'vocabulary-audio';

  @override
  void onStart() {
    _logger.info(
      'Vocabulary audio service started',
      eventType: 'service_start',
    );
  }

  @override
  void onStop() {
    _logger.info(
      'Vocabulary audio service stopped',
      eventType: 'service_stop',
    );
  }

  @override
  void onError(QueueMessage message, Object error) {
    _logger.error(
      'Error processing message: $error',
      eventType: 'message_error',
      metadata: {'messageId': message.id},
    );
  }

  /// Process a message from the queue
  @override
  Future<bool> processMessage(QueueMessage message) async {
    try {
      final wordId = message.payload['wordId'] as String?;

      await _logger.info(
        'Processing vocabulary audio message',
        eventType: 'message_receive',
        metadata: {
          'messageId': message.id,
          'wordId': wordId,
          'eventType': message.eventType,
          'deliveryCount': message.deliveryCount,
        },
      );

      if (wordId == null || wordId.isEmpty) {
        await _logger.warning(
          'Invalid message payload - missing wordId',
          eventType: 'message_invalid',
          metadata: {'wordId': wordId},
        );
        return true; // Acknowledge to remove from queue
      }

      // Retrieve word from database
      final word = await VocabularyStorage.instance.getWord(wordId);
      if (word == null) {
        await _logger.warning(
          'Word no longer exists, skipping audio generation',
          eventType: 'word_not_found',
          metadata: {'wordId': wordId},
        );
        return true;
      }

      // Verify word has meaning and samples
      if (word.meaning.isEmpty || word.samplePhrases.isEmpty) {
        await _logger.warning(
          'Word has no meaning or samples, skipping audio generation',
          eventType: 'word_incomplete',
          metadata: {
            'wordId': wordId,
            'word': word.word,
            'hasMeaning': word.meaning.isNotEmpty,
            'sampleCount': word.samplePhrases.length,
          },
        );
        return true; // Acknowledge to remove from queue
      }

      final wordText = word.word;
      final samplePhrases = word.samplePhrases;

      final audioService = AudioGenerationService.instance;

      if (!audioService.isConfigured) {
        await _logger.error(
          'Audio generation service not configured',
          eventType: 'audio_not_configured',
          metadata: {
            'suggestion': 'Set the audio generation API URL in Settings',
          },
        );
        return false; // Will retry
      }

      // Generate audio for the word
      String? wordAudioPath;
      try {
        await _logger.info(
          'Generating audio for word',
          eventType: 'word_audio_start',
          metadata: {'wordId': wordId, 'word': wordText},
        );

        final wordAudioFile = await audioService.generateAudioForApp(
          text: wordText,
          filename: '${wordText}_word',
          appId: 'vocabulary',
        );
        wordAudioPath = wordAudioFile.relativePath;

        await _logger.info(
          'Successfully generated word audio',
          eventType: 'word_audio_success',
          metadata: {
            'wordId': wordId,
            'word': wordText,
            'audioPath': wordAudioPath,
          },
        );
      } catch (e) {
        await _logger.error(
          'Failed to generate word audio: $e',
          eventType: 'word_audio_failed',
          metadata: {'wordId': wordId, 'word': wordText, 'error': e.toString()},
        );
        // Continue with sample phrases even if word audio fails
      }

      // Generate audio for sample phrases
      final phraseAudioPaths = <String>[];
      if (samplePhrases != null && samplePhrases.isNotEmpty) {
        for (var i = 0; i < samplePhrases.length; i++) {
          final phrase = samplePhrases[i];
          if (phrase.isEmpty) continue;

          try {
            await _logger.info(
              'Generating audio for sample phrase',
              eventType: 'phrase_audio_start',
              metadata: {
                'wordId': wordId,
                'phraseIndex': i,
                'phrasePreview': phrase.length > 50
                    ? '${phrase.substring(0, 50)}...'
                    : phrase,
              },
            );

            final phraseAudioFile = await audioService.generateAudioForApp(
              text: phrase,
              filename: '${wordText}_phrase_${i + 1}',
              appId: 'vocabulary',
            );
            phraseAudioPaths.add(phraseAudioFile.relativePath);

            await _logger.info(
              'Successfully generated phrase audio',
              eventType: 'phrase_audio_success',
              metadata: {
                'wordId': wordId,
                'phraseIndex': i,
                'audioPath': phraseAudioFile.relativePath,
              },
            );
          } catch (e) {
            await _logger.error(
              'Failed to generate phrase audio: $e',
              eventType: 'phrase_audio_failed',
              metadata: {
                'wordId': wordId,
                'phraseIndex': i,
                'error': e.toString(),
              },
            );
            // Add empty string to maintain index alignment
            phraseAudioPaths.add('');
          }
        }
      }

      // Update word with audio paths
      await VocabularyStorage.instance.updateWordAudio(
        wordId,
        wordAudioPath: wordAudioPath,
        sampleAudioPaths: phraseAudioPaths,
      );

      await _logger.info(
        'Successfully updated word with audio paths',
        eventType: 'audio_save',
        metadata: {
          'wordId': wordId,
          'word': wordText,
          'hasWordAudio': wordAudioPath != null,
          'phrasesCount': phraseAudioPaths.length,
        },
      );

      return true;
    } catch (e, stackTrace) {
      await _logger.error(
        'Error processing vocabulary audio message: $e',
        eventType: 'message_error',
        metadata: {
          'messageId': message.id,
          'error': e.toString(),
          'stackTrace': stackTrace.toString().split('\n').take(5).join('\n'),
        },
      );
      return false; // Will retry
    }
  }

  /// Dispose the service
  void dispose() {
    stop();
    _logger.info(
      'Vocabulary audio service disposed',
      eventType: 'service_dispose',
    );
  }

  /// Reset instance for testing
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }
}
