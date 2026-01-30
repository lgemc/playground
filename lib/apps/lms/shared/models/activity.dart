enum ActivityType {
  resourceFile,
  quiz, // Future implementation
}

enum ResourceType {
  lecture,
  audio,
  video,
  document,
  other,
}

abstract class Activity {
  final String id;
  final String subSectionId;
  final String name;
  final String? description;
  final DateTime createdAt;
  final int order;
  final ActivityType type;

  Activity({
    required this.id,
    required this.subSectionId,
    required this.name,
    this.description,
    required this.createdAt,
    required this.order,
    required this.type,
  });

  Map<String, dynamic> toJson();

  static Activity fromJson(Map<String, dynamic> json) {
    final type = ActivityType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => ActivityType.resourceFile,
    );

    switch (type) {
      case ActivityType.resourceFile:
        return ResourceFileActivity.fromJson(json);
      case ActivityType.quiz:
        // Future: return QuizActivity.fromJson(json);
        throw UnimplementedError('Quiz activities not yet implemented');
    }
  }

  Activity copyWith({
    String? id,
    String? subSectionId,
    String? name,
    String? description,
    DateTime? createdAt,
    int? order,
  });
}

class ResourceFileActivity extends Activity {
  final String? fileId;
  final ResourceType resourceType;

  ResourceFileActivity({
    required super.id,
    required super.subSectionId,
    required super.name,
    super.description,
    required super.createdAt,
    required super.order,
    this.fileId,
    required this.resourceType,
  }) : super(type: ActivityType.resourceFile);

  factory ResourceFileActivity.create({
    required String subSectionId,
    required String name,
    String? description,
    required int order,
    String? fileId,
    required ResourceType resourceType,
  }) {
    final now = DateTime.now();
    return ResourceFileActivity(
      id: now.millisecondsSinceEpoch.toString(),
      subSectionId: subSectionId,
      name: name,
      description: description,
      createdAt: now,
      order: order,
      fileId: fileId,
      resourceType: resourceType,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'subSectionId': subSectionId,
      'name': name,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'order': order,
      'type': type.name,
      'fileId': fileId,
      'resourceType': resourceType.name,
    };
  }

  factory ResourceFileActivity.fromJson(Map<String, dynamic> json) {
    return ResourceFileActivity(
      id: json['id'] as String,
      subSectionId: json['subSectionId'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      order: json['order'] as int,
      fileId: json['fileId'] as String?,
      resourceType: ResourceType.values.firstWhere(
        (t) => t.name == json['resourceType'],
        orElse: () => ResourceType.other,
      ),
    );
  }

  @override
  ResourceFileActivity copyWith({
    String? id,
    String? subSectionId,
    String? name,
    String? description,
    DateTime? createdAt,
    int? order,
    String? fileId,
    ResourceType? resourceType,
  }) {
    return ResourceFileActivity(
      id: id ?? this.id,
      subSectionId: subSectionId ?? this.subSectionId,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      order: order ?? this.order,
      fileId: fileId ?? this.fileId,
      resourceType: resourceType ?? this.resourceType,
    );
  }
}
