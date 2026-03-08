import Foundation

// PlatformImage is already defined in MLXImageService.swift
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Service for generating images using on-device MLX Stable Diffusion
/// Compatible with existing dependencies, optimized for Apple Silicon
class ImageGenerationService {
    static let shared = ImageGenerationService()
    private let config = ConfigService.shared
    private let stableDiffusion = MLXStableDiffusionService.shared

    // Config keys
    private let configKeyUseOnDevice = "image_generation.use_on_device"
    private let configKeyApiUrl = "image_generation.api_url"

    private init() {
        initializeDefaults()
    }

    // MARK: - Configuration

    private func initializeDefaults() {
        config.defineConfig(key: configKeyUseOnDevice, value: "true")
        config.defineConfig(key: configKeyApiUrl, value: "")
    }

    var useOnDevice: Bool {
        (config.getConfig(key: configKeyUseOnDevice) ?? "true") == "true"
    }

    /// Always true since this service uses MLX Stable Diffusion
    var useMLX: Bool {
        return true
    }

    var apiUrl: String {
        config.getConfig(key: configKeyApiUrl) ?? ""
    }

    var isConfigured: Bool {
        useOnDevice
    }

    // MARK: - Image Generation

    /// Generate image from text prompt and save to file system
    /// - Parameters:
    ///   - prompt: Text description of the image
    ///   - negativePrompt: What to avoid in the image
    ///   - width: Image width (default: 512, optimized for iPhone)
    ///   - height: Image height (default: 512, optimized for iPhone)
    ///   - steps: Number of inference steps (default: 4 for SDXL Turbo)
    ///   - guidanceScale: Guidance scale for generation (default: 0.0 for SDXL Turbo)
    ///   - seed: Random seed for reproducibility
    /// - Returns: URL of the saved image file
    func generateImage(
        prompt: String,
        negativePrompt: String? = nil,
        width: Int = 512,
        height: Int = 512,
        steps: Int = 4,
        guidanceScale: Double = 0.0,
        seed: Int? = nil
    ) async throws -> URL {
        guard isConfigured else {
            throw ImageGenerationError.notConfigured
        }

        // Load model if not loaded
        try await stableDiffusion.loadModel()

        print("🎨 Generating image with Core ML Stable Diffusion")
        print("   Prompt: \(prompt.prefix(50))...")
        print("   Size: \(width)x\(height)")

        let image = try await stableDiffusion.generate(
            prompt: prompt,
            negativePrompt: negativePrompt,
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

        print("✅ Image saved: \(fileURL.path)")
        return fileURL
    }

    /// Generate image with progress updates
    func generateImageWithProgress(
        prompt: String,
        negativePrompt: String? = nil,
        width: Int = 512,
        height: Int = 512,
        steps: Int = 4,
        guidanceScale: Double = 0.0,
        seed: Int? = nil
    ) -> AsyncThrowingStream<GenerationProgress, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Load model if not loaded
                    try await stableDiffusion.loadModel()

                    // Stream progress
                    for try await progress in stableDiffusion.generateWithProgress(
                        prompt: prompt,
                        negativePrompt: negativePrompt,
                        width: width,
                        height: height,
                        steps: steps,
                        guidanceScale: guidanceScale,
                        seed: seed
                    ) {
                        continuation.yield(progress)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
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

    /// Unload model to free memory
    func unloadModel() {
        stableDiffusion.unloadModel()
    }
}

// MARK: - Errors

enum ImageGenerationError: Error, LocalizedError {
    case notConfigured
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Image generation not configured. On-device generation is disabled."
        case .imageEncodingFailed:
            return "Failed to encode image as PNG"
        }
    }
}
