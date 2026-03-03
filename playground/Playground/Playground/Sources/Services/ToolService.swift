import Foundation

/// Central registry for tools that LLM can call
actor ToolService {
    static let shared = ToolService()

    private var tools: [String: Tool] = [:]

    private init() {}

    /// Register a tool
    func register(_ tool: Tool) {
        tools[tool.name] = tool
    }

    /// Unregister a tool by name
    func unregister(name: String) {
        tools.removeValue(forKey: name)
    }

    /// Get all registered tools
    func allTools() -> [Tool] {
        return Array(tools.values)
    }

    /// Get tool by name
    func getTool(name: String) -> Tool? {
        return tools[name]
    }

    /// Execute a tool by name with arguments
    nonisolated func execute(name: String, arguments: [String: Any]) async -> ToolResult {
        // Get the handler from isolated context
        let handler: (@Sendable ([String: Any]) async throws -> ToolResult)? = await getHandler(name: name)

        guard let handler = handler else {
            return .failure(error: "Tool not found: \(name)")
        }

        do {
            return try await handler(arguments)
        } catch {
            return .failure(error: "Tool execution failed: \(error.localizedDescription)")
        }
    }

    /// Get handler in isolated context
    private func getHandler(name: String) -> (@Sendable ([String: Any]) async throws -> ToolResult)? {
        return tools[name]?.handler
    }

    /// Convert tools to OpenAI format for API calls
    func toOpenAIFormat() -> [[String: Any]] {
        return tools.values.map { $0.toOpenAIFormat() }
    }
}
