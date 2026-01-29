class Message {
  final String id;
  final String chatId;
  final String content;
  final bool isUser;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.chatId,
    required this.content,
    required this.isUser,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chatId': chatId,
      'content': content,
      'isUser': isUser ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      chatId: map['chatId'] as String,
      content: map['content'] as String,
      isUser: (map['isUser'] as int) == 1,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  Message copyWith({
    String? id,
    String? chatId,
    String? content,
    bool? isUser,
    DateTime? createdAt,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
