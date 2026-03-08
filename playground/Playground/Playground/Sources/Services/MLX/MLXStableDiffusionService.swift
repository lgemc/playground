import Foundation
import MLX
import StableDiffusion

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// On-device text-to-image service using MLX Stable Diffusion
/// Compatible with existing swift-transformers 1.1.9 (no dependency conflicts)
/// Works on iPhone and Mac with Apple Silicon
class MLXStableDiffusionService {
    static let shared = MLXStableDiffusionService()
    private let config = ConfigService.shared

    private var modelContainer: ModelContainer<TextToImageGenerator>?
    private var configuration: StableDiffusionConfiguration
    private var isLoading = false

    // Config keys
    private let configKeyConserveMemory = "stable_diffusion.conserve_memory"

    private init() {
        // Use preset configuration for SDXL Turbo
        configuration = StableDiffusionConfiguration.presetSDXLTurbo
        initializeDefaults()
    }

    // MARK: - Configuration

    private func initializeDefaults() {
        config.defineConfig(key: configKeyConserveMemory, value: "true")  // For iPhone
    }

    var conserveMemory: Bool {
        (config.getConfig(key: configKeyConserveMemory) ?? "true") == "true"
    }

    // MARK: - Model Loading

    func loadModel() async throws {
        if modelContainer != nil {
            print("✅ Stable Diffusion model already loaded")
            return
        }

        guard !isLoading else {
            print("⏳ Model already loading...")
            return
        }

        isLoading = true
        defer { isLoading = false }

        print("📦 Loading MLX Stable Diffusion model: SDXL Turbo")
        print("   Conserve memory: \(conserveMemory)")

        do {
            // Download model if needed
            try await configuration.download { progress in
                print("   Downloading: \(Int(progress.fractionCompleted * 100))%")
            }

            // Create model container
            let loadConfiguration = LoadConfiguration(
                float16: true,
                quantize: conserveMemory
            )

            let container = try ModelContainer<TextToImageGenerator>.createTextToImageGenerator(
                configuration: configuration,
                loadConfiguration: loadConfiguration
            )

            await container.setConserveMemory(conserveMemory)

            // Load weights
            try await container.perform { model in
                print("   Loading weights...")
                if !conserveMemory {
                    model.ensureLoaded()
                }
            }

            self.modelContainer = container
            print("✅ MLX Stable Diffusion model loaded successfully")
        } catch {
            modelContainer = nil
            print("❌ Failed to load model: \(error)")
            throw StableDiffusionError.modelLoadFailed(error)
        }
    }

    // MARK: - Image Generation

    func generate(
        prompt: String,
        negativePrompt: String? = nil,
        width: Int = 512,
        height: Int = 512,
        steps: Int = 4,  // SDXL Turbo default
        guidanceScale: Double = 0.0,  // SDXL Turbo uses 0.0
        seed: Int? = nil
    ) async throws -> PlatformImage {
        guard let container = modelContainer else {
            throw StableDiffusionError.modelNotLoaded
        }

        print("🎨 Generating image with MLX Stable Diffusion")
        print("   Prompt: \(prompt.prefix(50))...")
        print("   Size: \(width)x\(height)")
        print("   Steps: \(steps)")

        // Create generation parameters
        var parameters = configuration.defaultParameters()
        parameters.prompt = prompt
        parameters.negativePrompt = negativePrompt ?? ""
        parameters.steps = conserveMemory ? 1 : steps

        do {
            // Generate latents and decode to image
            let image = try await container.performTwoStage { generator in
                // Stage 1: Generate latents
                let latents = generator.generateLatents(parameters: parameters)

                // Detach decoder to conserve memory
                let decoder = generator.detachedDecoder()

                return (decoder, latents)

            } second: { decoder, latents in
                // Stage 2: Evaluate latents and decode
                var lastLatent: MLXArray?
                for latent in latents {
                    MLX.eval(latent)
                    lastLatent = latent
                }

                guard let finalLatent = lastLatent else {
                    throw StableDiffusionError.generationFailed
                }

                // Decode to image
                let decoded = decoder(finalLatent)
                MLX.eval(decoded)

                // Convert MLXArray to CGImage
                let raster = (decoded * 255).asType(.uint8).squeezed()
                return Image(raster).asCGImage()
            }

            #if canImport(UIKit)
            let platformImage = UIImage(cgImage: image)
            #elseif canImport(AppKit)
            let platformImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            #endif

            print("✅ Image generated successfully")
            return platformImage
        } catch {
            print("❌ Generation failed: \(error)")
            throw StableDiffusionError.generationFailed
        }
    }

    func generateWithProgress(
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
                guard let container = modelContainer else {
                    continuation.finish(throwing: StableDiffusionError.modelNotLoaded)
                    return
                }

                // Create generation parameters
                var parameters = configuration.defaultParameters()
                parameters.prompt = prompt
                parameters.negativePrompt = negativePrompt ?? ""
                parameters.steps = conserveMemory ? 1 : steps

                do {
                    // Generate with progress
                    try await container.performTwoStage { generator in
                        let latents = generator.generateLatents(parameters: parameters)
                        let decoder = generator.detachedDecoder()
                        return (decoder, latents)

                    } second: { decoder, latents in
                        var currentStep = 0
                        let totalSteps = parameters.steps

                        for latent in latents {
                            MLX.eval(latent)
                            currentStep += 1

                            let isComplete = currentStep == totalSteps

                            // For last step, decode and send final image
                            if isComplete {
                                let decoded = decoder(latent)
                                MLX.eval(decoded)

                                let raster = (decoded * 255).asType(.uint8).squeezed()
                                let cgImage = Image(raster).asCGImage()

                                #if canImport(UIKit)
                                let platformImage = UIImage(cgImage: cgImage)
                                let imageData = platformImage.pngData()
                                #elseif canImport(AppKit)
                                let platformImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                                let imageData = platformImage.tiffRepresentation
                                #endif

                                let base64Image = imageData?.base64EncodedString()

                                continuation.yield(GenerationProgress(
                                    step: currentStep,
                                    totalSteps: totalSteps,
                                    previewImage: base64Image,
                                    isComplete: true
                                ))
                            } else {
                                // Send progress update without image
                                continuation.yield(GenerationProgress(
                                    step: currentStep,
                                    totalSteps: totalSteps,
                                    previewImage: nil,
                                    isComplete: false
                                ))
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func unloadModel() {
        modelContainer = nil
        print("🗑️ MLX Stable Diffusion model unloaded")
    }
}

// MARK: - Errors

enum StableDiffusionError: Error, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(Error)
    case generationFailed
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Stable Diffusion model not loaded. Call loadModel() first."
        case .modelLoadFailed(let error):
            return "Failed to load Stable Diffusion model: \(error.localizedDescription)"
        case .generationFailed:
            return "Image generation failed"
        case .imageEncodingFailed:
            return "Failed to encode image"
        }
    }
}

