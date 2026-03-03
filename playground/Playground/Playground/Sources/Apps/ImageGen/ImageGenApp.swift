import SwiftUI
import Combine

/// Image Generation sub-app - AI-powered image creation using Flux
class ImageGenApp: SubApp {
    let id = "imagegen"
    let name = "Image Gen"
    let iconName = "photo.on.rectangle.angled"
    let themeColor = Color.purple

    let supportsSearch = false  // TODO: Add search support for generated images

    // ObservableObject conformance
    let objectWillChange = ObservableObjectPublisher()

    init() {}

    func buildView() -> AnyView {
        AnyView(ImageGenView())
    }

    // MARK: - Lifecycle

    func onInit() async {
        print("✅ Image Gen app initialized")

        // Initialize config defaults (already done in ImageGenerationService)
        // No additional setup needed
    }

    func onDispose() {
        // Unload model to free memory
        ImageGenerationService.shared.unloadModel()
        print("🗑️ Image Gen app disposed - model unloaded")
    }

    // MARK: - Search (Future Implementation)

    func search(query: String) async -> [SearchResult] {
        // TODO: Implement search in generated images
        // - Search by prompt text
        // - Search by filename
        // Could integrate with FileSystem app's database
        return []
    }

    func navigateToSearchResult(result: SearchResult) async {
        // TODO: Navigate to image detail view
    }
}
