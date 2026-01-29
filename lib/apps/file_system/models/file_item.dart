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
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
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
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
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
    );
  }
}
