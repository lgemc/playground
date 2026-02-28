import 'dart:convert';
import 'autocompletion_service.dart';
import '../core/tool.dart';
import '../apps/lms/shared/services/lms_crdt_storage_service.dart';
import '../apps/lms/shared/models/course.dart';
import '../apps/lms/shared/models/lesson_module.dart';
import '../apps/lms/shared/models/lesson_sub_section.dart';
import '../apps/lms/shared/models/activity.dart';
import '../apps/file_system/services/file_system_storage.dart';

/// Message storage for display purposes
class AssistantMessage {
  final String content;
  final DateTime timestamp;
  final bool isUser;

  AssistantMessage({
    required this.content,
    required this.timestamp,
    required this.isUser,
  });

  factory AssistantMessage.fromChatMessage(ChatMessage msg) {
    return AssistantMessage(
      content: msg.content,
      timestamp: DateTime.now(),
      isUser: msg.role == MessageRole.user,
    );
  }
}

/// Events that can be streamed from the agent
abstract class AgentEvent {}

class ContentEvent extends AgentEvent {
  final String content;
  ContentEvent(this.content);
}

class ToolCallStartEvent extends AgentEvent {
  final String toolName;
  final Map<String, dynamic> arguments;

  ToolCallStartEvent(this.toolName, this.arguments);

  String get friendlyName {
    switch (toolName) {
      case 'list_courses':
        return '📚 Listing courses';
      case 'get_course':
        return '📖 Getting course details';
      case 'create_course':
        return '✨ Creating course';
      case 'create_module':
        return '📝 Creating module';
      case 'create_subsection':
        return '📄 Creating subsection';
      case 'create_activity':
        return '🎯 Creating activity';
      case 'ls':
        return '📂 Listing directory';
      default:
        return '🔧 $toolName';
    }
  }
}

/// Orchestrator service using direct tool calling
class OrchestratorAgentService {
  static OrchestratorAgentService? _instance;
  static OrchestratorAgentService get instance => _instance ??= OrchestratorAgentService._();

  OrchestratorAgentService._();

  final List<ChatMessage> _conversationHistory = [];
  final List<Tool> _tools = [];
  bool _isInitialized = false;

  final String _systemPrompt = '''You are a helpful AI assistant with access to file system and LMS course management tools.

Available capabilities:
- List and view courses, modules, subsections, and activities
- Create courses with modules, subsections, and activities
- List directory contents (files and folders) from the file system using the ls tool
- Attach files to activities when creating them

CRITICAL INSTRUCTIONS:
- When you call a tool, you MUST read the "data" field from the tool result
- Extract the actual details (names, paths, IDs, etc.) and present them to the user
- NEVER just repeat the tool's "message" field
- ALWAYS show the specific items from the "data" field
- When creating course structures, remember to use the IDs returned from previous creations
- ALWAYS provide a final response after using tools - NEVER end without responding to the user

Example: When list_courses returns:
{
  "message": "Found 2 courses",
  "data": {
    "courses": [
      {"name": "Introduction to Python", "description": "Learn Python basics"},
      {"name": "Web Development", "description": "Build modern web apps"}
    ]
  }
}

You MUST respond with actual content: "There are 2 courses available:
1. **Introduction to Python** - Learn Python basics
2. **Web Development** - Build modern web apps"

DO NOT respond: "Found 2 courses"
DO NOT end without providing a readable response to the user.

Always format the actual data from tool results in a clear, readable way.''';

  /// Initialize the orchestrator
  Future<void> initialize() async {
    if (_isInitialized) return;

    final autocompletion = AutocompletionService.instance;
    if (!autocompletion.isHighConfigured) {
      throw StateError(
        'High-tier AutocompletionService is not configured. Please configure high LLM settings first (llm.high.*).',
      );
    }

    // Initialize file system storage
    await FileSystemStorage.instance.init();

    // Load tools
    _tools.clear();

    // Import and convert tools to our Tool interface
    // For now, we'll create adapters for the agenix tools
    _loadTools();

    _isInitialized = true;
  }

  void _loadTools() {
    // Create adapters for agenix tools
    final lmsStorage = LmsCrdtStorageService.instance;
    final fileStorage = FileSystemStorage.instance;

    // LMS Tools - Read
    _registerAgenixTool(_createListCoursesTool(lmsStorage));
    _registerAgenixTool(_createGetCourseTool(lmsStorage));

    // LMS Tools - Write
    _registerAgenixTool(_createCreateCourseTool(lmsStorage));
    _registerAgenixTool(_createCreateModuleTool(lmsStorage));
    _registerAgenixTool(_createCreateSubSectionTool(lmsStorage));
    _registerAgenixTool(_createCreateActivityTool(lmsStorage));

    // File System Tools
    _registerAgenixTool(_createLsTool(fileStorage));
  }

  void _registerAgenixTool(Tool tool) {
    _tools.add(tool);
  }

  Tool _createListCoursesTool(LmsCrdtStorageService storage) {
    return Tool(
      name: 'list_courses',
      description: 'List all available courses with their basic information',
      parameters: {
        'type': 'object',
        'properties': {},
      },
      handler: (args) async {
        try {
          final courses = await storage.loadCourses();
          final coursesInfo = courses.map((course) => {
            'id': course.id,
            'name': course.name,
            'description': course.description ?? 'No description',
            'modules_count': course.totalModules,
            'subsections_count': course.totalSubSections,
            'activities_count': course.totalActivities,
          }).toList();

          return ToolResult.success({
            'message': 'Found ${courses.length} courses',
            'data': {'courses': coursesInfo},
          });
        } catch (e) {
          return ToolResult.failure('Failed to list courses: $e');
        }
      },
    );
  }

  Tool _createGetCourseTool(LmsCrdtStorageService storage) {
    return Tool(
      name: 'get_course',
      description: 'Get detailed information about a specific course including all modules, subsections, and activities',
      parameters: {
        'type': 'object',
        'properties': {
          'course_id': {
            'type': 'string',
            'description': 'The ID of the course to retrieve',
          },
        },
        'required': ['course_id'],
      },
      handler: (args) async {
        try {
          final courseId = args['course_id'] as String?;
          if (courseId == null) {
            return ToolResult.failure('Missing required parameter: course_id');
          }

          final course = await storage.getCourse(courseId);
          if (course == null) {
            return ToolResult.failure('Course not found with id: $courseId');
          }

          return ToolResult.success({
            'message': 'Retrieved course: ${course.name}',
            'data': course.toJson(),
          });
        } catch (e) {
          return ToolResult.failure('Failed to get course: $e');
        }
      },
    );
  }

  Tool _createLsTool(FileSystemStorage storage) {
    return Tool(
      name: 'ls',
      description: 'List contents of a directory (both files and folders), similar to Unix ls command. Use "/" or "" for root.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'The directory path to list. Use "/" or "" for root. Example: "documents/" or "images/"',
          },
        },
        'required': ['path'],
      },
      handler: (args) async {
        try {
          String path = args['path'] as String? ?? '/';

          // Normalize path
          if (path == '/') {
            path = '';
          } else if (!path.endsWith('/') && path.isNotEmpty) {
            path = '$path/';
          }

          // Get folders and files in parallel
          final folders = await storage.getFoldersInPath(path);
          final files = await storage.getFilesInFolder(path);

          // Build unified items list with type indicators
          final items = <Map<String, dynamic>>[];

          // Add folders first (like ls does)
          for (final folder in folders) {
            items.add({
              'name': folder.name,
              'type': 'directory',
              'path': folder.path,
            });
          }

          // Add files
          for (final file in files) {
            items.add({
              'name': file.name,
              'type': 'file',
              'id': file.id,
              'path': file.relativePath,
              'mime_type': file.mimeType ?? 'unknown',
              'size': file.size,
            });
          }

          return ToolResult.success({
            'message': 'Found ${folders.length} directories and ${files.length} files in ${path.isEmpty ? "root" : path}',
            'data': {
              'current_path': path,
              'items': items,
              'summary': {
                'total': items.length,
                'directories': folders.length,
                'files': files.length,
              },
            },
          });
        } catch (e) {
          return ToolResult.failure('Failed to list directory: $e');
        }
      },
    );
  }

  Tool _createCreateCourseTool(LmsCrdtStorageService storage) {
    return Tool(
      name: 'create_course',
      description: 'Create a new course with a name and optional description',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'The name of the course',
          },
          'description': {
            'type': 'string',
            'description': 'Optional description of the course',
          },
        },
        'required': ['name'],
      },
      handler: (args) async {
        try {
          final name = args['name'] as String?;
          if (name == null || name.trim().isEmpty) {
            return ToolResult.failure('Course name is required');
          }

          final description = args['description'] as String?;

          final course = Course.create(
            name: name.trim(),
            description: description?.trim(),
          );

          await storage.saveCourse(course);

          return ToolResult.success({
            'message': 'Created course: ${course.name}',
            'data': {
              'course_id': course.id,
              'name': course.name,
              'description': course.description,
            },
          });
        } catch (e) {
          return ToolResult.failure('Failed to create course: $e');
        }
      },
    );
  }

  Tool _createCreateModuleTool(LmsCrdtStorageService storage) {
    return Tool(
      name: 'create_module',
      description: 'Create a new module inside a course. Modules are the main sections of a course.',
      parameters: {
        'type': 'object',
        'properties': {
          'course_id': {
            'type': 'string',
            'description': 'The ID of the course to add the module to',
          },
          'name': {
            'type': 'string',
            'description': 'The name of the module',
          },
          'description': {
            'type': 'string',
            'description': 'Optional description of the module',
          },
        },
        'required': ['course_id', 'name'],
      },
      handler: (args) async {
        try {
          final courseId = args['course_id'] as String?;
          if (courseId == null || courseId.trim().isEmpty) {
            return ToolResult.failure('Course ID is required');
          }

          final name = args['name'] as String?;
          if (name == null || name.trim().isEmpty) {
            return ToolResult.failure('Module name is required');
          }

          // Check if course exists
          final course = await storage.getCourse(courseId);
          if (course == null) {
            return ToolResult.failure('Course not found with id: $courseId');
          }

          final description = args['description'] as String?;

          // Calculate order (next position)
          final order = course.modules.length;

          final module = LessonModule.create(
            courseId: courseId,
            name: name.trim(),
            description: description?.trim(),
            order: order,
          );

          await storage.saveModule(courseId, module);

          return ToolResult.success({
            'message': 'Created module: ${module.name} in course: ${course.name}',
            'data': {
              'module_id': module.id,
              'course_id': courseId,
              'name': module.name,
              'description': module.description,
              'order': module.order,
            },
          });
        } catch (e) {
          return ToolResult.failure('Failed to create module: $e');
        }
      },
    );
  }

  Tool _createCreateSubSectionTool(LmsCrdtStorageService storage) {
    return Tool(
      name: 'create_subsection',
      description: 'Create a new subsection inside a module. Subsections are subdivisions within modules.',
      parameters: {
        'type': 'object',
        'properties': {
          'course_id': {
            'type': 'string',
            'description': 'The ID of the course',
          },
          'module_id': {
            'type': 'string',
            'description': 'The ID of the module to add the subsection to',
          },
          'name': {
            'type': 'string',
            'description': 'The name of the subsection',
          },
          'description': {
            'type': 'string',
            'description': 'Optional description of the subsection',
          },
        },
        'required': ['course_id', 'module_id', 'name'],
      },
      handler: (args) async {
        try {
          final courseId = args['course_id'] as String?;
          if (courseId == null || courseId.trim().isEmpty) {
            return ToolResult.failure('Course ID is required');
          }

          final moduleId = args['module_id'] as String?;
          if (moduleId == null || moduleId.trim().isEmpty) {
            return ToolResult.failure('Module ID is required');
          }

          final name = args['name'] as String?;
          if (name == null || name.trim().isEmpty) {
            return ToolResult.failure('Subsection name is required');
          }

          // Check if course and module exist
          final course = await storage.getCourse(courseId);
          if (course == null) {
            return ToolResult.failure('Course not found with id: $courseId');
          }

          final module = course.modules.where((m) => m.id == moduleId).firstOrNull;
          if (module == null) {
            return ToolResult.failure('Module not found with id: $moduleId');
          }

          final description = args['description'] as String?;

          // Calculate order (next position)
          final order = module.subSections.length;

          final subSection = LessonSubSection.create(
            moduleId: moduleId,
            name: name.trim(),
            description: description?.trim(),
            order: order,
          );

          await storage.saveSubSection(courseId, moduleId, subSection);

          return ToolResult.success({
            'message': 'Created subsection: ${subSection.name} in module: ${module.name}',
            'data': {
              'subsection_id': subSection.id,
              'module_id': moduleId,
              'course_id': courseId,
              'name': subSection.name,
              'description': subSection.description,
              'order': subSection.order,
            },
          });
        } catch (e) {
          return ToolResult.failure('Failed to create subsection: $e');
        }
      },
    );
  }

  Tool _createCreateActivityTool(LmsCrdtStorageService storage) {
    return Tool(
      name: 'create_activity',
      description: 'Create a new activity inside a subsection. Activities can have attached files (lecture, video, audio, document, etc.).',
      parameters: {
        'type': 'object',
        'properties': {
          'course_id': {
            'type': 'string',
            'description': 'The ID of the course',
          },
          'module_id': {
            'type': 'string',
            'description': 'The ID of the module',
          },
          'subsection_id': {
            'type': 'string',
            'description': 'The ID of the subsection to add the activity to',
          },
          'name': {
            'type': 'string',
            'description': 'The name of the activity',
          },
          'description': {
            'type': 'string',
            'description': 'Optional description of the activity',
          },
          'file_id': {
            'type': 'string',
            'description': 'Optional ID of a file from the file system to attach to this activity',
          },
          'resource_type': {
            'type': 'string',
            'description': 'The type of resource: lecture, audio, video, document, or other',
            'enum': ['lecture', 'audio', 'video', 'document', 'other'],
          },
        },
        'required': ['course_id', 'module_id', 'subsection_id', 'name', 'resource_type'],
      },
      handler: (args) async {
        try {
          final courseId = args['course_id'] as String?;
          if (courseId == null || courseId.trim().isEmpty) {
            return ToolResult.failure('Course ID is required');
          }

          final moduleId = args['module_id'] as String?;
          if (moduleId == null || moduleId.trim().isEmpty) {
            return ToolResult.failure('Module ID is required');
          }

          final subsectionId = args['subsection_id'] as String?;
          if (subsectionId == null || subsectionId.trim().isEmpty) {
            return ToolResult.failure('Subsection ID is required');
          }

          final name = args['name'] as String?;
          if (name == null || name.trim().isEmpty) {
            return ToolResult.failure('Activity name is required');
          }

          final resourceTypeStr = args['resource_type'] as String?;
          if (resourceTypeStr == null) {
            return ToolResult.failure('Resource type is required');
          }

          // Validate resource type
          final resourceType = ResourceType.values.where((t) => t.name == resourceTypeStr).firstOrNull;
          if (resourceType == null) {
            return ToolResult.failure('Invalid resource type: $resourceTypeStr');
          }

          // Check if course, module, and subsection exist
          final course = await storage.getCourse(courseId);
          if (course == null) {
            return ToolResult.failure('Course not found with id: $courseId');
          }

          final module = course.modules.where((m) => m.id == moduleId).firstOrNull;
          if (module == null) {
            return ToolResult.failure('Module not found with id: $moduleId');
          }

          final subsection = module.subSections.where((s) => s.id == subsectionId).firstOrNull;
          if (subsection == null) {
            return ToolResult.failure('Subsection not found with id: $subsectionId');
          }

          final description = args['description'] as String?;
          final fileId = args['file_id'] as String?;

          // Calculate order (next position)
          final order = subsection.activities.length;

          final activity = ResourceFileActivity.create(
            subSectionId: subsectionId,
            name: name.trim(),
            description: description?.trim(),
            order: order,
            fileId: fileId,
            resourceType: resourceType,
          );

          await storage.saveActivity(courseId, moduleId, subsectionId, activity);

          return ToolResult.success({
            'message': 'Created activity: ${activity.name} in subsection: ${subsection.name}',
            'data': {
              'activity_id': activity.id,
              'subsection_id': subsectionId,
              'module_id': moduleId,
              'course_id': courseId,
              'name': activity.name,
              'description': activity.description,
              'file_id': activity.fileId,
              'resource_type': activity.resourceType.name,
              'order': activity.order,
            },
          });
        } catch (e) {
          return ToolResult.failure('Failed to create activity: $e');
        }
      },
    );
  }

  /// Send a message and get a streaming response with events
  Stream<AgentEvent> chatStreamEvents(String message) async* {
    if (!_isInitialized) {
      await initialize();
    }

    // Add user message to conversation history
    _conversationHistory.add(ChatMessage(
      role: MessageRole.user,
      content: message,
    ));

    // Build conversation history with system prompt
    final conversationHistory = _buildConversationHistory();

    final autocompletion = AutocompletionService.instance;
    final buffer = StringBuffer();

    // Tool calling loop
    while (true) {
      final toolCalls = <ToolCallEvent>[];

      await for (final event in autocompletion.completeWithToolsHigh(
        conversationHistory,
        tools: _tools.isNotEmpty ? _tools : null,
      )) {
        if (event is ContentChunk) {
          buffer.write(event.content);
          yield ContentEvent(event.content); // Stream the chunk to UI
        } else if (event is ToolCallEvent) {
          toolCalls.add(event);
        }
      }

      // If no tool calls, we're done
      if (toolCalls.isEmpty) {
        final response = buffer.toString().trim();

        // Add assistant response to persistent conversation history
        if (response.isNotEmpty) {
          _conversationHistory.add(ChatMessage(
            role: MessageRole.assistant,
            content: response,
          ));
        }
        return;
      }

      // Add assistant message with tool calls to persistent history
      final assistantMessage = ChatMessage(
        role: MessageRole.assistant,
        content: buffer.toString(),
        toolCalls: toolCalls.map((tc) => ChatToolCall(
          id: tc.id,
          name: tc.name,
          arguments: tc.arguments,
        )).toList(),
      );
      _conversationHistory.add(assistantMessage);
      conversationHistory.add(assistantMessage);

      // Execute tool calls
      for (final toolCall in toolCalls) {
        // Notify UI about tool call
        yield ToolCallStartEvent(toolCall.name, toolCall.arguments);

        final result = await _executeTool(toolCall.name, toolCall.arguments);

        // Add tool result to both persistent and local history
        final toolResultMessage = ChatMessage(
          role: MessageRole.tool,
          toolCallId: toolCall.id,
          content: jsonEncode(result.toJson()),
        );
        _conversationHistory.add(toolResultMessage);
        conversationHistory.add(toolResultMessage);
      }

      buffer.clear();
    }
  }

  /// Send a message and get a streaming response (backward compatible)
  Stream<String> chatStream(String message) async* {
    await for (final event in chatStreamEvents(message)) {
      if (event is ContentEvent) {
        yield event.content;
      }
    }
  }

  /// Execute a tool by name
  Future<ToolResult> _executeTool(String name, Map<String, dynamic> args) async {
    final tool = _tools.where((t) => t.name == name).firstOrNull;
    if (tool == null) {
      return ToolResult.failure('Tool not found: $name');
    }

    try {
      return await tool.handler(args);
    } catch (e) {
      return ToolResult.failure('Tool execution failed: $e');
    }
  }

  /// Build conversation history for API
  List<ChatMessage> _buildConversationHistory() {
    final messages = <ChatMessage>[
      // Add system prompt as first message
      ChatMessage(
        role: MessageRole.system,
        content: _systemPrompt,
      ),
    ];

    // Add all persistent conversation messages (includes tool calls and results)
    messages.addAll(_conversationHistory);

    return messages;
  }

  /// Get all messages for display (filters out tool messages)
  List<AssistantMessage> getMessages() {
    return _conversationHistory
        .where((msg) => msg.role == MessageRole.user || msg.role == MessageRole.assistant)
        .where((msg) => msg.content.isNotEmpty)
        .map((msg) => AssistantMessage.fromChatMessage(msg))
        .toList();
  }

  /// Reset conversation
  Future<void> resetConversation() async {
    _conversationHistory.clear();
  }

  /// Check if initialized
  bool get isInitialized => _isInitialized;

  /// Dispose
  void dispose() {
    _conversationHistory.clear();
    _tools.clear();
    _isInitialized = false;
  }
}
