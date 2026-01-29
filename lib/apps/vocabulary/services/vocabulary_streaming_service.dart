import 'dart:async';

/// State of a word definition generation
enum DefinitionStreamState {
  idle,
  generating,
  completed,
  error,
}

/// Streaming update for a word definition
class DefinitionStreamUpdate {
  final String wordId;
  final DefinitionStreamState state;
  final String meaning;
  final List<String> examples;
  final String? error;

  const DefinitionStreamUpdate({
    required this.wordId,
    required this.state,
    this.meaning = '',
    this.examples = const [],
    this.error,
  });

  DefinitionStreamUpdate copyWith({
    DefinitionStreamState? state,
    String? meaning,
    List<String>? examples,
    String? error,
  }) {
    return DefinitionStreamUpdate(
      wordId: wordId,
      state: state ?? this.state,
      meaning: meaning ?? this.meaning,
      examples: examples ?? this.examples,
      error: error ?? this.error,
    );
  }
}

/// Service for broadcasting real-time definition streaming updates to the UI.
/// UI components can subscribe to updates for specific word IDs.
class VocabularyStreamingService {
  static VocabularyStreamingService? _instance;
  static VocabularyStreamingService get instance =>
      _instance ??= VocabularyStreamingService._();

  VocabularyStreamingService._();

  /// Active streams per word ID
  final Map<String, StreamController<DefinitionStreamUpdate>> _controllers = {};

  /// Current state per word ID
  final Map<String, DefinitionStreamUpdate> _currentState = {};

  /// Get the stream of updates for a specific word
  Stream<DefinitionStreamUpdate> streamFor(String wordId) {
    _controllers[wordId] ??= StreamController<DefinitionStreamUpdate>.broadcast();
    // Emit current state immediately if available
    final current = _currentState[wordId];
    if (current != null) {
      Future.microtask(() => _controllers[wordId]?.add(current));
    }
    return _controllers[wordId]!.stream;
  }

  /// Get current state for a word (synchronous)
  DefinitionStreamUpdate? getState(String wordId) => _currentState[wordId];

  /// Check if a word is currently generating
  bool isGenerating(String wordId) =>
      _currentState[wordId]?.state == DefinitionStreamState.generating;

  /// Start generation for a word
  void startGeneration(String wordId) {
    final update = DefinitionStreamUpdate(
      wordId: wordId,
      state: DefinitionStreamState.generating,
    );
    _emit(wordId, update);
  }

  /// Update meaning text (appends to existing)
  void appendMeaning(String wordId, String text) {
    final current = _currentState[wordId];
    if (current == null) return;

    final update = current.copyWith(
      meaning: current.meaning + text,
    );
    _emit(wordId, update);
  }

  /// Set complete meaning
  void setMeaning(String wordId, String meaning) {
    final current = _currentState[wordId];
    if (current == null) return;

    final update = current.copyWith(meaning: meaning);
    _emit(wordId, update);
  }

  /// Append to current example being streamed
  void appendExample(String wordId, int index, String text) {
    final current = _currentState[wordId];
    if (current == null) return;

    final examples = List<String>.from(current.examples);
    while (examples.length <= index) {
      examples.add('');
    }
    examples[index] = examples[index] + text;

    final update = current.copyWith(examples: examples);
    _emit(wordId, update);
  }

  /// Set a complete example
  void setExample(String wordId, int index, String example) {
    final current = _currentState[wordId];
    if (current == null) return;

    final examples = List<String>.from(current.examples);
    while (examples.length <= index) {
      examples.add('');
    }
    examples[index] = example;

    final update = current.copyWith(examples: examples);
    _emit(wordId, update);
  }

  /// Mark generation as completed
  void completeGeneration(String wordId, {String? meaning, List<String>? examples}) {
    final current = _currentState[wordId];
    final update = DefinitionStreamUpdate(
      wordId: wordId,
      state: DefinitionStreamState.completed,
      meaning: meaning ?? current?.meaning ?? '',
      examples: examples ?? current?.examples ?? [],
    );
    _emit(wordId, update);

    // Clean up after a short delay to allow UI to show final state
    Future.delayed(const Duration(seconds: 2), () {
      _cleanup(wordId);
    });
  }

  /// Mark generation as failed
  void failGeneration(String wordId, String error) {
    final update = DefinitionStreamUpdate(
      wordId: wordId,
      state: DefinitionStreamState.error,
      error: error,
    );
    _emit(wordId, update);

    // Clean up after showing error
    Future.delayed(const Duration(seconds: 5), () {
      _cleanup(wordId);
    });
  }

  void _emit(String wordId, DefinitionStreamUpdate update) {
    _currentState[wordId] = update;
    _controllers[wordId]?.add(update);
  }

  void _cleanup(String wordId) {
    _currentState.remove(wordId);
    _controllers[wordId]?.close();
    _controllers.remove(wordId);
  }

  /// Dispose all streams
  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
    _currentState.clear();
  }

  /// Reset instance for testing
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }
}
