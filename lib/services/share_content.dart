/// Content types that can be shared between apps
enum ShareContentType {
  text, // Plain text (word, phrase, snippet)
  note, // Full note with title/body
  file, // File reference (path, name, metadata)
  url, // URL/link
  json, // Structured data (for advanced use cases)
}

/// Represents content that can be shared from one app to another
class ShareContent {
  /// Unique identifier for this share instance
  final String id;

  /// The type of content being shared
  final ShareContentType type;

  /// The app ID that is sharing this content
  final String sourceAppId;

  /// The data payload (structure depends on type)
  final Map<String, dynamic> data;

  /// When this share was created
  final DateTime timestamp;

  ShareContent({
    required this.id,
    required this.type,
    required this.sourceAppId,
    required this.data,
    required this.timestamp,
  });

  /// Create a new ShareContent with auto-generated ID and timestamp
  factory ShareContent.create({
    required ShareContentType type,
    required String sourceAppId,
    required Map<String, dynamic> data,
  }) {
    return ShareContent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      sourceAppId: sourceAppId,
      data: data,
      timestamp: DateTime.now(),
    );
  }

  /// Create text content
  factory ShareContent.text({
    required String sourceAppId,
    required String text,
  }) {
    return ShareContent.create(
      type: ShareContentType.text,
      sourceAppId: sourceAppId,
      data: {'text': text},
    );
  }

  /// Create note content
  factory ShareContent.note({
    required String sourceAppId,
    required String title,
    required String body,
    String format = 'markdown',
  }) {
    return ShareContent.create(
      type: ShareContentType.note,
      sourceAppId: sourceAppId,
      data: {'title': title, 'body': body, 'format': format},
    );
  }

  /// Create file content
  factory ShareContent.file({
    required String sourceAppId,
    required String path,
    required String name,
    String? mimeType,
  }) {
    return ShareContent.create(
      type: ShareContentType.file,
      sourceAppId: sourceAppId,
      data: {'path': path, 'name': name, 'mimeType': mimeType ?? ''},
    );
  }

  /// Create URL content
  factory ShareContent.url({
    required String sourceAppId,
    required String url,
    String? title,
  }) {
    return ShareContent.create(
      type: ShareContentType.url,
      sourceAppId: sourceAppId,
      data: {'url': url, 'title': title ?? ''},
    );
  }

  /// Create JSON content
  factory ShareContent.json({
    required String sourceAppId,
    required Map<String, dynamic> data,
    String? schema,
  }) {
    return ShareContent.create(
      type: ShareContentType.json,
      sourceAppId: sourceAppId,
      data: {'data': data, 'schema': schema ?? ''},
    );
  }

  @override
  String toString() {
    return 'ShareContent(id: $id, type: $type, sourceAppId: $sourceAppId)';
  }
}
