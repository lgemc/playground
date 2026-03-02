import SwiftUI

/// Add word view - form for creating new vocabulary words
/// Matches the Dart implementation with sample phrases and audio generation
struct AddWordView: View {
    @Environment(\.dismiss) private var dismiss
    let onWordAdded: () -> Void

    @State private var word: String = ""
    @State private var meaning: String = ""
    @State private var samplePhrases: [String] = []

    @State private var isGenerating = false
    @State private var isGeneratingAudio = false
    @State private var streamingResponse: String = ""
    @State private var showError = false
    @State private var errorMessage = ""

    private let definitionService = VocabularyDefinitionService.shared
    private let audioService = VocabularyAudioService.shared

    var body: some View {
        Form {
            Section("Word") {
                TextField("Enter word", text: $word)
                    .autocapitalization(.none)
            }

            Section {
                Button(action: generateDefinition) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Generate Definition with AI")
                        if isGenerating {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(word.isEmpty || isGenerating)
            }

            // Show streaming response if generating
            if isGenerating && !streamingResponse.isEmpty {
                Section("Generating...") {
                    Text(streamingResponse)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Definition") {
                TextEditor(text: $meaning)
                    .frame(minHeight: 80)
            }

            Section("Sample Phrases") {
                if samplePhrases.isEmpty {
                    Text("Generate definition to add sample phrases")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(samplePhrases.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(samplePhrases[index])
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Add Word")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveWord()
                }
                .disabled(word.isEmpty || isGenerating || isGeneratingAudio)
            }
        }
        .overlay {
            if isGeneratingAudio {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.5)
                        Text("Generating audio...")
                            .font(.headline)
                    }
                    .padding(32)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func generateDefinition() {
        guard !word.isEmpty else { return }

        isGenerating = true
        streamingResponse = ""

        Task {
            do {
                let result = try await definitionService.generateDefinitionStreaming(
                    word: word,
                    exampleCount: 5,
                    onUpdate: { partial in
                        Task { @MainActor in
                            streamingResponse = partial
                        }
                    }
                )

                await MainActor.run {
                    meaning = result.meaning
                    samplePhrases = result.examples
                    isGenerating = false
                    streamingResponse = ""
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate definition: \(error.localizedDescription)"
                    showError = true
                    isGenerating = false
                    streamingResponse = ""
                }
            }
        }
    }

    private func saveWord() {
        let result = VocabularyStorage.shared.createWord(
            word: word,
            meaning: meaning,
            samplePhrases: samplePhrases
        )

        if result.isErr {
            errorMessage = "Failed to save word: \(result.error!.localizedDescription)"
            showError = true
            return
        }

        guard let savedWord = result.value else {
            errorMessage = "Failed to save word: Unknown error"
            showError = true
            return
        }

        // Generate audio in background
        Task {
            do {
                await MainActor.run {
                    isGeneratingAudio = true
                }

                try await audioService.generateAudioForWord(wordId: savedWord.id)

                await MainActor.run {
                    isGeneratingAudio = false
                    onWordAdded()
                    dismiss()
                }
            } catch {
                // Audio generation failed, but word was saved
                print("⚠️ Audio generation failed: \(error)")
                await MainActor.run {
                    isGeneratingAudio = false
                    onWordAdded()
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AddWordView(onWordAdded: {})
    }
}
