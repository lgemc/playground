/// Result type for global search
enum SearchResultType {
  file,
  note,
  vocabularyWord,
  chat,
  chatMessage,
}

/// A search result that can come from any app
class SearchResult {
  /// Unique identifier for the result
  final String id;

  /// The type of result
  final SearchResultType type;

  /// App ID that owns this result
  final String appId;

  /// Title or primary text to display
  final String title;

  /// Optional subtitle or secondary text
  final String? subtitle;

  /// Optional preview of content
  final String? preview;

  /// Navigation data (app-specific)
  final Map<String, dynamic> navigationData;

  /// Creation or modification date
  final DateTime? timestamp;

  SearchResult({
    required this.id,
    required this.type,
    required this.appId,
    required this.title,
    this.subtitle,
    this.preview,
    required this.navigationData,
    this.timestamp,
  });

  /// Display label for the result type
  String get typeLabel {
    switch (type) {
      case SearchResultType.file:
        return 'File';
      case SearchResultType.note:
        return 'Note';
      case SearchResultType.vocabularyWord:
        return 'Vocabulary';
      case SearchResultType.chat:
        return 'Chat';
      case SearchResultType.chatMessage:
        return 'Message';
    }
  }
}
