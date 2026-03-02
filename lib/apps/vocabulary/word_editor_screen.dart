import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../services/logger.dart';
import '../../core/app_bus.dart';
import '../../core/app_event.dart';
import '../file_system/services/file_system_storage.dart';
import 'models/word.dart';
import 'services/vocabulary_storage.dart';
import 'services/vocabulary_streaming_service.dart';

final _logger = Logger(appId: 'vocabulary', appName: 'Vocabulary');

class WordEditorScreen extends StatefulWidget {
  final Word word;
  final bool isNew;

  const WordEditorScreen({
    super.key,
    required this.word,
    this.isNew = false,
  });

  @override
  State<WordEditorScreen> createState() => _WordEditorScreenState();
}

class _WordEditorScreenState extends State<WordEditorScreen> {
  late TextEditingController _wordController;
  late TextEditingController _meaningController;
  late List<TextEditingController> _phraseControllers;
  late String _originalWord;
  bool _hasChanges = false;
  bool _isSaving = false;
  Timer? _debounceTimer;

  // Streaming support
  StreamSubscription<DefinitionStreamUpdate>? _streamSubscription;
  bool _isGenerating = false;

  // Audio playback
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingPath;

  @override
  void initState() {
    super.initState();
    _wordController = TextEditingController(text: widget.word.word);
    _meaningController = TextEditingController(text: widget.word.meaning);
    _phraseControllers = widget.word.samplePhrases
        .map((phrase) => TextEditingController(text: phrase))
        .toList();
    _originalWord = widget.word.word;

    _wordController.addListener(_onChanged);
    _meaningController.addListener(_onChanged);
    for (final controller in _phraseControllers) {
      controller.addListener(_onChanged);
    }

    // Subscribe to streaming updates
    _subscribeToStreaming();
  }

  void _subscribeToStreaming() {
    final streaming = VocabularyStreamingService.instance;

    // Check if already generating
    final currentState = streaming.getState(widget.word.id);
    if (currentState?.state == DefinitionStreamState.generating) {
      _isGenerating = true;
    }

    _streamSubscription = streaming.streamFor(widget.word.id).listen((update) {
      if (!mounted) return;

      setState(() {
        _isGenerating = update.state == DefinitionStreamState.generating;
      });

      if (update.state == DefinitionStreamState.generating ||
          update.state == DefinitionStreamState.completed) {
        // Update meaning field with streamed content
        if (update.meaning.isNotEmpty &&
            _meaningController.text != update.meaning) {
          _meaningController.text = update.meaning;
        }

        // Update phrase controllers with streamed examples
        _updatePhraseControllers(update.examples);
      }
    });
  }

  void _updatePhraseControllers(List<String> examples) {
    // Add new controllers if we have more examples
    while (_phraseControllers.length < examples.length) {
      final controller = TextEditingController();
      controller.addListener(_onChanged);
      _phraseControllers.add(controller);
    }

    // Update existing controllers
    for (var i = 0; i < examples.length; i++) {
      if (_phraseControllers[i].text != examples[i]) {
        _phraseControllers[i].text = examples[i];
      }
    }

    // Rebuild UI if controllers were added
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _debounceTimer?.cancel();
    _audioPlayer.dispose();
    _wordController.removeListener(_onChanged);
    _wordController.dispose();
    _meaningController.removeListener(_onChanged);
    _meaningController.dispose();
    for (final controller in _phraseControllers) {
      controller.removeListener(_onChanged);
      controller.dispose();
    }
    if (_hasChanges) {
      _saveWord();
    }
    super.dispose();
  }

  Future<void> _playAudio(String relativePath) async {
    try {
      // Stop currently playing audio if any
      if (_currentlyPlayingPath != null) {
        await _audioPlayer.stop();
      }

      // Convert relative path to absolute path
      final storageDir = FileSystemStorage.instance.storageDir;
      final absolutePath = '${storageDir.path}/$relativePath';
      final file = File(absolutePath);

      if (await file.exists()) {
        await _audioPlayer.play(DeviceFileSource(absolutePath));
        setState(() {
          _currentlyPlayingPath = relativePath;
        });

        // Listen for completion to reset state
        _audioPlayer.onPlayerComplete.listen((_) {
          if (mounted) {
            setState(() {
              _currentlyPlayingPath = null;
            });
          }
        });
      } else {
        _logger.warning(
          'Audio file not found',
          eventType: 'audio_file_not_found',
          metadata: {'relativePath': relativePath, 'absolutePath': absolutePath},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Audio file not found')),
          );
        }
      }
    } catch (e) {
      _logger.error(
        'Error playing audio: $e',
        eventType: 'audio_playback_error',
        metadata: {'relativePath': relativePath, 'error': e.toString()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing audio: $e')),
        );
      }
    }
  }

  Future<void> _stopAudio() async {
    await _audioPlayer.stop();
    setState(() {
      _currentlyPlayingPath = null;
    });
  }

  Future<void> _generateAudio() async {
    if (widget.word.meaning.isEmpty || widget.word.samplePhrases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please generate meaning and sample phrases first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Emit audio generation event with only wordId
      await AppBus.instance.emit(AppEvent.create(
        type: 'vocabulary.audio_generate',
        appId: 'vocabulary',
        metadata: {
          'wordId': widget.word.id,
        },
      ));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio generation queued. Check back in a moment.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _logger.error(
        'Error queuing audio generation: $e',
        eventType: 'audio_generation_queue_error',
        metadata: {'wordId': widget.word.id, 'error': e.toString()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _onChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
    _scheduleSave();
  }

  void _scheduleSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), _saveWord);
  }

  Future<void> _saveWord() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final wordText = _wordController.text.trim();
      if (wordText.isEmpty) {
        setState(() => _isSaving = false);
        return;
      }

      final wordChanged = _originalWord != wordText;

      // Check for duplicates if the word text changed
      if (wordChanged) {
        final duplicate = await VocabularyStorage.instance.findDuplicateWord(
          wordText,
          excludeId: widget.word.id,
        );

        if (duplicate != null) {
          _logger.warning(
            'Duplicate word attempt: "$wordText" already exists',
            eventType: 'duplicate_word',
            metadata: {'attemptedWord': wordText, 'existingWordId': duplicate.id},
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Word "$wordText" already exists'),
                backgroundColor: Colors.orange,
              ),
            );
            setState(() => _isSaving = false);
          }
          return;
        }
      }

      final phrases = _phraseControllers
          .map((c) => c.text.trim())
          .where((p) => p.isNotEmpty)
          .toList();

      final updatedWord = widget.word.copyWith(
        word: wordText,
        meaning: _meaningController.text.trim(),
        samplePhrases: phrases,
        updatedAt: DateTime.now(),
      );

      await VocabularyStorage.instance.saveWord(
        updatedWord,
        wordChanged: wordChanged,
      );

      _originalWord = wordText;
      _hasChanges = false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving word: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) {
      Navigator.of(context).pop(true);
      return false;
    }

    _debounceTimer?.cancel();
    await _saveWord();
    if (mounted) {
      Navigator.of(context).pop(true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _onWillPop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _onWillPop,
          ),
          title: Text(widget.isNew ? 'New Word' : 'Edit Word'),
          actions: [
            // Generate audio button
            if (!widget.isNew && widget.word.meaning.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.volume_up),
                tooltip: 'Generate audio',
                onPressed: _generateAudio,
              ),
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_hasChanges)
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _saveWord,
              )
            else
              const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(Icons.check, color: Colors.green),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _wordController,
              decoration: InputDecoration(
                labelText: 'Word',
                hintText: 'Enter the word',
                border: const OutlineInputBorder(),
                suffixIcon: widget.word.wordAudioPath != null
                    ? IconButton(
                        icon: Icon(
                          _currentlyPlayingPath == widget.word.wordAudioPath
                              ? Icons.stop_circle
                              : Icons.play_circle,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        tooltip: _currentlyPlayingPath == widget.word.wordAudioPath
                            ? 'Stop audio'
                            : 'Play word pronunciation',
                        onPressed: () {
                          if (_currentlyPlayingPath == widget.word.wordAudioPath) {
                            _stopAudio();
                          } else {
                            _playAudio(widget.word.wordAudioPath!);
                          }
                        },
                      )
                    : null,
              ),
              style: Theme.of(context).textTheme.headlineSmall,
              textCapitalization: TextCapitalization.none,
              autofocus: widget.isNew,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _meaningController,
              decoration: InputDecoration(
                labelText: 'Meaning',
                hintText: 'Meaning will be auto-filled...',
                border: const OutlineInputBorder(),
                suffixIcon: _isGenerating
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      )
                    : widget.word.meaning.isEmpty && _meaningController.text.isEmpty
                        ? Tooltip(
                            message: 'Meaning will be filled automatically',
                            child: Icon(
                              Icons.auto_awesome,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          )
                        : null,
              ),
              maxLines: 5,
              minLines: 3,
              readOnly: _isGenerating,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  'Sample Phrases',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_isGenerating) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Generating...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ] else if (_phraseControllers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Tooltip(
                      message: 'Phrases will be filled automatically',
                      child: Icon(
                        Icons.auto_awesome,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_phraseControllers.isEmpty && !_isGenerating)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).hintColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Sample phrases will be automatically generated after saving the word.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).hintColor,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_phraseControllers.isNotEmpty)
              ...List.generate(_phraseControllers.length, (index) {
                final hasAudio = index < widget.word.sampleAudioPaths.length &&
                    widget.word.sampleAudioPaths[index].isNotEmpty;
                final audioPath = hasAudio ? widget.word.sampleAudioPaths[index] : null;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _phraseControllers[index],
                    decoration: InputDecoration(
                      labelText: 'Phrase ${index + 1}',
                      border: const OutlineInputBorder(),
                      suffixIcon: hasAudio
                          ? IconButton(
                              icon: Icon(
                                _currentlyPlayingPath == audioPath
                                    ? Icons.stop_circle
                                    : Icons.play_circle,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              tooltip: _currentlyPlayingPath == audioPath
                                  ? 'Stop audio'
                                  : 'Play phrase',
                              onPressed: () {
                                if (_currentlyPlayingPath == audioPath) {
                                  _stopAudio();
                                } else {
                                  _playAudio(audioPath!);
                                }
                              },
                            )
                          : null,
                    ),
                    minLines: 2,
                    maxLines: null,
                    readOnly: _isGenerating,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
