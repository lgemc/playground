import 'package:agenix/agenix.dart';
import '../shared/models/course.dart';
import '../shared/models/lesson_module.dart';
import '../shared/models/lesson_sub_section.dart';
import '../shared/models/activity.dart';
import '../shared/services/lms_crdt_storage_service.dart';

/// Tool to list all courses
class ListCoursesTool extends Tool {
  final LmsCrdtStorageService _storage;

  ListCoursesTool(this._storage)
      : super(
          name: 'list_courses',
          description: 'List all available courses with their basic information',
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      final courses = await _storage.loadCourses();

      final coursesInfo = courses.map((course) => {
        'id': course.id,
        'name': course.name,
        'description': course.description ?? 'No description',
        'modules_count': course.totalModules,
        'subsections_count': course.totalSubSections,
        'activities_count': course.totalActivities,
      }).toList();

      return ToolResponse(
        toolName: name,
        isRequestSuccessful: true,
        message: 'Found ${courses.length} courses',
        data: {'courses': coursesInfo},
      );
    } catch (e) {
      return ToolResponse(
        toolName: name,
        isRequestSuccessful: false,
        message: 'Failed to list courses: $e',
      );
    }
  }
}

/// Tool to get detailed course information
class GetCourseTool extends Tool {
  final LmsCrdtStorageService _storage;

  GetCourseTool(this._storage)
      : super(
          name: 'get_course',
          description: 'Get detailed information about a specific course including all modules, subsections, and activities. Required parameter: course_id',
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      final courseId = params['course_id'] as String?;
      if (courseId == null) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'Missing required parameter: course_id',
        );
      }

      final course = await _storage.getCourse(courseId);
      if (course == null) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'Course not found with id: $courseId',
        );
      }

      return ToolResponse(
        toolName: name,
        isRequestSuccessful: true,
        message: 'Retrieved course: ${course.name}',
        data: course.toJson(),
      );
    } catch (e) {
      return ToolResponse(
        toolName: name,
        isRequestSuccessful: false,
        message: 'Failed to get course: $e',
      );
    }
  }
}

/// Tool to create a new course
class CreateCourseTool extends Tool {
  final LmsCrdtStorageService _storage;

  CreateCourseTool(this._storage)
      : super(
          name: 'create_course',
          description: 'Create a new course. Required parameter: name. Optional: description, thumbnail_file_id',
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      final name = params['name'] as String?;
      if (name == null || name.isEmpty) {
        return ToolResponse(
          toolName: this.name,
          isRequestSuccessful: false,
          message: 'Missing required parameter: name',
        );
      }

      final course = Course.create(
        name: name,
        description: params['description'] as String?,
        thumbnailFileId: params['thumbnail_file_id'] as String?,
      );

      await _storage.saveCourse(course);

      return ToolResponse(
        toolName: this.name,
        isRequestSuccessful: true,
        message: 'Created course: $name',
        data: course.toJson(),
      );
    } catch (e) {
      return ToolResponse(
        toolName: this.name,
        isRequestSuccessful: false,
        message: 'Failed to create course: $e',
      );
    }
  }
}

/// Tool to update an existing course
class UpdateCourseTool extends Tool {
  final LmsCrdtStorageService _storage;

  UpdateCourseTool(this._storage)
      : super(
          name: 'update_course',
          description: 'Update an existing course. Required: course_id. Optional: name, description, thumbnail_file_id',
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      final courseId = params['course_id'] as String?;
      if (courseId == null) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'Missing required parameter: course_id',
        );
      }

      final course = await _storage.getCourse(courseId);
      if (course == null) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'Course not found with id: $courseId',
        );
      }

      final updatedCourse = course.copyWith(
        name: params['name'] as String?,
        description: params['description'] as String?,
        thumbnailFileId: params['thumbnail_file_id'] as String?,
        updatedAt: DateTime.now(),
      );

      await _storage.saveCourse(updatedCourse);

      return ToolResponse(
        toolName: name,
        isRequestSuccessful: true,
        message: 'Updated course: ${updatedCourse.name}',
        data: updatedCourse.toJson(),
      );
    } catch (e) {
      return ToolResponse(
        toolName: name,
        isRequestSuccessful: false,
        message: 'Failed to update course: $e',
      );
    }
  }
}

/// Tool to delete a course
class DeleteCourseTool extends Tool {
  final LmsCrdtStorageService _storage;

  DeleteCourseTool(this._storage)
      : super(
          name: 'delete_course',
          description: 'Delete a course and all its modules, subsections, and activities. Required parameter: course_id',
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      final courseId = params['course_id'] as String?;
      if (courseId == null) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'Missing required parameter: course_id',
        );
      }

      await _storage.deleteCourse(courseId);

      return ToolResponse(
        toolName: name,
        isRequestSuccessful: true,
        message: 'Deleted course with id: $courseId',
        data: {'course_id': courseId},
      );
    } catch (e) {
      return ToolResponse(
        toolName: name,
        isRequestSuccessful: false,
        message: 'Failed to delete course: $e',
      );
    }
  }
}

/// Tool to create a module in a course
class CreateModuleTool extends Tool {
  final LmsCrdtStorageService _storage;

  CreateModuleTool(this._storage)
      : super(
          name: 'create_module',
          description: 'Create a new module in a course. Required: course_id, name, order. Optional: description',
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      final courseId = params['course_id'] as String?;
      final name = params['name'] as String?;
      final order = params['order'];

      if (courseId == null || name == null || order == null) {
        return ToolResponse(
          toolName: this.name,
          isRequestSuccessful: false,
          message: 'Missing required parameters: course_id, name, order',
        );
      }

      final module = LessonModule.create(
        courseId: courseId,
        name: name,
        description: params['description'] as String?,
        order: order is int ? order : int.parse(order.toString()),
      );

      await _storage.saveModule(courseId, module);

      return ToolResponse(
        toolName: this.name,
        isRequestSuccessful: true,
        message: 'Created module: $name',
        data: module.toJson(),
      );
    } catch (e) {
      return ToolResponse(
        toolName: this.name,
        isRequestSuccessful: false,
        message: 'Failed to create module: $e',
      );
    }
  }
}

/// Tool to update a module
class UpdateModuleTool extends Tool {
  final LmsCrdtStorageService _storage;

  UpdateModuleTool(this._storage)
      : super(
          name: 'update_module',
          description: 'Update a module. Required: course_id, module_id. Optional: name, description, order',
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      final courseId = params['course_id'] as String?;
      final moduleId = params['module_id'] as String?;

      if (courseId == null || moduleId == null) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'Missing required parameters: course_id, module_id',
        );
      }

      final course = await _storage.getCourse(courseId);
      if (course == null) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'Course not found',
        );
      }

      final module = course.modules.firstWhere(
        (m) => m.id == moduleId,
        orElse: () => throw Exception('Module not found'),
      );

      final updatedModule = module.copyWith(
        name: params['name'] as String?,
        description: params['description'] as String?,
        order: params['order'] != null
            ? (params['order'] is int ? params['order'] : int.parse(params['order'].toString()))
            : null,
      );

      await _storage.saveModule(courseId, updatedModule);

      return ToolResponse(
        toolName: name,
        isRequestSuccessful: true,
        message: 'Updated module: ${updatedModule.name}',
        data: updatedModule.toJson(),
      );
    } catch (e) {
      return ToolResponse(
        toolName: name,
        isRequestSuccessful: false,
        message: 'Failed to update module: $e',
      );
    }
  }
}

/// Tool to delete a module
class DeleteModuleTool extends Tool {
  final LmsCrdtStorageService _storage;

  DeleteModuleTool(this._storage)
      : super(
          name: 'delete_module',
          description: 'Delete a module and all its subsections and activities. Required: course_id, module_id',
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      final courseId = params['course_id'] as String?;
      final moduleId = params['module_id'] as String?;

      if (courseId == null || moduleId == null) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'Missing required parameters: course_id, module_id',
        );
      }

      await _storage.deleteModule(courseId, moduleId);

      return ToolResponse(
        toolName: name,
        isRequestSuccessful: true,
        message: 'Deleted module with id: $moduleId',
        data: {'course_id': courseId, 'module_id': moduleId},
      );
    } catch (e) {
      return ToolResponse(
        toolName: name,
        isRequestSuccessful: false,
        message: 'Failed to delete module: $e',
      );
    }
  }
}

/// Tool to create a subsection in a module
class CreateSubSectionTool extends Tool {
  final LmsCrdtStorageService _storage;

  CreateSubSectionTool(this._storage)
      : super(
          name: 'create_subsection',
          description: 'Create a new subsection in a module. Required: course_id, module_id, name, order. Optional: description',
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      final courseId = params['course_id'] as String?;
      final moduleId = params['module_id'] as String?;
      final name = params['name'] as String?;
      final order = params['order'];

      if (courseId == null || moduleId == null || name == null || order == null) {
        return ToolResponse(
          toolName: this.name,
          isRequestSuccessful: false,
          message: 'Missing required parameters: course_id, module_id, name, order',
        );
      }

      final subSection = LessonSubSection.create(
        moduleId: moduleId,
        name: name,
        description: params['description'] as String?,
        order: order is int ? order : int.parse(order.toString()),
      );

      await _storage.saveSubSection(courseId, moduleId, subSection);

      return ToolResponse(
        toolName: this.name,
        isRequestSuccessful: true,
        message: 'Created subsection: $name',
        data: subSection.toJson(),
      );
    } catch (e) {
      return ToolResponse(
        toolName: this.name,
        isRequestSuccessful: false,
        message: 'Failed to create subsection: $e',
      );
    }
  }
}

/// Tool to create an activity in a subsection
class CreateActivityTool extends Tool {
  final LmsCrdtStorageService _storage;

  CreateActivityTool(this._storage)
      : super(
          name: 'create_activity',
          description: 'Create a new resource activity in a subsection. Required: course_id, module_id, subsection_id, name, order, resource_type (lecture/audio/video/document/other). Optional: description, file_id',
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      final courseId = params['course_id'] as String?;
      final moduleId = params['module_id'] as String?;
      final subSectionId = params['subsection_id'] as String?;
      final name = params['name'] as String?;
      final order = params['order'];
      final resourceTypeStr = params['resource_type'] as String?;

      if (courseId == null || moduleId == null || subSectionId == null ||
          name == null || order == null || resourceTypeStr == null) {
        return ToolResponse(
          toolName: this.name,
          isRequestSuccessful: false,
          message: 'Missing required parameters: course_id, module_id, subsection_id, name, order, resource_type',
        );
      }

      final resourceType = ResourceType.values.firstWhere(
        (t) => t.name.toLowerCase() == resourceTypeStr.toLowerCase(),
        orElse: () => ResourceType.other,
      );

      final activity = ResourceFileActivity.create(
        subSectionId: subSectionId,
        name: name,
        description: params['description'] as String?,
        order: order is int ? order : int.parse(order.toString()),
        fileId: params['file_id'] as String?,
        resourceType: resourceType,
      );

      await _storage.saveActivity(courseId, moduleId, subSectionId, activity);

      return ToolResponse(
        toolName: this.name,
        isRequestSuccessful: true,
        message: 'Created activity: $name',
        data: activity.toJson(),
      );
    } catch (e) {
      return ToolResponse(
        toolName: this.name,
        isRequestSuccessful: false,
        message: 'Failed to create activity: $e',
      );
    }
  }
}

/// Factory to create all LMS tools
class LmsToolsFactory {
  static List<Tool> createAll(LmsCrdtStorageService storage) {
    return [
      ListCoursesTool(storage),
      GetCourseTool(storage),
      CreateCourseTool(storage),
      UpdateCourseTool(storage),
      DeleteCourseTool(storage),
      CreateModuleTool(storage),
      UpdateModuleTool(storage),
      DeleteModuleTool(storage),
      CreateSubSectionTool(storage),
      CreateActivityTool(storage),
    ];
  }
}
