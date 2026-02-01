import 'package:uuid/uuid.dart';
import '../../../../core/app_bus.dart';
import '../../../../core/app_event.dart';
import '../../../../core/sync/services/device_id_service.dart';
import '../../../../core/database/crdt_database.dart';
import '../models/activity.dart';
import '../models/course.dart';
import '../models/lesson_module.dart';
import '../models/lesson_sub_section.dart';

/// Event types emitted by LMS storage (snake_case, infinitive verbs)
class LmsEvents {
  static const String courseCreate = 'lms.course.create';
  static const String courseUpdate = 'lms.course.update';
  static const String courseDelete = 'lms.course.delete';
  static const String moduleCreate = 'lms.module.create';
  static const String moduleUpdate = 'lms.module.update';
  static const String moduleDelete = 'lms.module.delete';
  static const String subsectionCreate = 'lms.subsection.create';
  static const String subsectionUpdate = 'lms.subsection.update';
  static const String subsectionDelete = 'lms.subsection.delete';
  static const String activityCreate = 'lms.activity.create';
  static const String activityUpdate = 'lms.activity.update';
  static const String activityDelete = 'lms.activity.delete';
}

/// LMS storage using shared CRDT database
class LmsCrdtStorageService {
  static LmsCrdtStorageService? _instance;
  static LmsCrdtStorageService get instance => _instance ??= LmsCrdtStorageService._();

  LmsCrdtStorageService._();

  String? _deviceId;

  Future<String> get deviceId async {
    _deviceId ??= await DeviceIdService.instance.getDeviceId();
    return _deviceId!;
  }

  // === Course Operations ===

  Future<List<Course>> loadCourses() async {
    final rows = await CrdtDatabase.instance.query(
      'SELECT * FROM lms_courses WHERE deleted_at IS NULL ORDER BY updated_at DESC',
    );

    final courses = <Course>[];
    for (final row in rows) {
      final courseId = row['id'] as String;
      final modules = await _loadModulesForCourse(courseId);
      courses.add(_toCourse(row, modules));
    }

    return courses;
  }

  Future<Course?> getCourse(String courseId) async {
    final rows = await CrdtDatabase.instance.query(
      'SELECT * FROM lms_courses WHERE id = ? AND deleted_at IS NULL',
      [courseId],
    );

    if (rows.isEmpty) return null;

    final modules = await _loadModulesForCourse(courseId);
    return _toCourse(rows.first, modules);
  }

  Course _toCourse(Map<String, Object?> row, List<LessonModule> modules) {
    return Course(
      id: row['id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      thumbnailFileId: row['thumbnail_file_id'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      modules: modules,
    );
  }

  Future<void> saveCourse(Course course) async {
    final devId = await deviceId;
    final now = DateTime.now();

    // Check if course exists
    final existingRows = await CrdtDatabase.instance.query(
      'SELECT * FROM lms_courses WHERE id = ?',
      [course.id],
    );
    final isNew = existingRows.isEmpty;

    final courseId = course.id.isEmpty ? const Uuid().v4() : course.id;

    if (isNew) {
      // Insert new course
      await CrdtDatabase.instance.execute(
        '''INSERT INTO lms_courses
           (id, name, description, thumbnail_file_id, created_at, updated_at, deleted_at, device_id, sync_version)
           VALUES (?, ?, ?, ?, ?, ?, NULL, ?, 1)''',
        [
          courseId,
          course.name,
          course.description,
          course.thumbnailFileId,
          course.createdAt.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch,
          devId,
        ],
      );
    } else {
      // Update existing course
      final currentVersion = existingRows.first['sync_version'] as int;
      await CrdtDatabase.instance.execute(
        '''UPDATE lms_courses
           SET name = ?, description = ?, thumbnail_file_id = ?, updated_at = ?, device_id = ?, sync_version = ?
           WHERE id = ?''',
        [
          course.name,
          course.description,
          course.thumbnailFileId,
          now.millisecondsSinceEpoch,
          devId,
          currentVersion + 1,
          course.id,
        ],
      );
    }

    // Emit event to app bus
    await AppBus.instance.emit(AppEvent.create(
      type: isNew ? LmsEvents.courseCreate : LmsEvents.courseUpdate,
      appId: 'lms',
      metadata: {
        'courseId': courseId,
        'courseName': course.name,
      },
    ));
  }

  Future<void> deleteCourse(String courseId) async {
    final devId = await deviceId;
    final now = DateTime.now();

    // Get current sync version
    final rows = await CrdtDatabase.instance.query(
      'SELECT sync_version FROM lms_courses WHERE id = ?',
      [courseId],
    );
    if (rows.isEmpty) return;

    final currentVersion = rows.first['sync_version'] as int;

    // Soft delete course
    await CrdtDatabase.instance.execute(
      '''UPDATE lms_courses
         SET deleted_at = ?, updated_at = ?, device_id = ?, sync_version = ?
         WHERE id = ?''',
      [
        now.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
        devId,
        currentVersion + 1,
        courseId,
      ],
    );

    // Soft delete all modules for this course
    await CrdtDatabase.instance.execute(
      '''UPDATE lms_modules
         SET deleted_at = ?, updated_at = ?, device_id = ?, sync_version = sync_version + 1
         WHERE course_id = ? AND deleted_at IS NULL''',
      [
        now.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
        devId,
        courseId,
      ],
    );

    // Emit event
    await AppBus.instance.emit(AppEvent.create(
      type: LmsEvents.courseDelete,
      appId: 'lms',
      metadata: {'courseId': courseId},
    ));
  }

  // === Module Operations ===

  Future<List<LessonModule>> _loadModulesForCourse(String courseId) async {
    final rows = await CrdtDatabase.instance.query(
      'SELECT * FROM lms_modules WHERE course_id = ? AND deleted_at IS NULL ORDER BY "order"',
      [courseId],
    );

    final modules = <LessonModule>[];
    for (final row in rows) {
      final moduleId = row['id'] as String;
      final subsections = await _loadSubsectionsForModule(moduleId);
      modules.add(_toModule(row, subsections));
    }

    return modules;
  }

  LessonModule _toModule(Map<String, Object?> row, List<LessonSubSection> subsections) {
    return LessonModule(
      id: row['id'] as String,
      courseId: row['course_id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      order: row['order'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      subSections: subsections,
    );
  }

  Future<void> saveModule(String courseId, LessonModule module) async {
    final devId = await deviceId;
    final now = DateTime.now();

    // Check if module exists
    final existingRows = await CrdtDatabase.instance.query(
      'SELECT * FROM lms_modules WHERE id = ?',
      [module.id],
    );
    final isNew = existingRows.isEmpty;

    final moduleId = module.id.isEmpty ? const Uuid().v4() : module.id;

    if (isNew) {
      // Insert new module
      await CrdtDatabase.instance.execute(
        '''INSERT INTO lms_modules
           (id, course_id, name, description, "order", created_at, updated_at, deleted_at, device_id, sync_version)
           VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?, 1)''',
        [
          moduleId,
          courseId,
          module.name,
          module.description,
          module.order,
          module.createdAt.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch,
          devId,
        ],
      );
    } else {
      // Update existing module
      final currentVersion = existingRows.first['sync_version'] as int;
      await CrdtDatabase.instance.execute(
        '''UPDATE lms_modules
           SET name = ?, description = ?, "order" = ?, updated_at = ?, device_id = ?, sync_version = ?
           WHERE id = ?''',
        [
          module.name,
          module.description,
          module.order,
          now.millisecondsSinceEpoch,
          devId,
          currentVersion + 1,
          module.id,
        ],
      );
    }

    // Update course updated_at
    await _touchCourse(courseId);

    // Emit event
    await AppBus.instance.emit(AppEvent.create(
      type: isNew ? LmsEvents.moduleCreate : LmsEvents.moduleUpdate,
      appId: 'lms',
      metadata: {
        'courseId': courseId,
        'moduleId': moduleId,
        'moduleName': module.name,
      },
    ));
  }

  Future<void> deleteModule(String courseId, String moduleId) async {
    final devId = await deviceId;
    final now = DateTime.now();

    // Get current sync version
    final rows = await CrdtDatabase.instance.query(
      'SELECT sync_version FROM lms_modules WHERE id = ?',
      [moduleId],
    );
    if (rows.isEmpty) return;

    final currentVersion = rows.first['sync_version'] as int;

    // Soft delete module
    await CrdtDatabase.instance.execute(
      '''UPDATE lms_modules
         SET deleted_at = ?, updated_at = ?, device_id = ?, sync_version = ?
         WHERE id = ?''',
      [
        now.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
        devId,
        currentVersion + 1,
        moduleId,
      ],
    );

    // Soft delete all subsections for this module
    await CrdtDatabase.instance.execute(
      '''UPDATE lms_subsections
         SET deleted_at = ?, updated_at = ?, device_id = ?, sync_version = sync_version + 1
         WHERE module_id = ? AND deleted_at IS NULL''',
      [
        now.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
        devId,
        moduleId,
      ],
    );

    // Update course updated_at
    await _touchCourse(courseId);

    // Emit event
    await AppBus.instance.emit(AppEvent.create(
      type: LmsEvents.moduleDelete,
      appId: 'lms',
      metadata: {
        'courseId': courseId,
        'moduleId': moduleId,
      },
    ));
  }

  Future<void> reorderModules(String courseId, List<String> moduleIds) async {
    for (var i = 0; i < moduleIds.length; i++) {
      final rows = await CrdtDatabase.instance.query(
        'SELECT * FROM lms_modules WHERE id = ?',
        [moduleIds[i]],
      );

      if (rows.isNotEmpty) {
        final currentVersion = rows.first['sync_version'] as int;
        final devId = await deviceId;

        await CrdtDatabase.instance.execute(
          '''UPDATE lms_modules
             SET "order" = ?, updated_at = ?, device_id = ?, sync_version = ?
             WHERE id = ?''',
          [
            i,
            DateTime.now().millisecondsSinceEpoch,
            devId,
            currentVersion + 1,
            moduleIds[i],
          ],
        );
      }
    }

    await _touchCourse(courseId);
  }

  // === SubSection Operations ===

  Future<List<LessonSubSection>> _loadSubsectionsForModule(String moduleId) async {
    final rows = await CrdtDatabase.instance.query(
      'SELECT * FROM lms_subsections WHERE module_id = ? AND deleted_at IS NULL ORDER BY "order"',
      [moduleId],
    );

    final subsections = <LessonSubSection>[];
    for (final row in rows) {
      final subsectionId = row['id'] as String;
      final activities = await _loadActivitiesForSubsection(subsectionId);
      subsections.add(_toSubSection(row, activities));
    }

    return subsections;
  }

  LessonSubSection _toSubSection(Map<String, Object?> row, List<Activity> activities) {
    return LessonSubSection(
      id: row['id'] as String,
      moduleId: row['module_id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      order: row['order'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      activities: activities,
    );
  }

  Future<void> saveSubSection(
    String courseId,
    String moduleId,
    LessonSubSection subSection,
  ) async {
    final devId = await deviceId;
    final now = DateTime.now();

    // Check if subsection exists
    final existingRows = await CrdtDatabase.instance.query(
      'SELECT * FROM lms_subsections WHERE id = ?',
      [subSection.id],
    );
    final isNew = existingRows.isEmpty;

    final subsectionId = subSection.id.isEmpty ? const Uuid().v4() : subSection.id;

    if (isNew) {
      // Insert new subsection
      await CrdtDatabase.instance.execute(
        '''INSERT INTO lms_subsections
           (id, module_id, name, description, "order", created_at, updated_at, deleted_at, device_id, sync_version)
           VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?, 1)''',
        [
          subsectionId,
          moduleId,
          subSection.name,
          subSection.description,
          subSection.order,
          subSection.createdAt.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch,
          devId,
        ],
      );
    } else {
      // Update existing subsection
      final currentVersion = existingRows.first['sync_version'] as int;
      await CrdtDatabase.instance.execute(
        '''UPDATE lms_subsections
           SET name = ?, description = ?, "order" = ?, updated_at = ?, device_id = ?, sync_version = ?
           WHERE id = ?''',
        [
          subSection.name,
          subSection.description,
          subSection.order,
          now.millisecondsSinceEpoch,
          devId,
          currentVersion + 1,
          subSection.id,
        ],
      );
    }

    // Update course updated_at
    await _touchCourse(courseId);

    // Emit event
    await AppBus.instance.emit(AppEvent.create(
      type: isNew ? LmsEvents.subsectionCreate : LmsEvents.subsectionUpdate,
      appId: 'lms',
      metadata: {
        'courseId': courseId,
        'moduleId': moduleId,
        'subsectionId': subsectionId,
        'subsectionName': subSection.name,
      },
    ));
  }

  Future<void> deleteSubSection(
    String courseId,
    String moduleId,
    String subSectionId,
  ) async {
    final devId = await deviceId;
    final now = DateTime.now();

    // Get current sync version
    final rows = await CrdtDatabase.instance.query(
      'SELECT sync_version FROM lms_subsections WHERE id = ?',
      [subSectionId],
    );
    if (rows.isEmpty) return;

    final currentVersion = rows.first['sync_version'] as int;

    // Soft delete subsection
    await CrdtDatabase.instance.execute(
      '''UPDATE lms_subsections
         SET deleted_at = ?, updated_at = ?, device_id = ?, sync_version = ?
         WHERE id = ?''',
      [
        now.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
        devId,
        currentVersion + 1,
        subSectionId,
      ],
    );

    // Soft delete all activities for this subsection
    await CrdtDatabase.instance.execute(
      '''UPDATE lms_activities
         SET deleted_at = ?, updated_at = ?, device_id = ?, sync_version = sync_version + 1
         WHERE subsection_id = ? AND deleted_at IS NULL''',
      [
        now.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
        devId,
        subSectionId,
      ],
    );

    // Update course updated_at
    await _touchCourse(courseId);

    // Emit event
    await AppBus.instance.emit(AppEvent.create(
      type: LmsEvents.subsectionDelete,
      appId: 'lms',
      metadata: {
        'courseId': courseId,
        'moduleId': moduleId,
        'subsectionId': subSectionId,
      },
    ));
  }

  Future<void> reorderSubSections(
    String courseId,
    String moduleId,
    List<String> subSectionIds,
  ) async {
    for (var i = 0; i < subSectionIds.length; i++) {
      final rows = await CrdtDatabase.instance.query(
        'SELECT * FROM lms_subsections WHERE id = ?',
        [subSectionIds[i]],
      );

      if (rows.isNotEmpty) {
        final currentVersion = rows.first['sync_version'] as int;
        final devId = await deviceId;

        await CrdtDatabase.instance.execute(
          '''UPDATE lms_subsections
             SET "order" = ?, updated_at = ?, device_id = ?, sync_version = ?
             WHERE id = ?''',
          [
            i,
            DateTime.now().millisecondsSinceEpoch,
            devId,
            currentVersion + 1,
            subSectionIds[i],
          ],
        );
      }
    }

    await _touchCourse(courseId);
  }

  // === Activity Operations ===

  Future<List<Activity>> _loadActivitiesForSubsection(String subsectionId) async {
    final rows = await CrdtDatabase.instance.query(
      'SELECT * FROM lms_activities WHERE subsection_id = ? AND deleted_at IS NULL ORDER BY "order"',
      [subsectionId],
    );

    return rows.map(_toActivity).toList();
  }

  Activity _toActivity(Map<String, Object?> row) {
    final typeStr = row['type'] as String;
    final type = ActivityType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => ActivityType.resourceFile,
    );

    if (type == ActivityType.resourceFile) {
      final resourceTypeStr = row['resource_type'] as String?;
      final resourceType = resourceTypeStr != null
          ? ResourceType.values.firstWhere(
              (t) => t.name == resourceTypeStr,
              orElse: () => ResourceType.other,
            )
          : ResourceType.other;

      return ResourceFileActivity(
        id: row['id'] as String,
        subSectionId: row['subsection_id'] as String,
        name: row['name'] as String,
        description: row['description'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        order: row['order'] as int,
        fileId: row['file_id'] as String?,
        resourceType: resourceType,
      );
    }

    throw UnimplementedError('Activity type $type not yet implemented');
  }

  Future<void> saveActivity(
    String courseId,
    String moduleId,
    String subSectionId,
    Activity activity,
  ) async {
    final devId = await deviceId;
    final now = DateTime.now();

    // Check if activity exists
    final existingRows = await CrdtDatabase.instance.query(
      'SELECT * FROM lms_activities WHERE id = ?',
      [activity.id],
    );
    final isNew = existingRows.isEmpty;

    final activityId = activity.id.isEmpty ? const Uuid().v4() : activity.id;

    // Get activity-specific fields
    String? fileId;
    String? resourceType;
    if (activity is ResourceFileActivity) {
      fileId = activity.fileId;
      resourceType = activity.resourceType.name;
    }

    if (isNew) {
      // Insert new activity
      await CrdtDatabase.instance.execute(
        '''INSERT INTO lms_activities
           (id, subsection_id, name, description, type, "order", file_id, resource_type, created_at, updated_at, deleted_at, device_id, sync_version)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, 1)''',
        [
          activityId,
          subSectionId,
          activity.name,
          activity.description,
          activity.type.name,
          activity.order,
          fileId,
          resourceType,
          activity.createdAt.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch,
          devId,
        ],
      );
    } else {
      // Update existing activity
      final currentVersion = existingRows.first['sync_version'] as int;
      await CrdtDatabase.instance.execute(
        '''UPDATE lms_activities
           SET name = ?, description = ?, "order" = ?, file_id = ?, resource_type = ?, updated_at = ?, device_id = ?, sync_version = ?
           WHERE id = ?''',
        [
          activity.name,
          activity.description,
          activity.order,
          fileId,
          resourceType,
          now.millisecondsSinceEpoch,
          devId,
          currentVersion + 1,
          activity.id,
        ],
      );
    }

    // Update course updated_at
    await _touchCourse(courseId);

    // Emit event
    await AppBus.instance.emit(AppEvent.create(
      type: isNew ? LmsEvents.activityCreate : LmsEvents.activityUpdate,
      appId: 'lms',
      metadata: {
        'courseId': courseId,
        'moduleId': moduleId,
        'subsectionId': subSectionId,
        'activityId': activityId,
        'activityName': activity.name,
      },
    ));
  }

  Future<void> deleteActivity(
    String courseId,
    String moduleId,
    String subSectionId,
    String activityId,
  ) async {
    final devId = await deviceId;
    final now = DateTime.now();

    // Get current sync version
    final rows = await CrdtDatabase.instance.query(
      'SELECT sync_version FROM lms_activities WHERE id = ?',
      [activityId],
    );
    if (rows.isEmpty) return;

    final currentVersion = rows.first['sync_version'] as int;

    // Soft delete activity
    await CrdtDatabase.instance.execute(
      '''UPDATE lms_activities
         SET deleted_at = ?, updated_at = ?, device_id = ?, sync_version = ?
         WHERE id = ?''',
      [
        now.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
        devId,
        currentVersion + 1,
        activityId,
      ],
    );

    // Update course updated_at
    await _touchCourse(courseId);

    // Emit event
    await AppBus.instance.emit(AppEvent.create(
      type: LmsEvents.activityDelete,
      appId: 'lms',
      metadata: {
        'courseId': courseId,
        'moduleId': moduleId,
        'subsectionId': subSectionId,
        'activityId': activityId,
      },
    ));
  }

  Future<void> reorderActivities(
    String courseId,
    String moduleId,
    String subSectionId,
    List<String> activityIds,
  ) async {
    for (var i = 0; i < activityIds.length; i++) {
      final rows = await CrdtDatabase.instance.query(
        'SELECT * FROM lms_activities WHERE id = ?',
        [activityIds[i]],
      );

      if (rows.isNotEmpty) {
        final currentVersion = rows.first['sync_version'] as int;
        final devId = await deviceId;

        await CrdtDatabase.instance.execute(
          '''UPDATE lms_activities
             SET "order" = ?, updated_at = ?, device_id = ?, sync_version = ?
             WHERE id = ?''',
          [
            i,
            DateTime.now().millisecondsSinceEpoch,
            devId,
            currentVersion + 1,
            activityIds[i],
          ],
        );
      }
    }

    await _touchCourse(courseId);
  }

  // === Helper Methods ===

  /// Update course's updated_at timestamp
  Future<void> _touchCourse(String courseId) async {
    final rows = await CrdtDatabase.instance.query(
      'SELECT sync_version FROM lms_courses WHERE id = ?',
      [courseId],
    );

    if (rows.isNotEmpty) {
      final currentVersion = rows.first['sync_version'] as int;
      final devId = await deviceId;

      await CrdtDatabase.instance.execute(
        '''UPDATE lms_courses
           SET updated_at = ?, device_id = ?, sync_version = ?
           WHERE id = ?''',
        [
          DateTime.now().millisecondsSinceEpoch,
          devId,
          currentVersion + 1,
          courseId,
        ],
      );
    }
  }

  /// Watch courses for reactive updates
  Stream<List<Course>> watchCourses() async* {
    await for (final rows in CrdtDatabase.instance.watch(
      'SELECT * FROM lms_courses WHERE deleted_at IS NULL ORDER BY updated_at DESC',
    )) {
      final courses = <Course>[];
      for (final row in rows) {
        final courseId = row['id'] as String;
        final modules = await _loadModulesForCourse(courseId);
        courses.add(_toCourse(row, modules));
      }
      yield courses;
    }
  }
}
