/// A vocabulary word entry with meaning and sample phrases
class Word {
  final String id;
  final String word;
  final String meaning;
  final List<String> samplePhrases;
  final DateTime createdAt;
  final DateTime updatedAt;

  Word({
    required this.id,
    required this.word,
    required this.meaning,
    required this.samplePhrases,
    required this.createdAt,
    required this.updatedAt,
  });

  Word copyWith({
    String? id,
    String? word,
    String? meaning,
    List<String>? samplePhrases,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Word(
      id: id ?? this.id,
      word: word ?? this.word,
      meaning: meaning ?? this.meaning,
      samplePhrases: samplePhrases ?? this.samplePhrases,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Word.create({String word = ''}) {
    final now = DateTime.now();
    return Word(
      id: now.millisecondsSinceEpoch.toString(),
      word: word,
      meaning: '',
      samplePhrases: [],
      createdAt: now,
      updatedAt: now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'word': word,
      'meaning': meaning,
      'samplePhrases': samplePhrases,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Word.fromJson(Map<String, dynamic> json) {
    return Word(
      id: json['id'] as String,
      word: json['word'] as String,
      meaning: json['meaning'] as String? ?? '',
      samplePhrases: (json['samplePhrases'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}