import Foundation
import Alamofire

/// OpenAI-compatible LLM API client
/// Supports both streaming and non-streaming completions
class AutocompletionService {
    static let shared = AutocompletionService()
    private let config = ConfigService.shared

    private init() {}

    /// Check if the service is properly configured
    var isConfigured: Bool {
        let baseURL = config.getString(key: "llm.base_url")
        return !baseURL.isEmpty
    }

    // MARK: - Chat Completion

    struct ChatMessage: Codable, Sendable {
        let role: String
        let content: String
    }

    struct ChatCompletionRequest: Codable, Sendable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double?
        let maxTokens: Int?
        let stream: Bool
        let tools: [[String: Any]]?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case maxTokens = "max_tokens"
            case stream
            case tools
        }

        init(model: String, messages: [ChatMessage], temperature: Double?, maxTokens: Int?, stream: Bool, tools: [[String: Any]]? = nil) {
            self.model = model
            self.messages = messages
            self.temperature = temperature
            self.maxTokens = maxTokens
            self.stream = stream
            self.tools = tools
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            model = try container.decode(String.self, forKey: .model)
            messages = try container.decode([ChatMessage].self, forKey: .messages)
            temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
            maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
            stream = try container.decode(Bool.self, forKey: .stream)
            tools = nil // Tools are not decoded from JSON
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(model, forKey: .model)
            try container.encode(messages, forKey: .messages)
            try container.encodeIfPresent(temperature, forKey: .temperature)
            try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
            try container.encode(stream, forKey: .stream)

            // Manually encode tools as JSON
            if let tools = tools {
                // We need to manually serialize this since it's [String: Any]
                // This will be handled by custom JSON encoding
            }
        }

        func toJSONData() throws -> Data {
            var dict: [String: Any] = [
                "model": model,
                "messages": messages.map { ["role": $0.role, "content": $0.content] },
                "stream": stream
            ]

            if let temperature = temperature {
                dict["temperature"] = temperature
            }
            if let maxTokens = maxTokens {
                dict["max_tokens"] = maxTokens
            }
            if let tools = tools, !tools.isEmpty {
                dict["tools"] = tools
            }

            return try JSONSerialization.data(withJSONObject: dict)
        }
    }

    struct ChatCompletionResponse: Codable, Sendable {
        let id: String?
        let choices: [Choice]

        struct Choice: Codable, Sendable {
            let message: ChatMessage
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }
    }

    struct ChatCompletionChunk: Codable, Sendable {
        let id: String?
        let choices: [Choice]

        struct Choice: Codable, Sendable {
            let delta: Delta
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }

        struct Delta: Codable, Sendable {
            let role: String?
            let content: String?
            let toolCalls: [ToolCallDelta]?

            enum CodingKeys: String, CodingKey {
                case role
                case content
                case toolCalls = "tool_calls"
            }
        }

        struct ToolCallDelta: Codable, Sendable {
            let index: Int
            let id: String?
            let type: String?
            let function: FunctionDelta?

            struct FunctionDelta: Codable, Sendable {
                let name: String?
                let arguments: String?
            }
        }
    }

    /// Stream events for tool calling
    enum ChatStreamEvent {
        case contentChunk(String)
        case toolCall(id: String, name: String, arguments: [String: Any])
        case done
    }

    /// Non-streaming chat completion
    func complete(messages: [ChatMessage],
                  model: String? = nil,
                  temperature: Double? = nil,
                  maxTokens: Int? = nil) async -> Result<String, Error> {
        return await Result.catching {
            let baseURL = self.config.getString(key: "llm.base_url")
            let apiKey = self.config.getString(key: "llm.api_key")
            let modelName = model ?? self.config.getString(key: "llm.model", default: "gpt-4o-mini")

            let request = ChatCompletionRequest(
                model: modelName,
                messages: messages,
                temperature: temperature ?? self.config.getDouble(key: "llm.temperature", default: 0.7),
                maxTokens: maxTokens ?? self.config.getInt(key: "llm.max_tokens", default: 1024),
                stream: false,
                tools: nil
            )

            // Encode request manually to avoid Sendable conformance issues
            let requestBody = try request.toJSONData()

            var headers = HTTPHeaders()
            if !apiKey.isEmpty {
                headers.add(.authorization(bearerToken: apiKey))
            }
            headers.add(.contentType("application/json"))

            let responseData = try await AF.request(
                "\(baseURL)/chat/completions",
                method: .post,
                headers: headers
            ) { urlRequest in
                urlRequest.httpBody = requestBody
            }
            .serializingData()
            .value

            // Decode response manually to avoid Sendable conformance issues
            let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: responseData)
            return response.choices.first?.message.content ?? ""
        }
    }

    /// Streaming chat completion
    func completeStream(messages: [ChatMessage],
                       model: String? = nil,
                       temperature: Double? = nil,
                       maxTokens: Int? = nil) -> AsyncThrowingStream<String, Error> {
        let baseURL = config.getString(key: "llm.base_url")
        let apiKey = config.getString(key: "llm.api_key")
        let modelName = model ?? config.getString(key: "llm.model", default: "gpt-4o-mini")

        let request = ChatCompletionRequest(
            model: modelName,
            messages: messages,
            temperature: temperature ?? config.getDouble(key: "llm.temperature", default: 0.7),
            maxTokens: maxTokens ?? config.getInt(key: "llm.max_tokens", default: 1024),
            stream: true,
            tools: nil
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var headers = HTTPHeaders()
                    if !apiKey.isEmpty {
                        headers.add(.authorization(bearerToken: apiKey))
                    }
                    headers.add(.contentType("application/json"))

                    let requestBody = try request.toJSONData()

                    var urlRequest = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
                    urlRequest.httpMethod = "POST"
                    urlRequest.httpBody = requestBody
                    for header in headers.dictionary {
                        urlRequest.setValue(header.value, forHTTPHeaderField: header.key)
                    }

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("❌ Response is not HTTPURLResponse")
                        throw AutocompletionError.invalidResponse
                    }

                    guard httpResponse.statusCode == 200 else {
                        print("❌ HTTP Status: \(httpResponse.statusCode)")
                        print("❌ URL: \(baseURL)/chat/completions")
                        print("❌ Model: \(modelName)")
                        throw AutocompletionError.httpError(statusCode: httpResponse.statusCode)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let data = String(line.dropFirst(6))

                        if data == "[DONE]" {
                            continuation.finish()
                            return
                        }

                        guard let jsonData = data.data(using: .utf8) else { continue }
                        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: jsonData)

                        if let content = chunk.choices.first?.delta.content {
                            continuation.yield(content)
                        }

                        if chunk.choices.first?.finishReason != nil {
                            continuation.finish()
                            return
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Streaming chat completion with tools support
    /// Yields ChatStreamEvent objects for content chunks and tool calls
    func completeWithTools(messages: [ChatMessage],
                          tools: [[String: Any]]?,
                          model: String? = nil,
                          temperature: Double? = nil,
                          maxTokens: Int? = nil) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let baseURL = config.getString(key: "llm.base_url")
        let apiKey = config.getString(key: "llm.api_key")
        let modelName = model ?? config.getString(key: "llm.model", default: "gpt-4o-mini")

        let request = ChatCompletionRequest(
            model: modelName,
            messages: messages,
            temperature: temperature ?? config.getDouble(key: "llm.temperature", default: 0.7),
            maxTokens: maxTokens ?? config.getInt(key: "llm.max_tokens", default: 1024),
            stream: true,
            tools: tools
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var headers = HTTPHeaders()
                    if !apiKey.isEmpty {
                        headers.add(.authorization(bearerToken: apiKey))
                    }
                    headers.add(.contentType("application/json"))

                    let requestBody = try request.toJSONData()

                    var urlRequest = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
                    urlRequest.httpMethod = "POST"
                    urlRequest.httpBody = requestBody
                    for header in headers.dictionary {
                        urlRequest.setValue(header.value, forHTTPHeaderField: header.key)
                    }

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("❌ Response is not HTTPURLResponse")
                        throw AutocompletionError.invalidResponse
                    }

                    guard httpResponse.statusCode == 200 else {
                        print("❌ HTTP Status: \(httpResponse.statusCode)")
                        throw AutocompletionError.httpError(statusCode: httpResponse.statusCode)
                    }

                    // Track tool calls being built up from streaming chunks
                    var toolCallsInProgress: [Int: (id: String?, name: String?, arguments: String)] = [:]

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let data = String(line.dropFirst(6))

                        if data == "[DONE]" {
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        }

                        guard let jsonData = data.data(using: .utf8) else { continue }
                        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: jsonData)

                        guard let choice = chunk.choices.first else { continue }

                        // Handle content
                        if let content = choice.delta.content {
                            continuation.yield(.contentChunk(content))
                        }

                        // Handle tool call deltas
                        if let toolCallDeltas = choice.delta.toolCalls {
                            for toolCallDelta in toolCallDeltas {
                                let index = toolCallDelta.index

                                // Initialize builder if new tool call
                                if toolCallsInProgress[index] == nil {
                                    toolCallsInProgress[index] = (nil, nil, "")
                                }

                                var current = toolCallsInProgress[index]!

                                // Accumulate data from delta
                                if let id = toolCallDelta.id {
                                    current.id = id
                                }
                                if let name = toolCallDelta.function?.name {
                                    current.name = name
                                }
                                if let args = toolCallDelta.function?.arguments {
                                    current.arguments += args
                                }

                                toolCallsInProgress[index] = current
                            }
                        }

                        // Check if stream is done
                        if let finishReason = choice.finishReason {
                            // If finished with tool_calls, emit the tool call events
                            if finishReason == "tool_calls" {
                                for (_, toolCall) in toolCallsInProgress {
                                    if let id = toolCall.id, let name = toolCall.name {
                                        var args: [String: Any] = [:]
                                        if !toolCall.arguments.isEmpty,
                                           let argsData = toolCall.arguments.data(using: .utf8),
                                           let json = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                                            args = json
                                        }
                                        continuation.yield(.toolCall(id: id, name: name, arguments: args))
                                    }
                                }
                            }

                            continuation.yield(.done)
                            continuation.finish()
                            return
                        }
                    }

                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Convenience Methods

    /// Simple prompt-based completion (user message)
    func prompt(_ userMessage: String,
                systemPrompt: String? = nil,
                temperature: Double? = nil,
                maxTokens: Int? = nil) async -> Result<String, Error> {
        var messages: [ChatMessage] = []

        if let systemPrompt = systemPrompt {
            messages.append(ChatMessage(role: "system", content: systemPrompt))
        }

        messages.append(ChatMessage(role: "user", content: userMessage))

        return await complete(
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    /// Simple streaming prompt
    func promptStream(_ userMessage: String,
                     systemPrompt: String? = nil,
                     temperature: Double? = nil,
                     maxTokens: Int? = nil) -> AsyncThrowingStream<String, Error> {
        var messages: [ChatMessage] = []

        if let systemPrompt = systemPrompt {
            messages.append(ChatMessage(role: "system", content: systemPrompt))
        }

        messages.append(ChatMessage(role: "user", content: userMessage))

        return completeStream(
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }
}

enum AutocompletionError: Error {
    case invalidResponse
    case httpError(statusCode: Int)
    case missingContent
    case networkError(Error)

    var localizedDescription: String {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .missingContent:
            return "Missing content in response"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
