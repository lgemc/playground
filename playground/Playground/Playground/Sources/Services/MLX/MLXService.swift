import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Unified facade for all MLX services - Native On-Device AI
/// Everything runs locally with MLX Swift - no server required!
class MLXService {
    static let shared = MLXService()

    // Sub-services - all running natively on-device
    let chat = MLXChatService.shared
    let whisper = MLXWhisperService.shared
    let tts = MLXTTSService.shared
    let image = MLXImageService.shared
    let modelPool = MLXModelPool.shared

    private let config = ConfigService.shared

    private init() {
        // Set up default configuration
        setupDefaultConfig()
    }

    // MARK: - Configuration

    private func setupDefaultConfig() {
        // Device configuration
        config.defineConfig(key: "mlx.available_memory_gb", value: 12)

        // Chat configuration
        config.defineConfig(key: "mlx.temperature", value: 0.7)
        config.defineConfig(key: "mlx.max_tokens", value: 1024)

        // Model execution parameters
        config.defineConfig(key: "mlx.key_cache_type", value: "q8_0")  // Key cache quantization
        config.defineConfig(key: "mlx.value_cache_type", value: "q8_0")  // Value cache quantization
        config.defineConfig(key: "mlx.flash_attention", value: true)  // Enable flash attention
        config.defineConfig(key: "mlx.physical_batch_size", value: 512)  // Physical batch size
        config.defineConfig(key: "mlx.batch_size", value: 512)  // Logical batch size
        config.defineConfig(key: "mlx.context_size", value: 2048)  // Context window size

        // Model selection - you have 11.8GB available, can use larger models!
        // qwen3_5_2b_6bit = ~1.6GB (balanced, fast, 262K context)
        // qwen3_5_4b_4bit = ~2.8GB (default, better quality, 262K context)
        // mistral_7b_4bit = ~4.5GB (best quality, slower)
        config.defineConfig(key: "mlx.chat_model", value: MLXModelConfig.ChatModel.qwen3_5_4b_4bit.rawValue)
        config.defineConfig(key: "mlx.whisper_model", value: MLXModelConfig.WhisperModel.small.rawValue)
        config.defineConfig(key: "mlx.tts_model", value: MLXModelConfig.TTSModel.kokoro.rawValue)
        config.defineConfig(key: "mlx.image_model", value: MLXModelConfig.ImageModel.sdxlTurbo.rawValue)

        // Fallback to OpenAI API if model loading fails
        config.defineConfig(key: "mlx.fallback_to_openai", value: true)
    }

    /// Check if MLX is available (always true for native implementation)
    func isAvailable() -> Bool {
        return true  // Native MLX Swift is always available on supported devices
    }

    /// Get device status including loaded models
    func getDeviceStatus() async -> DeviceStatus {
        let loadedModels = await modelPool.getLoadedModels()
        let _ = await modelPool.getTotalMemoryUsageMB()
        let availableMemory = chat.getAvailableMemoryGB()

        return DeviceStatus(
            status: "ready",
            loadedModels: loadedModels.map { meta in
                DeviceStatus.LoadedModel(
                    modelId: meta.modelId,
                    type: meta.type.description,
                    memoryUsageMB: meta.estimatedMemoryMB,
                    loadedAt: meta.loadedAt?.ISO8601Format() ?? ""
                )
            },
            availableMemoryMB: Int(availableMemory * 1024),
            totalMemoryMB: 12 * 1024,  // iPhone 17 Pro
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    // MARK: - Convenience Methods with Fallback

    /// Chat completion with automatic fallback to OpenAI API
    func chatComplete(messages: [AutocompletionService.ChatMessage],
                     temperature: Double? = nil,
                     maxTokens: Int? = nil) async throws -> String {

        // Try MLX first
        do {
            return try await chat.complete(
                messages: messages,
                temperature: temperature,
                maxTokens: maxTokens
            )
        } catch {
            print("MLX chat failed: \(error)")

            // Fallback to OpenAI if enabled
            if config.getBool(key: "mlx.fallback_to_openai", default: true) {
                print("Falling back to OpenAI API...")
                let result = await AutocompletionService.shared.complete(
                    messages: messages,
                    temperature: temperature,
                    maxTokens: maxTokens
                )
                return try result.get()
            }

            throw error
        }
    }

    /// Chat streaming with automatic fallback
    func chatCompleteStream(messages: [AutocompletionService.ChatMessage],
                          temperature: Double? = nil,
                          maxTokens: Int? = nil) -> AsyncThrowingStream<String, Error> {

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Try MLX streaming
                    for try await chunk in chat.completeStream(
                        messages: messages,
                        temperature: temperature,
                        maxTokens: maxTokens
                    ) {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    print("MLX streaming failed: \(error)")

                    // Fallback to OpenAI if enabled
                    if config.getBool(key: "mlx.fallback_to_openai", default: true) {
                        print("Falling back to OpenAI API...")
                        do {
                            for try await chunk in AutocompletionService.shared.completeStream(
                                messages: messages,
                                temperature: temperature,
                                maxTokens: maxTokens
                            ) {
                                continuation.yield(chunk)
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    /// Simple prompt with fallback
    func prompt(_ text: String,
               systemPrompt: String? = nil,
               temperature: Double? = nil,
               maxTokens: Int? = nil) async throws -> String {

        var messages: [AutocompletionService.ChatMessage] = []

        if let systemPrompt = systemPrompt {
            messages.append(AutocompletionService.ChatMessage(role: "system", content: systemPrompt))
        }

        messages.append(AutocompletionService.ChatMessage(role: "user", content: text))

        return try await chatComplete(
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    /// Simple streaming prompt with fallback
    func promptStream(_ text: String,
                     systemPrompt: String? = nil,
                     temperature: Double? = nil,
                     maxTokens: Int? = nil) -> AsyncThrowingStream<String, Error> {

        var messages: [AutocompletionService.ChatMessage] = []

        if let systemPrompt = systemPrompt {
            messages.append(AutocompletionService.ChatMessage(role: "system", content: systemPrompt))
        }

        messages.append(AutocompletionService.ChatMessage(role: "user", content: text))

        return chatCompleteStream(
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    /// Unload all models to free memory
    func unloadAllModels() async {
        chat.unloadModel()
        whisper.unloadModel()
        image.unloadModel()
        await modelPool.clearAll()
    }

    // MARK: - Model Execution Configuration

    /// Configure model execution parameters
    ///
    /// **Important**: In MLX Swift, some parameters work differently than in llama.cpp or vLLM:
    /// - **keyCacheType/valueCacheType**: These are informational metadata in MLX Swift. Actual
    ///   quantization is determined by the model file (e.g., "4bit" in model name).
    /// - **flashAttention**: Informational - MLX uses optimized attention by default.
    /// - **physicalBatchSize**: Maps to `GenerateParameters.prefillStepSize` (tokens per step).
    /// - **batchSize**: Logical batch size (for reference, not directly used in single inference).
    /// - **contextSize**: Controls GPU cache allocation via `MLX.GPU.set(cacheLimit:)`.
    ///
    /// - Parameters:
    ///   - keyCacheType: Key cache quantization type (metadata: "q8_0", "q4_0", "f16")
    ///   - valueCacheType: Value cache quantization type (metadata: "q8_0", "q4_0", "f16")
    ///   - flashAttention: Enable flash attention (informational - always optimized)
    ///   - physicalBatchSize: Prefill step size in tokens (default: 512)
    ///   - batchSize: Logical batch size for reference (default: 512)
    ///   - contextSize: Maximum context window size in tokens (default: 2048)
    func configureExecution(
        keyCacheType: String? = nil,
        valueCacheType: String? = nil,
        flashAttention: Bool? = nil,
        physicalBatchSize: Int? = nil,
        batchSize: Int? = nil,
        contextSize: Int? = nil
    ) {
        if let keyCacheType = keyCacheType {
            config.setConfig(key: "mlx.key_cache_type", value: keyCacheType)
        }
        if let valueCacheType = valueCacheType {
            config.setConfig(key: "mlx.value_cache_type", value: valueCacheType)
        }
        if let flashAttention = flashAttention {
            config.setConfig(key: "mlx.flash_attention", value: flashAttention)
        }
        if let physicalBatchSize = physicalBatchSize {
            config.setConfig(key: "mlx.physical_batch_size", value: physicalBatchSize)
        }
        if let batchSize = batchSize {
            config.setConfig(key: "mlx.batch_size", value: batchSize)
        }
        if let contextSize = contextSize {
            config.setConfig(key: "mlx.context_size", value: contextSize)
            // Reconfigure GPU cache when context size changes
            Task { @MainActor in
                chat.setupMLXGPUCache()
            }
        }
    }

    /// Get current execution configuration
    func getExecutionConfig() -> ExecutionConfig {
        return ExecutionConfig(
            keyCacheType: config.getString(key: "mlx.key_cache_type", default: "q8_0"),
            valueCacheType: config.getString(key: "mlx.value_cache_type", default: "q8_0"),
            flashAttention: config.getBool(key: "mlx.flash_attention", default: true),
            physicalBatchSize: config.getInt(key: "mlx.physical_batch_size", default: 512),
            batchSize: config.getInt(key: "mlx.batch_size", default: 512),
            contextSize: config.getInt(key: "mlx.context_size", default: 2048)
        )
    }
}

// MARK: - Supporting Types

/// Model execution configuration
struct ExecutionConfig {
    let keyCacheType: String
    let valueCacheType: String
    let flashAttention: Bool
    let physicalBatchSize: Int
    let batchSize: Int
    let contextSize: Int

    var description: String {
        """
        MLX Execution Configuration:
        - Key Cache Type: \(keyCacheType) (flash attention)
        - Value Cache Type: \(valueCacheType)
        - Flash Attention: \(flashAttention ? "enabled" : "disabled")
        - Physical Batch Size: \(physicalBatchSize)
        - Batch Size: \(batchSize)
        - Context Size: \(contextSize) tokens
        """
    }
}

struct DeviceStatus: Codable {
    let status: String  // "ready", "degraded"
    let loadedModels: [LoadedModel]
    let availableMemoryMB: Int
    let totalMemoryMB: Int
    let uptime: TimeInterval

    enum CodingKeys: String, CodingKey {
        case status
        case loadedModels = "loaded_models"
        case availableMemoryMB = "available_memory_mb"
        case totalMemoryMB = "total_memory_mb"
        case uptime
    }

    struct LoadedModel: Codable {
        let modelId: String
        let type: String  // "chat", "whisper", "tts", "image"
        let memoryUsageMB: Int
        let loadedAt: String  // ISO 8601 timestamp

        enum CodingKeys: String, CodingKey {
            case modelId = "model_id"
            case type
            case memoryUsageMB = "memory_usage_mb"
            case loadedAt = "loaded_at"
        }
    }
}

extension MLXModelMetadata.ModelType {
    var description: String {
        switch self {
        case .chat: return "chat"
        case .whisper: return "whisper"
        case .tts: return "tts"
        case .image: return "image"
        }
    }
}

enum MLXServiceError: Error {
    case modelLoadFailed(Error)
    case noAvailableService
    case invalidConfiguration
}
