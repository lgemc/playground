import SwiftUI
import Combine

@MainActor
class ImageGenViewModel: ObservableObject {
    @Published var prompt: String = ""
    @Published var selectedSize: ImageSize = .square
    @Published var generatedImage: UIImage?
    @Published var isGenerating: Bool = false
    @Published var progress: Double = 0.0
    @Published var currentStep: Int = 0
    @Published var totalSteps: Int = 4
    @Published var errorMessage: String?

    private let imageService = ImageGenerationService.shared
    private var lastGeneratedURL: URL?

    var canGenerate: Bool {
        !prompt.isEmpty && !isGenerating
    }

    // MARK: - Image Generation

    func generateImage() async {
        guard !prompt.isEmpty else { return }

        isGenerating = true
        errorMessage = nil
        progress = 0.0
        currentStep = 0

        let (width, height) = selectedSize.dimensions

        do {
            // Use progress tracking if available (MLX only)
            if imageService.useMLX {
                try await generateWithProgress(width: width, height: height)
            } else {
                try await generateWithoutProgress(width: width, height: height)
            }
        } catch {
            print("❌ Image generation failed: \(error)")
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }

    private func generateWithProgress(width: Int, height: Int) async throws {
        for try await progressUpdate in imageService.generateImageWithProgress(
            prompt: prompt,
            width: width,
            height: height
        ) {
            self.currentStep = progressUpdate.step
            self.totalSteps = progressUpdate.totalSteps
            self.progress = progressUpdate.progress

            if progressUpdate.isComplete {
                // Load the final image
                if let base64 = progressUpdate.previewImage,
                   let imageData = Data(base64Encoded: base64),
                   let image = UIImage(data: imageData) {
                    self.generatedImage = image
                    print("✅ Image generated successfully")
                }
            }
        }
    }

    private func generateWithoutProgress(width: Int, height: Int) async throws {
        // Show indeterminate progress
        totalSteps = 1
        currentStep = 0
        progress = 0.5

        let imageURL = try await imageService.generateImage(
            prompt: prompt,
            width: width,
            height: height
        )

        lastGeneratedURL = imageURL
        progress = 1.0
        currentStep = 1

        // Load image from file
        if let imageData = try? Data(contentsOf: imageURL),
           let image = UIImage(data: imageData) {
            generatedImage = image
            print("✅ Image loaded from: \(imageURL.path)")
        }
    }

    // MARK: - Image Actions

    func saveToPhotos() {
        guard let image = generatedImage else { return }

        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)

        // Show success feedback (could use a toast/alert here)
        print("✅ Image saved to Photos")
    }

    func shareImage() {
        guard generatedImage != nil else { return }

        // This would need to be triggered from the view using a UIActivityViewController
        // For now, just log
        print("📤 Share image requested")
    }

    func regenerate() async {
        await generateImage()
    }

    // MARK: - Settings

    func loadSettings() {
        let config = ConfigService.shared

        // Load model preference
        if let modelName: String = config.getConfig(key: "image_generation.mlx_model") {
            // Model is already set in service
            print("Using model: \(modelName)")
        }
    }
}
