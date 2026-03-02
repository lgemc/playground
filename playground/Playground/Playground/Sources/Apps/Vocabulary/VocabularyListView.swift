import SwiftUI

/// Vocabulary list view - simple word list matching Dart implementation
struct VocabularyListView: View {
    @State private var words: [VocabularyWord] = []
    @State private var showingAddWord = false
    @State private var isLoading = false
    @State private var searchQuery: String = ""

    var filteredWords: [VocabularyWord] {
        if searchQuery.isEmpty {
            return words
        }
        let query = searchQuery.lowercased()
        return words.filter { word in
            word.word.lowercased().contains(query) ||
            word.meaning.lowercased().contains(query)
        }
    }

    var body: some View {
        List {
            // Word list
            if filteredWords.isEmpty {
                emptyStateView
            } else {
                ForEach(filteredWords) { word in
                    NavigationLink(destination: WordDetailView(word: word)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(word.word)
                                    .font(.headline)

                                if !word.meaning.isEmpty {
                                    Text(word.meaning)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                } else {
                                    HStack(spacing: 4) {
                                        Image(systemName: "hourglass")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                        Text("Pending definition")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }

                            Spacer()

                            // Show generate button if no meaning
                            if word.meaning.isEmpty {
                                Button(action: { generateDefinition(for: word) }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "sparkles")
                                            .font(.caption)
                                        Text("Generate")
                                            .font(.caption)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .padding(.trailing, 8)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: deleteWords)
            }
        }
        .searchable(text: $searchQuery, prompt: "Search words...")
        .navigationTitle("Vocabulary")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddWord = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddWord) {
            NavigationStack {
                AddWordView(onWordAdded: loadWords)
            }
        }
        .onAppear(perform: loadWords)
        .refreshable {
            loadWords()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            if searchQuery.isEmpty {
                Image(systemName: "book")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No words yet")
                    .font(.headline)
                Text("Tap + to add your first word")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No words found")
                    .font(.headline)
                Text("Try a different search term")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .listRowBackground(Color.clear)
    }

    private func loadWords() {
        isLoading = true

        let wordsResult = VocabularyStorage.shared.getAllWords()
        if wordsResult.isErr {
            print("❌ Failed to load words: \(wordsResult.error!)")
        } else {
            words = wordsResult.value!
        }

        isLoading = false
    }

    private func deleteWords(at offsets: IndexSet) {
        for index in offsets {
            let word = filteredWords[index]
            let result = VocabularyStorage.shared.deleteWord(id: word.id)

            if result.isErr {
                print("❌ Failed to delete word: \(result.error!)")
            } else {
                loadWords()
            }
        }
    }

    private func generateDefinition(for word: VocabularyWord) {
        Task {
            print("🔄 Generating definition for: \(word.word)")

            do {
                let (meaning, examples) = try await VocabularyDefinitionService.shared.generateDefinition(
                    word: word.word,
                    exampleCount: 5
                )

                // Update the word with the generated definition
                let result = VocabularyStorage.shared.updateWord(
                    id: word.id,
                    meaning: meaning,
                    samplePhrases: examples
                )

                if result.isOk {
                    print("✅ Definition generated and saved")
                    await MainActor.run {
                        loadWords()
                    }
                } else if let error = result.error {
                    print("❌ Failed to save definition: \(error)")
                }
            } catch {
                print("❌ Failed to generate definition: \(error)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        VocabularyListView()
    }
}
