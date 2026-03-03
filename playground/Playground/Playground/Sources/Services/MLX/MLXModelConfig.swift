import Foundation

/// Configuration for MLX models optimized for iPhone 17 Pro (12GB RAM)
enum MLXModelConfig {

    // MARK: - Chat Models

    enum ChatModel: String, CaseIterable {
        /// Fastest option: LFM2.5 1.2B 4-bit quantized
        /// Performance: 70 tokens/sec on iPhone, 124 tokens/sec on iPad
        case lfm25_1b_4bit = "mlx-community/LFM2.5-1.2B-4bit"

        /// Balanced: Qwen3 1.7B, 6-bit quantized (32K context)
        /// Performance: 25-35 tokens/sec
        case qwen3_1_7b_6bit = "mlx-community/Qwen3-1.7B-6bit"

        /// Higher quality: Qwen3 4B, 6-bit quantized (32K context)
        /// Performance: 15-20 tokens/sec
        case qwen3_4b_6bit = "mlx-community/Qwen3-4B-6bit"

        /// High quality: 7B parameter model, 4-bit quantized
        /// Performance: 8-15 tokens/sec (slower but higher quality)
        case mistral_7b_4bit = "mlx-community/Mistral-7B-Instruct-v0.3-4bit"

        var estimatedMemoryMB: Int {
            switch self {
            case .lfm25_1b_4bit: return 800  // ~800MB
            case .qwen3_1_7b_6bit: return 1400  // ~1.4GB (6-bit quantized)
            case .qwen3_4b_6bit: return 2800  // ~2.8GB (6-bit quantized)
            case .mistral_7b_4bit: return 4500  // ~4.5GB
            }
        }

        var tokensPerSecond: Int {
            switch self {
            case .lfm25_1b_4bit: return 70
            case .qwen3_1_7b_6bit: return 30
            case .qwen3_4b_6bit: return 18
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

    // MARK: - Text-to-Image Models (Stable Diffusion - DEPRECATED)

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

    // MARK: - Flux Models (NEW)

    enum FluxModel: String, CaseIterable {
        /// Flux Schnell: Fast generation (4 steps), no guidance
        case fluxSchnell = "flux-schnell"

        /// Flux Dev: High quality (20+ steps), with guidance
        case fluxDev = "flux-dev"

        /// Flux Kontext: Context-aware generation
        case fluxKontext = "flux-kontext"

        var estimatedMemoryMB: Int {
            switch self {
            case .fluxSchnell: return 12000  // ~12GB (can use quantization)
            case .fluxDev: return 12000      // ~12GB (can use quantization)
            case .fluxKontext: return 12000  // ~12GB (can use quantization)
            }
        }

        var defaultSteps: Int {
            switch self {
            case .fluxSchnell: return 4   // Optimized for speed
            case .fluxDev: return 20      // Quality mode
            case .fluxKontext: return 20  // Quality mode
            }
        }

        // FIXME: FluxConfiguration not available due to dependency conflict
        // var configuration: FluxConfiguration {
        //     switch self {
        //     case .fluxSchnell: return .flux1Schnell
        //     case .fluxDev: return .flux1Dev
        //     case .fluxKontext: return .flux1Kontext
        //     }
        // }
    }

    // MARK: - Model Selection

    /// Automatically select best chat model based on available memory
    static func recommendedChatModel(availableMemoryGB: Double) -> ChatModel {
        if availableMemoryGB >= 8 {
            return .qwen3_1_7b_6bit  // Balanced - avoid OOM
        } else if availableMemoryGB >= 4 {
            return .qwen3_1_7b_6bit  // Balanced
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

    /// Automatically select best image model based on available memory (DEPRECATED - use recommendedFluxModel)
    static func recommendedImageModel(availableMemoryGB: Double) -> ImageModel {
        if availableMemoryGB >= 6 {
            return .sdxlTurbo  // Fast generation
        } else if availableMemoryGB >= 4 {
            return .sd21
        } else {
            return .sd15
        }
    }

    /// Automatically select best Flux model based on available memory
    static func recommendedFluxModel(availableMemoryGB: Double) -> FluxModel {
        // Flux-schnell is fastest and works well with quantization
        // Even on devices with less memory, quantization makes it viable
        if availableMemoryGB >= 8 {
            return .fluxSchnell  // Fast, high quality
        } else {
            // Use quantization for lower memory devices
            return .fluxSchnell  // Will use quantization automatically
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
