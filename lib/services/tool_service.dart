import '../core/tool.dart';

/// Central registry for tools that LLM can call
class ToolService {
  static final ToolService instance = ToolService._();
  ToolService._();

  final Map<String, Tool> _tools = {};

  /// Register a tool
  void register(Tool tool) {
    _tools[tool.name] = tool;
  }

  /// Unregister a tool
  void unregister(String name) {
    _tools.remove(name);
  }

  /// Get all registered tools
  List<Tool> get tools => _tools.values.toList();

  /// Get tool by name
  Tool? getTool(String name) => _tools[name];

  /// Execute a tool by name with arguments
  Future<ToolResult> execute(String name, Map<String, dynamic> args) async {
    final tool = _tools[name];
    if (tool == null) {
      return ToolResult.failure('Tool not found: $name');
    }
    try {
      return await tool.handler(args);
    } catch (e) {
      return ToolResult.failure('Tool execution failed: $e');
    }
  }

  /// Convert tools to OpenAI format for API calls
  List<Map<String, dynamic>> toOpenAIFormat() {
    return _tools.values
        .map((tool) => {
              'type': 'function',
              'function': {
                'name': tool.name,
                'description': tool.description,
                'parameters': tool.parameters,
              },
            })
        .toList();
  }
}
