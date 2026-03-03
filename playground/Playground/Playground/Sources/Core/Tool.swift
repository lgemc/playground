import Foundation

/// Result of executing a tool
/// Marked as @unchecked Sendable because it contains [String: Any] which is not Sendable
enum ToolResult: @unchecked Sendable {
    case success(data: [String: Any])
    case failure(error: String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var isFailure: Bool {
        !isSuccess
    }

    func toJSON() -> [String: Any] {
        switch self {
        case .success(let data):
            return [
                "success": true,
                "data": data
            ]
        case .failure(let error):
            return [
                "success": false,
                "error": error
            ]
        }
    }
}

/// Represents a tool that can be called by the LLM
/// Note: Marked as @unchecked Sendable because it contains [String: Any] which is not Sendable,
/// but we ensure thread-safety by only creating tools at initialization time
struct Tool: @unchecked Sendable {
    let name: String
    let description: String
    let parameters: [String: Any] // JSON Schema

    // Internal handler storage - uses @Sendable to work across actor boundaries
    private let _handler: @Sendable ([String: Any]) async throws -> ToolResult

    // Public accessor for handler
    var handler: @Sendable ([String: Any]) async throws -> ToolResult {
        _handler
    }

    // Initializer that accepts any matching closure type
    init(
        name: String,
        description: String,
        parameters: [String: Any],
        handler: @escaping @Sendable ([String: Any]) async throws -> ToolResult
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self._handler = handler
    }

    /// Convert tool to OpenAI function format
    nonisolated func toOpenAIFormat() -> [String: Any] {
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters
            ]
        ]
    }
}

/// Represents a tool call made by the assistant
struct ToolCall: Codable, Sendable {
    let id: String
    let name: String
    let arguments: [String: Any]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case arguments
    }

    init(id: String, name: String, arguments: [String: Any]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        // Decode arguments as JSON
        if let argumentsString = try? container.decode(String.self, forKey: .arguments),
           let data = argumentsString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            arguments = json
        } else {
            arguments = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)

        // Encode arguments as JSON string
        let data = try JSONSerialization.data(withJSONObject: arguments)
        if let argumentsString = String(data: data, encoding: .utf8) {
            try container.encode(argumentsString, forKey: .arguments)
        }
    }
}
