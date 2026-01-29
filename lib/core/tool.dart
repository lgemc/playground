/// Represents a tool that can be called by the LLM
class Tool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters; // JSON Schema
  final Future<ToolResult> Function(Map<String, dynamic> args) handler;
  final String? appId; // Optional: which app registered this tool

  const Tool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.handler,
    this.appId,
  });
}

/// Result of executing a tool
class ToolResult {
  final bool success;
  final dynamic data;
  final String? error;

  const ToolResult.success(this.data)
      : success = true,
        error = null;

  const ToolResult.failure(this.error)
      : success = false,
        data = null;

  Map<String, dynamic> toJson() => {
        'success': success,
        if (data != null) 'data': data,
        if (error != null) 'error': error,
      };
}
