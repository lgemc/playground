class Chat {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  bool isTitleGenerating;

  Chat({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.isTitleGenerating = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isTitleGenerating': isTitleGenerating ? 1 : 0,
    };
  }

  factory Chat.fromMap(Map<String, dynamic> map) {
    return Chat(
      id: map['id'] as String,
      title: map['title'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      isTitleGenerating: (map['isTitleGenerating'] as int) == 1,
    );
  }

  Chat copyWith({
    String? title,
    DateTime? updatedAt,
    bool? isTitleGenerating,
  }) {
    return Chat(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isTitleGenerating: isTitleGenerating ?? this.isTitleGenerating,
    );
  }
}
