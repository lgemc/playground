class FolderItem {
  final String name;
  final String path;

  FolderItem({
    required this.name,
    required this.path,
  });

  String get parentPath {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) return '';
    return '${parts.sublist(0, parts.length - 1).join('/')}/';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FolderItem &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          path == other.path;

  @override
  int get hashCode => name.hashCode ^ path.hashCode;
}
