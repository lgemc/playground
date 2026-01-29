import 'activity.dart';

class LessonSubSection {
  final String id;
  final String moduleId;
  final String name;
  final String? description;
  final int order;
  final DateTime createdAt;
  final List<Activity> activities;

  LessonSubSection({
    required this.id,
    required this.moduleId,
    required this.name,
    this.description,
    required this.order,
    required this.createdAt,
    this.activities = const [],
  });

  factory LessonSubSection.create({
    required String moduleId,
    required String name,
    String? description,
    required int order,
  }) {
    final now = DateTime.now();
    return LessonSubSection(
      id: now.millisecondsSinceEpoch.toString(),
      moduleId: moduleId,
      name: name,
      description: description,
      order: order,
      createdAt: now,
      activities: [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'moduleId': moduleId,
      'name': name,
      'description': description,
      'order': order,
      'createdAt': createdAt.toIso8601String(),
      'activities': activities.map((a) => a.toJson()).toList(),
    };
  }

  factory LessonSubSection.fromJson(Map<String, dynamic> json) {
    final activitiesJson = json['activities'] as List<dynamic>? ?? [];
    return LessonSubSection(
      id: json['id'] as String,
      moduleId: json['moduleId'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      order: json['order'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      activities: activitiesJson
          .map((a) => Activity.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }

  LessonSubSection copyWith({
    String? id,
    String? moduleId,
    String? name,
    String? description,
    int? order,
    DateTime? createdAt,
    List<Activity>? activities,
  }) {
    return LessonSubSection(
      id: id ?? this.id,
      moduleId: moduleId ?? this.moduleId,
      name: name ?? this.name,
      description: description ?? this.description,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      activities: activities ?? this.activities,
    );
  }
}
