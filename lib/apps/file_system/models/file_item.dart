class FileItem {
  final String id;
  final String name;
  final String relativePath;
  final String folderPath;
  final String? mimeType;
  final int size;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? contentHash;

  FileItem({
    required this.id,
    required this.name,
    required this.relativePath,
    required this.folderPath,
    this.mimeType,
    required this.size,
    required this.isFavorite,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.contentHash,
  });

  String get extension => name.contains('.') ? name.split('.').last : '';

  bool get isImage => mimeType?.startsWith('image/') == true;
  bool get isVideo => mimeType?.startsWith('video/') == true;
  bool get isAudio => mimeType?.startsWith('audio/') == true;
  bool get isDocument =>
      mimeType?.contains('pdf') == true ||
      mimeType?.contains('document') == true ||
      mimeType?.contains('text') == true;

  factory FileItem.fromMap(Map<String, dynamic> map) {
    return FileItem(
      id: map['id'] as String,
      name: map['name'] as String,
      relativePath: map['relative_path'] as String,
      folderPath: map['folder_path'] as String,
      mimeType: map['mime_type'] as String?,
      size: map['size'] as int,
      isFavorite: (map['is_favorite'] as int) == 1,
      createdAt: _parseTimestamp(map['created_at']),
      updatedAt: _parseTimestamp(map['updated_at']),
      deletedAt: map['deleted_at'] != null ? _parseTimestamp(map['deleted_at']) : null,
      contentHash: map['content_hash'] as String?,
    );
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is String) {
      return DateTime.parse(value);
    }
    throw ArgumentError('Invalid timestamp format: $value');
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'relative_path': relativePath,
      'folder_path': folderPath,
      'mime_type': mimeType,
      'size': size,
      'is_favorite': isFavorite ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
      'content_hash': contentHash,
    };
  }

  FileItem copyWith({
    String? id,
    String? name,
    String? relativePath,
    String? folderPath,
    String? mimeType,
    int? size,
    bool? isFavorite,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? contentHash,
  }) {
    return FileItem(
      id: id ?? this.id,
      name: name ?? this.name,
      relativePath: relativePath ?? this.relativePath,
      folderPath: folderPath ?? this.folderPath,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      contentHash: contentHash ?? this.contentHash,
    );
  }
}
