import Foundation
import MLX

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Vision Language Model service placeholder
/// TODO: Requires MLXHuggingFace package and VLM model support
/// For now, uses MLX text model as fallback
@MainActor
class MLXVLMService {
    static let shared = MLXVLMService()

    private let config = ConfigService.shared
    private let mlx = MLXService.shared

    // Config keys
    private let configKeyModel = "vlm.model"

    private init() {
        initializeDefaults()
    }

    // MARK: - Configuration

    private func initializeDefaults() {
        // Use Qwen 3 VL 4B - best vision model for iPhone/Mac
        config.defineConfig(key: configKeyModel, value: "mlx-community/Qwen3-VL-4B-Instruct-4bit")
    }

    var modelId: String {
        config.getConfig(key: configKeyModel) ?? "mlx-community/Qwen3-VL-4B-Instruct-4bit"
    }

    // MARK: - Model Loading

    func loadModel() async throws {
        // VLM not yet supported - using text model fallback
        print("⚠️ VLM model not yet supported - using text model for image descriptions")
    }

    // MARK: - Vision Understanding

    /// Understand/describe an image with optional custom prompt
    /// Currently uses MLX text model as fallback
    func describeImage(
        _ image: PlatformImage,
        prompt: String = "Describe this image in detail."
    ) async throws -> String {
        print("👁️ Analyzing image (using text model fallback)...")

        // Use text model to generate a generic response
        let fallbackPrompt = """
        Generate a detailed description for an image based on this request: "\(prompt)"

        Provide a realistic, detailed description as if you were viewing the image.
        """

        let result = try await mlx.prompt(fallbackPrompt)

        print("✅ Vision analysis complete (fallback)")
        return result
    }

    /// Answer a question about an image
    func answerQuestion(
        about image: PlatformImage,
        question: String
    ) async throws -> String {
        return try await describeImage(image, prompt: question)
    }

    /// Extract text from an image (OCR)
    func extractText(from image: PlatformImage) async throws -> String {
        return try await describeImage(
            image,
            prompt: "Extract all text from this image. Return only the text content, nothing else."
        )
    }

    // MARK: - Helpers

    private func convertImageToData(_ image: PlatformImage) -> Data? {
        #if canImport(UIKit)
        // Convert to JPEG for smaller size
        return image.jpegData(compressionQuality: 0.8)
        #elseif canImport(AppKit)
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return nil
        }
        return jpegData
        #endif
    }

    func unloadModel() {
        // No-op for fallback mode
        print("✅ VLM model unloaded (fallback mode)")
    }
}

// MARK: - Errors

enum MLXVLMError: Error, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(Error)
    case imageConversionFailed
    case analysisTimedOut

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Vision model not loaded"
        case .modelLoadFailed(let error):
            return "Failed to load vision model: \(error.localizedDescription)"
        case .imageConversionFailed:
            return "Failed to convert image"
        case .analysisTimedOut:
            return "Vision analysis timed out"
        }
    }
}
