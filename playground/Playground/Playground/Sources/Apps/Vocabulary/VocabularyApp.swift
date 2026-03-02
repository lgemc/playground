import SwiftUI
import Combine

/// Vocabulary sub-app - Spaced repetition language learning
class VocabularyApp: SubApp {
    let id = "vocabulary"
    let name = "Vocabulary"
    let iconName = "book.fill"
    let themeColor = Color.purple

    let supportsSearch = true

    // ObservableObject conformance
    let objectWillChange = ObservableObjectPublisher()

    init() {}

    func buildView() -> AnyView {
        AnyView(VocabularyListView())
    }

    // MARK: - Lifecycle

    func onInit() async {
        print("✅ Vocabulary app initialized")
    }

    // MARK: - Search

    func search(query: String) async -> [SearchResult] {
        let wordsResult = VocabularyStorage.shared.searchWords(query: query, limit: 50)
        guard let words = wordsResult.value else {
            print("❌ Vocabulary search failed: \(wordsResult.error?.localizedDescription ?? "unknown error")")
            return []
        }

        return words.map { word in
            let preview = word.meaning.count > 100
                ? String(word.meaning.prefix(100)) + "..."
                : word.meaning

            return SearchResult(
                id: word.id,
                type: .vocabularyWord,
                appId: id,
                title: word.word,
                subtitle: nil,
                preview: preview,
                navigationData: ["wordId": word.id],
                timestamp: word.createdAt
            )
        }
    }

    func navigateToSearchResult(result: SearchResult) async {
        // Navigation will be handled by the UI layer
    }
}
