import Foundation
import MLX
import Alamofire

// PlatformImage is already defined in MLXImageService.swift
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - API Response Models (nonisolated for background decoding)

private nonisolated struct AsyncJobResponse: Codable, Sendable {
    let job_id: String
    let status: String
}

private nonisolated struct AsyncJobStatus: Codable, Sendable {
    let job_id: String
    let status: String
    let progress: Int
    let result: AsyncJobResult?
}

private nonisolated struct AsyncJobResult: Codable, Sendable {
    let image_b64: String?
}

/// Remote API-based text-to-image service using Flux + MFLUX Python API
/// Uses Python API server instead of on-device Swift package due to dependency conflicts
class MLXFluxService {
    static let shared = MLXFluxService()
    private let config = ConfigService.shared

    // Config keys
    private let configKeyModel = "flux.model"
    private let configKeyApiUrl = "flux.api_url"

    private init() {
        initializeDefaults()
    }

    // MARK: - Configuration

    private func initializeDefaults() {
        config.defineConfig(key: configKeyModel, value: "flux-schnell")
        config.defineConfig(key: configKeyApiUrl, value: "http://localhost:8004")
    }

    var modelName: String {
        config.getConfig(key: configKeyModel) ?? "flux-schnell"
    }

    var apiUrl: String {
        config.getConfig(key: configKeyApiUrl) ?? "http://localhost:8004"
    }

    var isConfigured: Bool {
        !apiUrl.isEmpty
    }

    // MARK: - Model Loading (No-op for API-based approach)

    func loadModel(_ modelConfig: MLXModelConfig.FluxModel? = nil) async throws {
        // No-op - model is loaded on the server side
        print("✅ Flux API ready at \(apiUrl)")
    }

    // MARK: - Image Generation

    func generate(
        prompt: String,
        model: MLXModelConfig.FluxModel? = nil,
        negativePrompt: String? = nil,
        width: Int = 1024,
        height: Int = 1024,
        steps: Int? = nil,
        guidanceScale: Double = 3.5,
        seed: Int? = nil
    ) async throws -> PlatformImage {
        guard isConfigured else {
            throw MLXFluxError.notConfigured
        }

        // Prepare request parameters
        var parameters: [String: String] = [
            "prompt": prompt,
            "width": String(width),
            "height": String(height),
            "guidance_scale": String(guidanceScale),
            "response_format": "url"  // Get image bytes directly
        ]

        if let steps = steps {
            parameters["steps"] = String(steps)
        }

        if let seed = seed {
            parameters["seed"] = String(seed)
        }

        let url = "\(apiUrl)/v1/images/generations"

        print("🎨 Generating image via Flux API: \(prompt.prefix(50))...")
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
                    #if canImport(UIKit)
                    guard let image = UIImage(data: imageData) else {
                        continuation.resume(throwing: MLXFluxError.invalidImageData)
                        return
                    }
                    #elseif canImport(AppKit)
                    guard let image = NSImage(data: imageData) else {
                        continuation.resume(throwing: MLXFluxError.invalidImageData)
                        return
                    }
                    #endif

                    print("✅ Image generated successfully")
                    continuation.resume(returning: image)

                case .failure(let error):
                    print("❌ API request failed: \(error)")
                    if let data = response.data, let errorMessage = String(data: data, encoding: .utf8) {
                        print("   Error response: \(errorMessage)")
                    }
                    continuation.resume(throwing: MLXFluxError.apiRequestFailed(error))
                }
            }
        }
    }

    func generateToFile(
        prompt: String,
        outputURL: URL,
        model: MLXModelConfig.FluxModel? = nil,
        negativePrompt: String? = nil,
        width: Int = 1024,
        height: Int = 1024,
        steps: Int? = nil,
        guidanceScale: Double = 3.5,
        seed: Int? = nil
    ) async throws {
        let image = try await generate(
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
            throw MLXFluxError.imageEncodingFailed
        }
        #elseif canImport(AppKit)
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw MLXFluxError.imageEncodingFailed
        }
        #endif

        try pngData.write(to: outputURL)
        print("✅ Image saved to: \(outputURL.path)")
    }

    func generateWithProgress(
        prompt: String,
        model: MLXModelConfig.FluxModel? = nil,
        negativePrompt: String? = nil,
        width: Int = 1024,
        height: Int = 1024,
        steps: Int? = nil,
        guidanceScale: Double = 3.5,
        seed: Int? = nil
    ) -> AsyncThrowingStream<GenerationProgress, Error> {
        // Progress tracking via async API job
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard isConfigured else {
                        throw MLXFluxError.notConfigured
                    }

                    // Submit async job
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

                    let submitUrl = "\(apiUrl)/generate/async"

                    // Submit job
                    let request = AF.request(
                        submitUrl,
                        method: .post,
                        parameters: parameters,
                        encoding: URLEncoding.default
                    )
                    let serializer = request.serializingDecodable(AsyncJobResponse.self)
                    let jobResponse = try await serializer.value

                    let jobId = jobResponse.job_id
                    print("🎨 Async job submitted: \(jobId)")

                    // Poll for progress
                    let statusUrl = "\(apiUrl)/generate/status/\(jobId)"
                    var isComplete = false

                    while !isComplete {
                        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                        let statusRequest = AF.request(statusUrl)
                        let statusSerializer = statusRequest.serializingDecodable(AsyncJobStatus.self)
                        let status = try await statusSerializer.value

                        let currentStep = Int(Double(status.progress) / 100.0 * Double(steps ?? 4))
                        let totalSteps = steps ?? 4

                        // Send progress update
                        continuation.yield(GenerationProgress(
                            step: currentStep,
                            totalSteps: totalSteps,
                            previewImage: nil,
                            isComplete: false
                        ))

                        if status.status == "completed" {
                            isComplete = true

                            // Send final progress with image
                            let finalImage = status.result?.image_b64
                            continuation.yield(GenerationProgress(
                                step: totalSteps,
                                totalSteps: totalSteps,
                                previewImage: finalImage,
                                isComplete: true
                            ))

                            continuation.finish()
                        } else if status.status == "failed" {
                            throw MLXFluxError.generationFailed
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func unloadModel() {
        // No-op for API-based approach
        print("✅ Flux API connection ready")
    }
}

// MARK: - Errors

enum MLXFluxError: Error, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(Error)
    case generationFailed
    case imageEncodingFailed
    case notConfigured
    case apiRequestFailed(Error)
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Flux model not loaded"
        case .modelLoadFailed(let error):
            return "Failed to load Flux model: \(error.localizedDescription)"
        case .generationFailed:
            return "Image generation failed"
        case .imageEncodingFailed:
            return "Failed to encode image"
        case .notConfigured:
            return "Flux API not configured. Set flux.api_url in config."
        case .apiRequestFailed(let error):
            return "API request failed: \(error.localizedDescription)"
        case .invalidImageData:
            return "Invalid image data received from API"
        }
    }
}

// Note: GenerationProgress is already defined in MLXImageService.swift
