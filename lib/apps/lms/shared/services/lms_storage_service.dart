import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/activity.dart';
import '../models/course.dart';
import '../models/lesson_module.dart';
import '../models/lesson_sub_section.dart';

class LmsStorageService {
  static LmsStorageService? _instance;
  static LmsStorageService get instance => _instance ??= LmsStorageService._();

  LmsStorageService._();

  Directory? _dataDir;

  Future<Directory> get dataDir async {
    if (_dataDir != null) return _dataDir!;

    final appDir = await getApplicationDocumentsDirectory();
    _dataDir = Directory('${appDir.path}/data/lms');

    if (!await _dataDir!.exists()) {
      await _dataDir!.create(recursive: true);
    }

    return _dataDir!;
  }

  File _coursesFile(Directory dir) => File('${dir.path}/courses.json');

  // === Course Operations ===

  Future<List<Course>> loadCourses() async {
    final dir = await dataDir;
    final file = _coursesFile(dir);

    if (!await file.exists()) {
      return [];
    }

    final contents = await file.readAsString();
    final data = json.decode(contents) as Map<String, dynamic>;
    final coursesJson = data['courses'] as List<dynamic>? ?? [];

    return coursesJson
        .map((c) => Course.fromJson(c as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<Course?> getCourse(String courseId) async {
    final courses = await loadCourses();
    try {
      return courses.firstWhere((c) => c.id == courseId);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCourse(Course course) async {
    final courses = await loadCourses();
    final existingIndex = courses.indexWhere((c) => c.id == course.id);

    final updatedCourse = course.copyWith(updatedAt: DateTime.now());

    if (existingIndex >= 0) {
      courses[existingIndex] = updatedCourse;
    } else {
      courses.add(updatedCourse);
    }

    await _saveAll(courses);
  }

  Future<void> deleteCourse(String courseId) async {
    final courses = await loadCourses();
    courses.removeWhere((c) => c.id == courseId);
    await _saveAll(courses);
  }

  // === Module Operations ===

  Future<void> saveModule(String courseId, LessonModule module) async {
    final courses = await loadCourses();
    final courseIndex = courses.indexWhere((c) => c.id == courseId);

    if (courseIndex < 0) return;

    final course = courses[courseIndex];
    final modules = List<LessonModule>.from(course.modules);
    final existingIndex = modules.indexWhere((m) => m.id == module.id);

    if (existingIndex >= 0) {
      modules[existingIndex] = module;
    } else {
      modules.add(module);
    }

    courses[courseIndex] = course.copyWith(
      modules: modules,
      updatedAt: DateTime.now(),
    );

    await _saveAll(courses);
  }

  Future<void> deleteModule(String courseId, String moduleId) async {
    final courses = await loadCourses();
    final courseIndex = courses.indexWhere((c) => c.id == courseId);

    if (courseIndex < 0) return;

    final course = courses[courseIndex];
    final modules = List<LessonModule>.from(course.modules)
      ..removeWhere((m) => m.id == moduleId);

    courses[courseIndex] = course.copyWith(
      modules: modules,
      updatedAt: DateTime.now(),
    );

    await _saveAll(courses);
  }

  Future<void> reorderModules(String courseId, List<String> moduleIds) async {
    final courses = await loadCourses();
    final courseIndex = courses.indexWhere((c) => c.id == courseId);

    if (courseIndex < 0) return;

    final course = courses[courseIndex];
    final modules = List<LessonModule>.from(course.modules);

    final reorderedModules = <LessonModule>[];
    for (var i = 0; i < moduleIds.length; i++) {
      final module = modules.firstWhere((m) => m.id == moduleIds[i]);
      reorderedModules.add(module.copyWith(order: i));
    }

    courses[courseIndex] = course.copyWith(
      modules: reorderedModules,
      updatedAt: DateTime.now(),
    );

    await _saveAll(courses);
  }

  // === SubSection Operations ===

  Future<void> saveSubSection(
    String courseId,
    String moduleId,
    LessonSubSection subSection,
  ) async {
    final courses = await loadCourses();
    final courseIndex = courses.indexWhere((c) => c.id == courseId);

    if (courseIndex < 0) return;

    final course = courses[courseIndex];
    final moduleIndex = course.modules.indexWhere((m) => m.id == moduleId);

    if (moduleIndex < 0) return;

    final modules = List<LessonModule>.from(course.modules);
    final module = modules[moduleIndex];
    final subSections = List<LessonSubSection>.from(module.subSections);
    final existingIndex = subSections.indexWhere((s) => s.id == subSection.id);

    if (existingIndex >= 0) {
      subSections[existingIndex] = subSection;
    } else {
      subSections.add(subSection);
    }

    modules[moduleIndex] = module.copyWith(subSections: subSections);
    courses[courseIndex] = course.copyWith(
      modules: modules,
      updatedAt: DateTime.now(),
    );

    await _saveAll(courses);
  }

  Future<void> deleteSubSection(
    String courseId,
    String moduleId,
    String subSectionId,
  ) async {
    final courses = await loadCourses();
    final courseIndex = courses.indexWhere((c) => c.id == courseId);

    if (courseIndex < 0) return;

    final course = courses[courseIndex];
    final moduleIndex = course.modules.indexWhere((m) => m.id == moduleId);

    if (moduleIndex < 0) return;

    final modules = List<LessonModule>.from(course.modules);
    final module = modules[moduleIndex];
    final subSections = List<LessonSubSection>.from(module.subSections)
      ..removeWhere((s) => s.id == subSectionId);

    modules[moduleIndex] = module.copyWith(subSections: subSections);
    courses[courseIndex] = course.copyWith(
      modules: modules,
      updatedAt: DateTime.now(),
    );

    await _saveAll(courses);
  }

  Future<void> reorderSubSections(
    String courseId,
    String moduleId,
    List<String> subSectionIds,
  ) async {
    final courses = await loadCourses();
    final courseIndex = courses.indexWhere((c) => c.id == courseId);

    if (courseIndex < 0) return;

    final course = courses[courseIndex];
    final moduleIndex = course.modules.indexWhere((m) => m.id == moduleId);

    if (moduleIndex < 0) return;

    final modules = List<LessonModule>.from(course.modules);
    final module = modules[moduleIndex];
    final subSections = List<LessonSubSection>.from(module.subSections);

    final reorderedSubSections = <LessonSubSection>[];
    for (var i = 0; i < subSectionIds.length; i++) {
      final subSection = subSections.firstWhere((s) => s.id == subSectionIds[i]);
      reorderedSubSections.add(subSection.copyWith(order: i));
    }

    modules[moduleIndex] = module.copyWith(subSections: reorderedSubSections);
    courses[courseIndex] = course.copyWith(
      modules: modules,
      updatedAt: DateTime.now(),
    );

    await _saveAll(courses);
  }

  // === Activity Operations ===

  Future<void> saveActivity(
    String courseId,
    String moduleId,
    String subSectionId,
    Activity activity,
  ) async {
    final courses = await loadCourses();
    final courseIndex = courses.indexWhere((c) => c.id == courseId);

    if (courseIndex < 0) return;

    final course = courses[courseIndex];
    final moduleIndex = course.modules.indexWhere((m) => m.id == moduleId);

    if (moduleIndex < 0) return;

    final modules = List<LessonModule>.from(course.modules);
    final module = modules[moduleIndex];
    final subSectionIndex =
        module.subSections.indexWhere((s) => s.id == subSectionId);

    if (subSectionIndex < 0) return;

    final subSections = List<LessonSubSection>.from(module.subSections);
    final subSection = subSections[subSectionIndex];
    final activities = List<Activity>.from(subSection.activities);
    final existingIndex = activities.indexWhere((a) => a.id == activity.id);

    if (existingIndex >= 0) {
      activities[existingIndex] = activity;
    } else {
      activities.add(activity);
    }

    subSections[subSectionIndex] = subSection.copyWith(activities: activities);
    modules[moduleIndex] = module.copyWith(subSections: subSections);
    courses[courseIndex] = course.copyWith(
      modules: modules,
      updatedAt: DateTime.now(),
    );

    await _saveAll(courses);
  }

  Future<void> deleteActivity(
    String courseId,
    String moduleId,
    String subSectionId,
    String activityId,
  ) async {
    final courses = await loadCourses();
    final courseIndex = courses.indexWhere((c) => c.id == courseId);

    if (courseIndex < 0) return;

    final course = courses[courseIndex];
    final moduleIndex = course.modules.indexWhere((m) => m.id == moduleId);

    if (moduleIndex < 0) return;

    final modules = List<LessonModule>.from(course.modules);
    final module = modules[moduleIndex];
    final subSectionIndex =
        module.subSections.indexWhere((s) => s.id == subSectionId);

    if (subSectionIndex < 0) return;

    final subSections = List<LessonSubSection>.from(module.subSections);
    final subSection = subSections[subSectionIndex];
    final activities = List<Activity>.from(subSection.activities)
      ..removeWhere((a) => a.id == activityId);

    subSections[subSectionIndex] = subSection.copyWith(activities: activities);
    modules[moduleIndex] = module.copyWith(subSections: subSections);
    courses[courseIndex] = course.copyWith(
      modules: modules,
      updatedAt: DateTime.now(),
    );

    await _saveAll(courses);
  }

  Future<void> reorderActivities(
    String courseId,
    String moduleId,
    String subSectionId,
    List<String> activityIds,
  ) async {
    final courses = await loadCourses();
    final courseIndex = courses.indexWhere((c) => c.id == courseId);

    if (courseIndex < 0) return;

    final course = courses[courseIndex];
    final moduleIndex = course.modules.indexWhere((m) => m.id == moduleId);

    if (moduleIndex < 0) return;

    final modules = List<LessonModule>.from(course.modules);
    final module = modules[moduleIndex];
    final subSectionIndex =
        module.subSections.indexWhere((s) => s.id == subSectionId);

    if (subSectionIndex < 0) return;

    final subSections = List<LessonSubSection>.from(module.subSections);
    final subSection = subSections[subSectionIndex];
    final activities = List<Activity>.from(subSection.activities);

    final reorderedActivities = <Activity>[];
    for (var i = 0; i < activityIds.length; i++) {
      final activity = activities.firstWhere((a) => a.id == activityIds[i]);
      reorderedActivities.add(activity.copyWith(order: i));
    }

    subSections[subSectionIndex] =
        subSection.copyWith(activities: reorderedActivities);
    modules[moduleIndex] = module.copyWith(subSections: subSections);
    courses[courseIndex] = course.copyWith(
      modules: modules,
      updatedAt: DateTime.now(),
    );

    await _saveAll(courses);
  }

  // === Private Helpers ===

  Future<void> _saveAll(List<Course> courses) async {
    final dir = await dataDir;
    final file = _coursesFile(dir);

    final data = {
      'courses': courses.map((c) => c.toJson()).toList(),
    };

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
  }
}
