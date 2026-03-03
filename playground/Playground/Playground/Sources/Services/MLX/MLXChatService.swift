import Foundation
import Combine
import MLX
import MLXNN
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Native MLX-based chat service for on-device LLM inference
/// Uses MLX Swift framework directly - no server required!
@MainActor
class MLXChatService: ObservableObject {
    static let shared = MLXChatService()
    private let config = ConfigService.shared

    // Currently loaded model container
    var currentModel: ModelContainer?
    var currentModelId: String?
    var isLoading = false
    var loadProgress: Double = 0.0

    private init() {}

    // MARK: - Models (reusing from AutocompletionService for compatibility)

    typealias ChatMessage = AutocompletionService.ChatMessage

    // MARK: - Model Loading

    /// Load a model from HuggingFace
    func loadModel(_ modelConfig: MLXModelConfig.ChatModel) async throws -> ModelContainer {
        // If switching models, unload the old one first
        if currentModel != nil, currentModelId != modelConfig.rawValue {
            print("🗑️ Unloading previous model to free memory...")
            unloadModel()

            // Give system time to reclaim memory
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        if let existing = currentModel, currentModelId == modelConfig.rawValue {
            return existing
        }

        isLoading = true
        loadProgress = 0.0
        defer { isLoading = false }

        do {
            let memoryGB = getAvailableMemoryGB()
            print("🔄 Loading MLX model: \(modelConfig.rawValue)")
            print("💾 Available memory: \(String(format: "%.1f", memoryGB))GB")

            // Check if we have enough memory
            let requiredGB = Double(modelConfig.estimatedMemoryMB) / 1024.0
            if memoryGB < requiredGB + 1.0 {
                print("⚠️ Low memory: Available \(String(format: "%.1f", memoryGB))GB, needed \(String(format: "%.1f", requiredGB))GB")
            }

            // Clear GPU cache before loading large models
            if modelConfig.estimatedMemoryMB > 3000 {
                print("🧹 Clearing caches before loading large model...")
                MLX.Memory.clearCache()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
            }

            // Load model from HuggingFace using MLXLLM
            let model = try await LLMModelFactory.shared.loadContainer(
                configuration: .init(id: modelConfig.rawValue)
            )

            self.currentModel = model
            self.currentModelId = modelConfig.rawValue

            print("✅ Model loaded successfully: \(modelConfig.rawValue)")
            return model

        } catch {
            print("❌ Failed to load model: \(error)")
            throw MLXChatError.modelLoadFailed(error)
        }
    }

    // MARK: - Memory Management

    /// Get available memory in GB
    func getAvailableMemoryGB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedGB = Double(info.resident_size) / 1_073_741_824.0
            let usedMB = Double(info.resident_size) / 1_048_576.0

            // Get memory limit
            var limit: rlim_t = 0
            var limitSize = MemoryLayout<rlim_t>.size
            sysctlbyname("kern.memorystatus_memlimit_active", &limit, &limitSize, nil, 0)
            let limitGB = Double(limit) / 1_073_741_824.0

            print("📊 Memory stats:")
            print("   Used: \(String(format: "%.2f", usedGB))GB (\(Int(usedMB))MB)")
            print("   App limit: \(limitGB > 0 ? String(format: "%.2f", limitGB) + "GB" : "Unknown")")

            // Assume 12GB total on iPhone 17 Pro
            return max(0, 12.0 - usedGB)
        }

        return 8.0 // Fallback estimate
    }

    /// Unload current model to free memory
    func unloadModel() {
        currentModel = nil
        currentModelId = nil

        // Force MLX GPU cache clear
        MLX.Memory.clearCache()

        print("🗑️ MLX model unloaded, GPU cache cleared")
    }

    // MARK: - Chat Completion

    /// Non-streaming chat completion with MLX
    func complete(messages: [ChatMessage],
                  model: MLXModelConfig.ChatModel? = nil,
                  temperature: Double? = nil,
                  maxTokens: Int? = nil) async throws -> String {

        let modelConfig = model ?? MLXModelConfig.recommendedChatModel(availableMemoryGB: getAvailableMemoryGB())
        let llmModel = try await loadModel(modelConfig)

        // Format messages into a prompt
        let prompt = formatMessagesAsPrompt(messages)

        let generateParams = GenerateParameters(
            temperature: Float(temperature ?? 0.7),
            topP: Float(0.9)
        )

        // Generate synchronously (non-streaming)
        let fullOutput = try await llmModel.perform { context in
            var output = ""

            // Prepare input using the processor
            let input = try await context.processor.prepare(input: .init(prompt: prompt))

            // Generate with the new AsyncStream-based API
            let tokenStream = try MLXLMCommon.generate(
                input: input,
                parameters: generateParams,
                context: context
            )

            for await part in tokenStream {
                if let chunk = part.chunk {
                    output += chunk
                }
            }

            return output
        }

        let memoryAfter = getAvailableMemoryGB()
        print("✅ Generation complete")
        print("💾 Available memory after: \(String(format: "%.1f", memoryAfter))GB")

        return fullOutput
    }

    /// Streaming chat completion with MLX
    func completeStream(messages: [ChatMessage],
                       model: MLXModelConfig.ChatModel? = nil,
                       temperature: Double? = nil,
                       maxTokens: Int? = nil) -> AsyncThrowingStream<String, Error> {

        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    let modelConfig = model ?? MLXModelConfig.recommendedChatModel(availableMemoryGB: getAvailableMemoryGB())
                    let llmModel = try await loadModel(modelConfig)

                    // Format messages into a prompt
                    let prompt = formatMessagesAsPrompt(messages)

                    let generateParams = GenerateParameters(
                        temperature: Float(temperature ?? 0.7),
                        topP: Float(0.9)
                    )

                    // Stream generation
                    try await llmModel.perform { context in
                        // Prepare input using the processor
                        let input = try await context.processor.prepare(input: .init(prompt: prompt))

                        // Generate streaming tokens
                        let tokenStream = try MLXLMCommon.generate(
                            input: input,
                            parameters: generateParams,
                            context: context
                        )

                        for await part in tokenStream {
                            if let chunk = part.chunk {
                                continuation.yield(chunk)
                            }
                        }
                    }

                    continuation.finish()

                    let memoryAfter = getAvailableMemoryGB()
                    print("✅ Streaming complete")
                    print("💾 Available memory after: \(String(format: "%.1f", memoryAfter))GB")

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Prompt Formatting

    /// Format chat messages into a single prompt string
    /// Uses Qwen3 chat template format (compatible with multiple models)
    private func formatMessagesAsPrompt(_ messages: [ChatMessage]) -> String {
        var prompt = ""

        for message in messages {
            switch message.role {
            case "system":
                prompt += "<|im_start|>system\n\(message.content)<|im_end|>\n"
            case "user":
                prompt += "<|im_start|>user\n\(message.content)<|im_end|>\n"
            case "assistant":
                prompt += "<|im_start|>assistant\n\(message.content)<|im_end|>\n"
            default:
                prompt += "\(message.content)\n"
            }
        }

        // Add assistant prompt to trigger response
        prompt += "<|im_start|>assistant\n"

        return prompt
    }

    // MARK: - Convenience Methods

    /// Simple prompt-based completion (user message)
    func prompt(_ userMessage: String,
                systemPrompt: String? = nil,
                model: MLXModelConfig.ChatModel? = nil,
                temperature: Double? = nil,
                maxTokens: Int? = nil) async throws -> String {
        var messages: [ChatMessage] = []

        if let systemPrompt = systemPrompt {
            messages.append(ChatMessage(role: "system", content: systemPrompt))
        }

        messages.append(ChatMessage(role: "user", content: userMessage))

        return try await complete(
            messages: messages,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    /// Simple streaming prompt
    func promptStream(_ userMessage: String,
                     systemPrompt: String? = nil,
                     model: MLXModelConfig.ChatModel? = nil,
                     temperature: Double? = nil,
                     maxTokens: Int? = nil) -> AsyncThrowingStream<String, Error> {
        var messages: [ChatMessage] = []

        if let systemPrompt = systemPrompt {
            messages.append(ChatMessage(role: "system", content: systemPrompt))
        }

        messages.append(ChatMessage(role: "user", content: userMessage))

        return completeStream(
            messages: messages,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }
}

// MARK: - Errors

enum MLXChatError: Error, LocalizedError {
    case modelLoadFailed(Error)
    case generationFailed(Error)
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let error):
            return "Failed to load MLX model: \(error.localizedDescription)"
        case .generationFailed(let error):
            return "Failed to generate response: \(error.localizedDescription)"
        case .modelNotLoaded:
            return "No model is currently loaded"
        }
    }
}
