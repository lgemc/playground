import Foundation

/// Configuration for MLX models optimized for iPhone 17 Pro (12GB RAM)
enum MLXModelConfig {

    // MARK: - Chat Models

    enum ChatModel: String, CaseIterable {
        /// Fastest option: LFM2.5 1.2B 4-bit quantized
        /// Performance: 70 tokens/sec on iPhone, 124 tokens/sec on iPad
        case lfm25_1b_4bit = "mlx-community/LFM2.5-1.2B-4bit"

        /// Balanced: 3B parameter model, 4-bit quantized
        /// Performance: 10-20 tokens/sec
        case llama3_3b_4bit = "mlx-community/Llama-3.2-3B-Instruct-4bit"

        /// High quality: 7B parameter model, 4-bit quantized
        /// Performance: 8-15 tokens/sec (slower but higher quality)
        case mistral_7b_4bit = "mlx-community/Mistral-7B-Instruct-v0.3-4bit"

        var estimatedMemoryMB: Int {
            switch self {
            case .lfm25_1b_4bit: return 800  // ~800MB
            case .llama3_3b_4bit: return 2000  // ~2GB
            case .mistral_7b_4bit: return 4500  // ~4.5GB
            }
        }

        var tokensPerSecond: Int {
            switch self {
            case .lfm25_1b_4bit: return 70
            case .llama3_3b_4bit: return 15
            case .mistral_7b_4bit: return 10
            }
        }
    }

    // MARK: - Speech-to-Text Models

    enum WhisperModel: String, CaseIterable {
        /// Smallest: 39M parameters, ~150MB
        case tiny = "mlx-community/whisper-tiny"

        /// Small: 244M parameters, ~500MB
        case base = "mlx-community/whisper-base"

        /// Medium: 769M parameters, ~1.5GB
        case small = "mlx-community/whisper-small"

        /// Large: distilled version for better performance
        case distilLargeV3 = "mlx-community/distil-whisper-large-v3"

        var estimatedMemoryMB: Int {
            switch self {
            case .tiny: return 150
            case .base: return 500
            case .small: return 1500
            case .distilLargeV3: return 2000
            }
        }
    }

    // MARK: - Text-to-Speech Models

    enum TTSModel: String, CaseIterable {
        /// Fast, multilingual, 54 voice presets, 82M parameters
        case kokoro = "mlx-community/kokoro-82m"

        /// Qwen3 TTS: 0.6B parameters, 4-bit quantized
        case qwen3 = "mlx-community/Qwen3-TTS-0.6B-4bit"

        /// CosyVoice: 9 languages, DiT flow matching
        case cosyvoice = "mlx-community/CosyVoice-TTS"

        var estimatedMemoryMB: Int {
            switch self {
            case .kokoro: return 350  // ~350MB
            case .qwen3: return 400  // ~400MB (4-bit)
            case .cosyvoice: return 800  // ~800MB
            }
        }

        var supportsStreaming: Bool {
            switch self {
            case .kokoro: return true
            case .qwen3: return true
            case .cosyvoice: return true
            }
        }
    }

    // MARK: - Text-to-Image Models

    enum ImageModel: String, CaseIterable {
        /// Stable Diffusion 1.5 optimized for MLX
        case sd15 = "mlx-community/stable-diffusion-1.5"

        /// Stable Diffusion 2.1 optimized for MLX
        case sd21 = "mlx-community/stable-diffusion-2.1"

        /// SDXL Turbo: fast generation (1-4 steps)
        case sdxlTurbo = "mlx-community/sdxl-turbo"

        var estimatedMemoryMB: Int {
            switch self {
            case .sd15: return 3000  // ~3GB
            case .sd21: return 3500  // ~3.5GB
            case .sdxlTurbo: return 5000  // ~5GB
            }
        }

        var defaultSteps: Int {
            switch self {
            case .sd15: return 25
            case .sd21: return 30
            case .sdxlTurbo: return 4  // Optimized for speed
            }
        }
    }

    // MARK: - Model Selection

    /// Automatically select best chat model based on available memory
    static func recommendedChatModel(availableMemoryGB: Double) -> ChatModel {
        if availableMemoryGB >= 8 {
            return .llama3_3b_4bit  // Balanced - avoid OOM
        } else if availableMemoryGB >= 4 {
            return .llama3_3b_4bit  // Balanced
        } else {
            return .lfm25_1b_4bit  // Fast & efficient
        }
    }

    /// Automatically select best Whisper model based on available memory
    static func recommendedWhisperModel(availableMemoryGB: Double) -> WhisperModel {
        if availableMemoryGB >= 3 {
            return .distilLargeV3  // Best quality
        } else if availableMemoryGB >= 2 {
            return .small
        } else if availableMemoryGB >= 1 {
            return .base
        } else {
            return .tiny
        }
    }

    /// Automatically select best TTS model
    static func recommendedTTSModel() -> TTSModel {
        return .kokoro  // Fast, multilingual, excellent quality
    }

    /// Automatically select best image model based on available memory
    static func recommendedImageModel(availableMemoryGB: Double) -> ImageModel {
        if availableMemoryGB >= 6 {
            return .sdxlTurbo  // Fast generation
        } else if availableMemoryGB >= 4 {
            return .sd21
        } else {
            return .sd15
        }
    }
}

/// Model state tracking
enum MLXModelState {
    case notLoaded
    case loading
    case loaded
    case failed(Error)
}

/// Generic model metadata
struct MLXModelMetadata {
    let modelId: String
    let type: ModelType
    let estimatedMemoryMB: Int
    var state: MLXModelState = .notLoaded
    var loadedAt: Date?

    enum ModelType {
        case chat
        case whisper
        case tts
        case image
    }
}
