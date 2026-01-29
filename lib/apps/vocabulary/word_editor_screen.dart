import 'dart:async';

import 'package:flutter/material.dart';

import 'models/word.dart';
import 'services/vocabulary_storage.dart';
import 'services/vocabulary_streaming_service.dart';

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
              decoration: const InputDecoration(
                labelText: 'Word',
                hintText: 'Enter the word',
                border: OutlineInputBorder(),
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
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _phraseControllers[index],
                    decoration: InputDecoration(
                      labelText: 'Phrase ${index + 1}',
                      border: const OutlineInputBorder(),
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
