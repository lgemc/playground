import Foundation
// NOTE: DiffusionKit temporarily disabled due to dependency conflict
// (DiffusionKit requires swift-transformers 0.1.8, mlx-swift-lm requires 1.0.0+)
// import DiffusionKit
import MLX

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

/// Native on-device text-to-image service using DiffusionKit + MLX
/// Runs entirely on-device with Metal GPU - no server required!
/// NOTE: Currently disabled due to DiffusionKit dependency conflict
class MLXImageService {
    static let shared = MLXImageService()
    private let config = ConfigService.shared

    // Currently loaded Stable Diffusion pipeline
    // private var pipeline: DiffusionPipeline?
    private var currentModelId: String?

    private init() {}

    // MARK: - Model Loading

    /// Load a Stable Diffusion model (lazy loading)
    /// NOTE: Currently disabled - throws error
    func loadModel(_ modelConfig: MLXModelConfig.ImageModel) async throws {
        throw MLXImageError.modelLoadFailed(NSError(domain: "MLXImageService", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Image generation temporarily disabled due to DiffusionKit dependency conflict"
        ]))
    }

    // MARK: - Image Generation

    /// Generate images from text prompt
    /// NOTE: Currently disabled - throws error
    func generate(prompt: String,
                 model: MLXModelConfig.ImageModel? = nil,
                 negativePrompt: String? = nil,
                 width: Int = 512,
                 height: Int = 512,
                 steps: Int? = nil,
                 guidanceScale: Double = 7.5,
                 seed: Int? = nil,
                 numImages: Int = 1) async throws -> [PlatformImage] {

        throw MLXImageError.modelLoadFailed(NSError(domain: "MLXImageService", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Image generation temporarily disabled due to DiffusionKit dependency conflict"
        ]))
    }

    /// Generate single image from text prompt
    func generateSingle(prompt: String,
                       model: MLXModelConfig.ImageModel? = nil,
                       negativePrompt: String? = nil,
                       width: Int = 512,
                       height: Int = 512,
                       steps: Int? = nil,
                       guidanceScale: Double = 7.5,
                       seed: Int? = nil) async throws -> PlatformImage {

        let images = try await generate(
            prompt: prompt,
            model: model,
            negativePrompt: negativePrompt,
            width: width,
            height: height,
            steps: steps,
            guidanceScale: guidanceScale,
            seed: seed,
            numImages: 1
        )

        guard let image = images.first else {
            throw MLXImageError.noImagesGenerated
        }

        return image
    }

    /// Generate image and save to file
    func generateToFile(prompt: String,
                       outputURL: URL,
                       model: MLXModelConfig.ImageModel? = nil,
                       negativePrompt: String? = nil,
                       width: Int = 512,
                       height: Int = 512,
                       steps: Int? = nil,
                       guidanceScale: Double = 7.5,
                       seed: Int? = nil) async throws {

        let image = try await generateSingle(
            prompt: prompt,
            model: model,
            negativePrompt: negativePrompt,
            width: width,
            height: height,
            steps: steps,
            guidanceScale: guidanceScale,
            seed: seed
        )

        // Save as PNG
        #if canImport(UIKit)
        guard let pngData = image.pngData() else {
            throw MLXImageError.imageEncodingFailed
        }
        #elseif canImport(AppKit)
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw MLXImageError.imageEncodingFailed
        }
        #endif

        try pngData.write(to: outputURL)
    }

    /// Streaming image generation with progress updates
    /// NOTE: Currently disabled - throws error
    func generateWithProgress(prompt: String,
                            model: MLXModelConfig.ImageModel? = nil,
                            negativePrompt: String? = nil,
                            width: Int = 512,
                            height: Int = 512,
                            steps: Int? = nil,
                            guidanceScale: Double = 7.5,
                            seed: Int? = nil) -> AsyncThrowingStream<GenerationProgress, Error> {

        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: MLXImageError.modelLoadFailed(NSError(domain: "MLXImageService", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Image generation temporarily disabled due to DiffusionKit dependency conflict"
            ])))
        }
    }

    // MARK: - Helper Methods

    private func getDefaultImageModel() -> MLXModelConfig.ImageModel {
        let availableMemoryGB = MLXChatService.shared.getAvailableMemoryGB()
        return MLXModelConfig.recommendedImageModel(availableMemoryGB: availableMemoryGB)
    }

    /// Unload current model to free memory
    func unloadModel() {
        // pipeline = nil
        currentModelId = nil
        MLX.Memory.clearCache()
    }
}

// MARK: - Supporting Types

struct GenerationConfig {
    let prompt: String
    let negativePrompt: String?
    let width: Int
    let height: Int
    let steps: Int
    let guidanceScale: Float
    let seed: UInt32
}

struct GenerationProgress: Codable {
    let step: Int
    let totalSteps: Int
    let previewImage: String?  // Base64 encoded preview (if available)
    let isComplete: Bool

    enum CodingKeys: String, CodingKey {
        case step
        case totalSteps = "total_steps"
        case previewImage = "preview_image"
        case isComplete = "is_complete"
    }

    var progress: Double {
        return Double(step) / Double(totalSteps)
    }

    var previewUIImage: PlatformImage? {
        guard let previewImage = previewImage,
              let data = Data(base64Encoded: previewImage) else {
            return nil
        }
        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #endif
    }
}

enum MLXImageError: Error {
    case invalidResponse
    case invalidImageData
    case noImagesGenerated
    case imageEncodingFailed
    case modelLoadFailed(Error)
}
