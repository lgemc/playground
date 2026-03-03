import Foundation
import Alamofire

// PlatformImage is already defined in MLXImageService.swift
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Service for generating images using both remote API and on-device MLX
/// Supports automatic fallback: MLX (on-device) -> Remote API
class ImageGenerationService {
    static let shared = ImageGenerationService()
    private let config = ConfigService.shared
    private let mlxFlux = MLXFluxService.shared

    // Config keys
    private let configKeyUrl = "image_generation.api_url"
    private let configKeyModel = "image_generation.model"
    private let configKeyUseMLX = "image_generation.use_mlx"
    private let configKeyMLXModel = "image_generation.mlx_model"

    private init() {
        initializeDefaults()
    }

    // MARK: - Configuration

    private func initializeDefaults() {
        config.defineConfig(key: configKeyUrl, value: "")  // Optional remote API
        config.defineConfig(key: configKeyModel, value: "flux-schnell")
        config.defineConfig(key: configKeyUseMLX, value: "true")  // Enable MLX Flux
        config.defineConfig(key: configKeyMLXModel, value: "flux-schnell")
    }

    var apiUrl: String {
        config.getConfig(key: configKeyUrl) ?? ""
    }

    var model: String {
        config.getConfig(key: configKeyModel) ?? "flux-schnell"
    }

    var useMLX: Bool {
        (config.getConfig(key: configKeyUseMLX) ?? "true") == "true"
    }

    var mlxModel: MLXModelConfig.FluxModel {
        let modelName = config.getConfig(key: configKeyMLXModel) ?? "flux-schnell"
        return MLXModelConfig.FluxModel(rawValue: modelName) ?? .fluxSchnell
    }

    var isConfigured: Bool {
        useMLX || !apiUrl.isEmpty
    }

    // MARK: - Image Generation

    /// Generate image from text prompt and save to file system
    /// - Parameters:
    ///   - prompt: Text description of the image
    ///   - width: Image width (default: 1024)
    ///   - height: Image height (default: 1024)
    ///   - steps: Number of inference steps (default: model-specific)
    ///   - guidanceScale: Guidance scale for generation
    ///   - seed: Random seed for reproducibility
    /// - Returns: URL of the saved image file
    func generateImage(
        prompt: String,
        width: Int = 1024,
        height: Int = 1024,
        steps: Int? = nil,
        guidanceScale: Double = 3.5,
        seed: Int? = nil
    ) async throws -> URL {
        guard isConfigured else {
            throw ImageGenerationError.notConfigured
        }

        // Try MLX first if enabled
        if useMLX {
            do {
                print("🎨 Generating image with MLX Flux")
                print("   Model: \(mlxModel.rawValue)")
                print("   Prompt: \(prompt.prefix(50))...")
                print("   Size: \(width)x\(height)")

                let image = try await mlxFlux.generate(
                    prompt: prompt,
                    model: mlxModel,
                    width: width,
                    height: height,
                    steps: steps,
                    guidanceScale: guidanceScale,
                    seed: seed
                )

                let fileURL = try saveImageToFile(
                    image: image,
                    prompt: prompt
                )

                print("✅ Image saved (MLX): \(fileURL.path)")
                return fileURL
            } catch {
                print("⚠️ MLX Flux failed, falling back to remote API: \(error)")
                // Fall through to remote API
            }
        }

        // Fallback to remote API
        if !apiUrl.isEmpty {
            return try await generateImageViaAPI(
                prompt: prompt,
                width: width,
                height: height,
                steps: steps,
                guidanceScale: guidanceScale,
                seed: seed
            )
        }

        throw ImageGenerationError.notConfigured
    }

    /// Generate image using remote API
    private func generateImageViaAPI(
        prompt: String,
        width: Int,
        height: Int,
        steps: Int?,
        guidanceScale: Double,
        seed: Int?
    ) async throws -> URL {
        // Prepare request parameters
        var parameters: [String: String] = [
            "prompt": prompt,
            "width": String(width),
            "height": String(height),
            "guidance_scale": String(guidanceScale)
        ]

        if let steps = steps {
            parameters["steps"] = String(steps)
        }

        if let seed = seed {
            parameters["seed"] = String(seed)
        }

        let url = "\(apiUrl)/v1/images/generations"

        print("🎨 Generating image via API: \(prompt.prefix(50))...")
        print("   API: \(url)")

        // Make API request
        return try await withCheckedThrowingContinuation { continuation in
            AF.request(
                url,
                method: .post,
                parameters: parameters,
                encoding: URLEncoding.default
            )
            .validate()
            .responseData { response in
                switch response.result {
                case .success(let imageData):
                    do {
                        // Convert data to image
                        #if canImport(UIKit)
                        guard let image = UIImage(data: imageData) else {
                            throw ImageGenerationError.invalidImageData
                        }
                        #elseif canImport(AppKit)
                        guard let image = NSImage(data: imageData) else {
                            throw ImageGenerationError.invalidImageData
                        }
                        #endif

                        // Save to file
                        let fileURL = try self.saveImageToFile(
                            image: image,
                            prompt: prompt
                        )

                        print("✅ Image saved (API): \(fileURL.path)")
                        continuation.resume(returning: fileURL)
                    } catch {
                        print("❌ Failed to save image: \(error)")
                        continuation.resume(throwing: error)
                    }

                case .failure(let error):
                    print("❌ API request failed: \(error)")
                    if let data = response.data, let errorMessage = String(data: data, encoding: .utf8) {
                        print("   Error response: \(errorMessage)")
                    }
                    continuation.resume(throwing: ImageGenerationError.apiRequestFailed(error))
                }
            }
        }
    }

    /// Generate image with progress updates (MLX only)
    func generateImageWithProgress(
        prompt: String,
        width: Int = 1024,
        height: Int = 1024,
        steps: Int? = nil,
        guidanceScale: Double = 3.5,
        seed: Int? = nil
    ) -> AsyncThrowingStream<GenerationProgress, Error> {
        guard useMLX else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: ImageGenerationError.progressNotSupported)
            }
        }

        return mlxFlux.generateWithProgress(
            prompt: prompt,
            model: mlxModel,
            width: width,
            height: height,
            steps: steps,
            guidanceScale: guidanceScale,
            seed: seed
        )
    }

    // MARK: - File Management

    /// Save image to file in generated/images/ folder
    private func saveImageToFile(image: PlatformImage, prompt: String) throws -> URL {
        let documentsDirectory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        // Create data/file_system/storage directory structure
        let dataDirectory = documentsDirectory
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("file_system", isDirectory: true)
            .appendingPathComponent("storage", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

        // Create generated/images folder structure
        let imagesDirectory = dataDirectory
            .appendingPathComponent("generated", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        // Generate filename from prompt
        let filename = sanitizeFilename(prompt)
        let fileURL = imagesDirectory.appendingPathComponent(filename)

        // Save as PNG
        #if canImport(UIKit)
        guard let pngData = image.pngData() else {
            throw ImageGenerationError.imageEncodingFailed
        }
        #elseif canImport(AppKit)
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw ImageGenerationError.imageEncodingFailed
        }
        #endif

        try pngData.write(to: fileURL)

        return fileURL
    }

    /// Sanitize prompt into valid filename
    private func sanitizeFilename(_ prompt: String) -> String {
        // Take first few words of prompt
        let words = prompt.split(separator: " ").prefix(5)
        var cleanName = words.joined(separator: "_")

        // Replace spaces with underscores
        cleanName = cleanName.replacingOccurrences(of: " ", with: "_")

        // Remove non-alphanumeric characters (except underscores and hyphens)
        cleanName = cleanName.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "", options: .regularExpression)

        // Limit length
        if cleanName.count > 50 {
            cleanName = String(cleanName.prefix(50))
        }

        // Add timestamp to ensure uniqueness
        let timestamp = Int(Date().timeIntervalSince1970)

        return "\(cleanName)_\(timestamp).png"
    }

    /// Get relative path for storing in database (relative to data/file_system/storage)
    func getRelativePath(for fileURL: URL) -> String {
        guard let documentsDirectory = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return fileURL.lastPathComponent
        }

        let storageDirectory = documentsDirectory
            .appendingPathComponent("data")
            .appendingPathComponent("file_system")
            .appendingPathComponent("storage")

        let relativePath = fileURL.path.replacingOccurrences(
            of: storageDirectory.path + "/",
            with: ""
        )

        return relativePath
    }

    /// Get absolute URL from relative path (relative to data/file_system/storage)
    func getAbsoluteURL(from relativePath: String) -> URL? {
        guard let documentsDirectory = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return nil
        }

        let storageDirectory = documentsDirectory
            .appendingPathComponent("data")
            .appendingPathComponent("file_system")
            .appendingPathComponent("storage")

        return storageDirectory.appendingPathComponent(relativePath)
    }

    /// Unload MLX model to free memory
    func unloadModel() {
        mlxFlux.unloadModel()
    }
}

// MARK: - Errors

enum ImageGenerationError: Error, LocalizedError {
    case notConfigured
    case apiRequestFailed(Error)
    case invalidImageData
    case imageEncodingFailed
    case progressNotSupported

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Image generation not configured. Enable MLX or configure API URL."
        case .apiRequestFailed(let error):
            return "API request failed: \(error.localizedDescription)"
        case .invalidImageData:
            return "Invalid image data received from API"
        case .imageEncodingFailed:
            return "Failed to encode image as PNG"
        case .progressNotSupported:
            return "Progress tracking not supported for remote API generation"
        }
    }
}
