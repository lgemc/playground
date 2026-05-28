import SwiftUI
import Combine

/// Conversion sub-app - AI-powered transformations
class ConversionApp: SubApp {
    let id = "conversion"
    let name = "Conversions"
    let iconName = "wand.and.stars"
    let themeColor = Color.purple

    let supportsSearch = true

    // ObservableObject conformance
    let objectWillChange = ObservableObjectPublisher()

    init() {}

    func buildView() -> AnyView {
        AnyView(ConversionHistoryView())
    }

    // MARK: - Lifecycle

    func onInit() async {
        print("✅ Conversion app initialized")
    }

    // MARK: - Search

    func search(query: String) async -> [SearchResult] {
        let result = ConversionStorage.shared.searchConversions(query: query, limit: 50)

        guard let conversions = result.value else {
            print("❌ Conversion search failed: \(result.error?.localizedDescription ?? "unknown error")")
            return []
        }

        return conversions.map { conversion in
            let preview: String
            if let output = conversion.outputText {
                preview = output.count > 100 ? String(output.prefix(100)) + "..." : output
            } else if let input = conversion.inputText {
                preview = "Input: " + (input.count > 80 ? String(input.prefix(80)) + "..." : input)
            } else {
                preview = "[File conversion]"
            }

            return SearchResult(
                id: conversion.id,
                type: .note,  // Reusing note type for now
                appId: id,
                title: conversion.type.displayName,
                subtitle: conversion.formattedTime,
                preview: preview,
                navigationData: ["conversionId": conversion.id],
                timestamp: conversion.createdAt
            )
        }
    }

    func navigateToSearchResult(result: SearchResult) async {
        // Navigation handled by UI layer
        // Could show a detail view in the future
    }
}
