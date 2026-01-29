import 'lesson_sub_section.dart';

class LessonModule {
  final String id;
  final String courseId;
  final String name;
  final String? description;
  final int order;
  final DateTime createdAt;
  final List<LessonSubSection> subSections;

  LessonModule({
    required this.id,
    required this.courseId,
    required this.name,
    this.description,
    required this.order,
    required this.createdAt,
    this.subSections = const [],
  });

  factory LessonModule.create({
    required String courseId,
    required String name,
    String? description,
    required int order,
  }) {
    final now = DateTime.now();
    return LessonModule(
      id: now.millisecondsSinceEpoch.toString(),
      courseId: courseId,
      name: name,
      description: description,
      order: order,
      createdAt: now,
      subSections: [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'courseId': courseId,
      'name': name,
      'description': description,
      'order': order,
      'createdAt': createdAt.toIso8601String(),
      'subSections': subSections.map((s) => s.toJson()).toList(),
    };
  }

  factory LessonModule.fromJson(Map<String, dynamic> json) {
    final subSectionsJson = json['subSections'] as List<dynamic>? ?? [];
    return LessonModule(
      id: json['id'] as String,
      courseId: json['courseId'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      order: json['order'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      subSections: subSectionsJson
          .map((s) => LessonSubSection.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  LessonModule copyWith({
    String? id,
    String? courseId,
    String? name,
    String? description,
    int? order,
    DateTime? createdAt,
    List<LessonSubSection>? subSections,
  }) {
    return LessonModule(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      name: name ?? this.name,
      description: description ?? this.description,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      subSections: subSections ?? this.subSections,
    );
  }
}
