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

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case maxTokens = "max_tokens"
            case stream
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
        }
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
                stream: false
            )

            // Encode request manually to avoid Sendable conformance issues
            let requestBody = try JSONEncoder().encode(request)

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
            stream: true
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var headers = HTTPHeaders()
                    if !apiKey.isEmpty {
                        headers.add(.authorization(bearerToken: apiKey))
                    }
                    headers.add(.contentType("application/json"))

                    let requestBody = try JSONEncoder().encode(request)

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
