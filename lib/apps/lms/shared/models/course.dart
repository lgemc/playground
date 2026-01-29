import 'lesson_module.dart';

class Course {
  final String id;
  final String name;
  final String? description;
  final String? thumbnailFileId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<LessonModule> modules;

  Course({
    required this.id,
    required this.name,
    this.description,
    this.thumbnailFileId,
    required this.createdAt,
    required this.updatedAt,
    this.modules = const [],
  });

  factory Course.create({
    required String name,
    String? description,
    String? thumbnailFileId,
  }) {
    final now = DateTime.now();
    return Course(
      id: now.millisecondsSinceEpoch.toString(),
      name: name,
      description: description,
      thumbnailFileId: thumbnailFileId,
      createdAt: now,
      updatedAt: now,
      modules: [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'thumbnailFileId': thumbnailFileId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'modules': modules.map((m) => m.toJson()).toList(),
    };
  }

  factory Course.fromJson(Map<String, dynamic> json) {
    final modulesJson = json['modules'] as List<dynamic>? ?? [];
    return Course(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      thumbnailFileId: json['thumbnailFileId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      modules: modulesJson
          .map((m) => LessonModule.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }

  Course copyWith({
    String? id,
    String? name,
    String? description,
    String? thumbnailFileId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<LessonModule>? modules,
  }) {
    return Course(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      thumbnailFileId: thumbnailFileId ?? this.thumbnailFileId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      modules: modules ?? this.modules,
    );
  }

  int get totalModules => modules.length;

  int get totalSubSections =>
      modules.fold(0, (sum, m) => sum + m.subSections.length);

  int get totalActivities => modules.fold(
        0,
        (sum, m) =>
            sum + m.subSections.fold(0, (s, ss) => s + ss.activities.length),
      );
}
