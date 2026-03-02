import SwiftUI
import AVFoundation

/// Word detail view - shows information about a single vocabulary word
/// Matches the Dart implementation with sample phrases and audio playback
struct WordDetailView: View {
    let word: VocabularyWord

    @State private var showingDeleteAlert = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var currentlyPlayingIndex: Int?
    @State private var isGenerating = false
    @State private var currentWord: VocabularyWord

    private let audioService = VocabularyAudioService.shared
    private let storage = VocabularyStorage.shared

    init(word: VocabularyWord) {
        self.word = word
        self._currentWord = State(initialValue: word)
    }

    var body: some View {
        List {
            Section("Word") {
                HStack {
                    Text(currentWord.word)
                        .font(.title)
                        .fontWeight(.bold)

                    Spacer()

                    // Play word audio button
                    if let _ = currentWord.wordAudioPath {
                        Button(action: { playWordAudio() }) {
                            Image(systemName: currentlyPlayingIndex == -1 ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }

            Section("Definition") {
                if isGenerating {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Generating definition...")
                            .foregroundColor(.secondary)
                    }
                } else if currentWord.meaning.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No definition yet")
                            .foregroundColor(.secondary)
                            .italic()

                        Button(action: { generateDefinition() }) {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Generate Definition")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(currentWord.meaning)
                }
            }

            if !currentWord.samplePhrases.isEmpty {
                Section("Sample Phrases") {
                    ForEach(currentWord.samplePhrases.indices, id: \.self) { index in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(index + 1).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(currentWord.samplePhrases[index])
                                    .font(.body)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            // Play phrase audio button
                            if index < currentWord.sampleAudioPaths.count,
                               !currentWord.sampleAudioPaths[index].isEmpty {
                                Button(action: { playPhraseAudio(at: index) }) {
                                    Image(systemName: currentlyPlayingIndex == index ? "stop.circle.fill" : "play.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // Audio Generation Section
            if !currentWord.meaning.isEmpty && !currentWord.samplePhrases.isEmpty {
                Section("Audio") {
                    if audioService.hasAudio(for: currentWord) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Audio generated")
                            Spacer()
                            Button(action: { generateAudio() }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Regenerate")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("No audio generated yet")
                                .foregroundColor(.secondary)
                                .italic()

                            Button(action: { generateAudio() }) {
                                HStack {
                                    Image(systemName: "speaker.wave.2.fill")
                                    Text("Generate Audio")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isGenerating)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Section("Info") {
                HStack {
                    Text("Created")
                    Spacer()
                    Text(formatDate(word.createdAt))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Updated")
                    Spacer()
                    Text(formatDate(word.updatedAt))
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button(role: .destructive, action: { showingDeleteAlert = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete Word")
                    }
                }
            }
        }
        .navigationTitle("Word Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Delete Word", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteWord()
            }
        } message: {
            Text("Are you sure you want to delete '\(word.word)'? This action cannot be undone.")
        }
    }

    private func generateDefinition() {
        Task {
            isGenerating = true
            print("🔄 Generating definition for: \(word.word)")

            do {
                let (meaning, examples) = try await VocabularyDefinitionService.shared.generateDefinition(
                    word: word.word,
                    exampleCount: 5
                )

                // Update the word with the generated definition
                let result = storage.updateWord(
                    id: word.id,
                    meaning: meaning,
                    samplePhrases: examples
                )

                if result.isOk {
                    print("✅ Definition generated and saved")
                    // Update current word to show the new definition
                    await MainActor.run {
                        currentWord = VocabularyWord(
                            id: currentWord.id,
                            word: currentWord.word,
                            meaning: meaning,
                            samplePhrases: examples,
                            wordAudioPath: currentWord.wordAudioPath,
                            sampleAudioPaths: currentWord.sampleAudioPaths,
                            createdAt: currentWord.createdAt,
                            updatedAt: Date()
                        )
                        isGenerating = false
                    }
                } else if let error = result.error {
                    print("❌ Failed to save definition: \(error)")
                    await MainActor.run {
                        isGenerating = false
                    }
                }
            } catch {
                print("❌ Failed to generate definition: \(error)")
                await MainActor.run {
                    isGenerating = false
                }
            }
        }
    }

    private func generateAudio() {
        Task {
            isGenerating = true
            print("🔄 Generating audio for: \(currentWord.word)")

            do {
                _ = try await audioService.generateAudioForWord(wordId: currentWord.id)

                // Reload the word to get updated audio paths
                if let updatedWord = try await storage.getWord(id: currentWord.id).get() {
                    await MainActor.run {
                        currentWord = updatedWord
                        isGenerating = false
                    }
                    print("✅ Audio generation completed")
                }
            } catch {
                print("❌ Failed to generate audio: \(error)")
                await MainActor.run {
                    isGenerating = false
                }
            }
        }
    }

    private func deleteWord() {
        // Delete audio files first
        audioService.deleteAudio(for: word)

        let result = storage.deleteWord(id: word.id)
        if result.isOk {
            // Navigate back would happen here
            print("✅ Word deleted successfully")
        } else if let error = result.error {
            print("❌ Failed to delete word: \(error)")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Audio Playback

    private func playWordAudio() {
        guard let audioURL = audioService.getWordAudioURL(for: currentWord) else {
            print("⚠️ No audio available for word")
            return
        }

        if currentlyPlayingIndex == -1 {
            // Stop if already playing
            stopAudio()
        } else {
            playAudio(url: audioURL, index: -1)
        }
    }

    private func playPhraseAudio(at index: Int) {
        let audioURLs = audioService.getSampleAudioURLs(for: currentWord)
        guard index < audioURLs.count, let audioURL = audioURLs[index] else {
            print("⚠️ No audio available for phrase \(index + 1)")
            return
        }

        if currentlyPlayingIndex == index {
            // Stop if already playing this phrase
            stopAudio()
        } else {
            playAudio(url: audioURL, index: index)
        }
    }

    private func playAudio(url: URL, index: Int) {
        do {
            stopAudio()

            // Configure audio session
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            // Create and play audio
            let player = try AVAudioPlayer(contentsOf: url)

            // Create delegate and store it to keep it alive
            let delegate = AudioPlayerDelegate {
                // On completion
                DispatchQueue.main.async {
                    currentlyPlayingIndex = nil
                }
            }

            // Store both player and delegate
            audioPlayer = player
            player.delegate = delegate

            // Use objc associated objects to keep delegate alive
            objc_setAssociatedObject(player, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

            currentlyPlayingIndex = index
            player.play()

            print("🔊 Playing audio: \(url.lastPathComponent)")
        } catch {
            print("❌ Failed to play audio: \(error)")
            currentlyPlayingIndex = nil
        }
    }

    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentlyPlayingIndex = nil
    }
}

// MARK: - Audio Player Delegate

private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onComplete()
    }
}

#Preview {
    NavigationStack {
        WordDetailView(word: VocabularyWord(
            word: "Hello",
            meaning: "A greeting used to begin a conversation",
            samplePhrases: ["Hello, how are you today?", "Hello! Nice to meet you."]
        ))
    }
}
