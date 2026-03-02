import Foundation

/// Service for generating audio for vocabulary words and sample phrases
/// Matches the Dart VocabularyAudioService implementation
class VocabularyAudioService {
    static let shared = VocabularyAudioService()
    private let audioService = AudioGenerationService.shared
    private let storage = VocabularyStorage.shared

    private init() {}

    // MARK: - Audio Generation

    /// Generate audio for a vocabulary word and its sample phrases
    /// - Parameter wordId: ID of the vocabulary word
    /// - Returns: True if successful, false if failed
    @discardableResult
    func generateAudioForWord(wordId: String) async throws -> Bool {
        print("🎵 Generating audio for word: \(wordId)")

        // Retrieve word from database
        guard let word = try await storage.getWord(id: wordId).get() else {
            print("⚠️ Word not found: \(wordId)")
            return false
        }

        // Verify word has meaning and samples
        if word.meaning.isEmpty || word.samplePhrases.isEmpty {
            print("⚠️ Word has no meaning or samples, skipping audio generation")
            print("   Word: \(word.word)")
            print("   Has meaning: \(!word.meaning.isEmpty)")
            print("   Sample count: \(word.samplePhrases.count)")
            return false
        }

        let wordText = word.word
        let samplePhrases = word.samplePhrases

        // Check if service is configured
        guard audioService.isConfigured else {
            print("❌ Audio generation service not configured")
            print("   Suggestion: Set the audio generation API URL in Settings")
            throw AudioGenerationError.notConfigured
        }

        var wordAudioPath: String?
        var sampleAudioPaths: [String] = []

        // Generate audio for the word
        do {
            print("🎵 Generating audio for word: \(wordText)")

            let wordAudioURL = try await audioService.generateAudio(
                text: wordText,
                filename: "\(wordText)_word"
            )
            wordAudioPath = audioService.getRelativePath(for: wordAudioURL)

            print("✅ Successfully generated word audio: \(wordAudioPath ?? "")")
        } catch {
            print("❌ Failed to generate word audio: \(error)")
            // Continue with sample phrases even if word audio fails
        }

        // Generate audio for sample phrases
        for (index, phrase) in samplePhrases.enumerated() {
            guard !phrase.isEmpty else {
                sampleAudioPaths.append("")
                continue
            }

            do {
                print("🎵 Generating audio for sample phrase \(index + 1)/\(samplePhrases.count)")
                print("   Phrase: \(phrase.prefix(50))\(phrase.count > 50 ? "..." : "")")

                let phraseAudioURL = try await audioService.generateAudio(
                    text: phrase,
                    filename: "\(wordText)_phrase_\(index + 1)"
                )
                let phrasePath = audioService.getRelativePath(for: phraseAudioURL)
                sampleAudioPaths.append(phrasePath)

                print("✅ Successfully generated phrase audio: \(phrasePath)")
            } catch {
                print("❌ Failed to generate phrase audio \(index + 1): \(error)")
                // Add empty string to maintain index alignment
                sampleAudioPaths.append("")
            }
        }

        // Update word with audio paths
        try storage.updateWord(
            id: wordId,
            wordAudioPath: wordAudioPath,
            sampleAudioPaths: sampleAudioPaths
        ).get()

        print("✅ Successfully updated word with audio paths")
        print("   Word audio: \(wordAudioPath ?? "none")")
        print("   Phrase audios: \(sampleAudioPaths.count)")

        return true
    }

    /// Generate audio for multiple words in sequence
    /// - Parameter wordIds: Array of word IDs
    /// - Returns: Number of words successfully processed
    func generateAudioForWords(wordIds: [String]) async -> Int {
        var successCount = 0

        for wordId in wordIds {
            do {
                if try await generateAudioForWord(wordId: wordId) {
                    successCount += 1
                }
            } catch {
                print("❌ Error generating audio for word \(wordId): \(error)")
            }
        }

        return successCount
    }

    // MARK: - Audio Playback

    /// Get audio URL for a vocabulary word
    /// - Parameter word: The vocabulary word
    /// - Returns: URL of the word audio file, or nil if not available
    func getWordAudioURL(for word: VocabularyWord) -> URL? {
        guard let audioPath = word.wordAudioPath else {
            return nil
        }
        return audioService.getAbsoluteURL(from: audioPath)
    }

    /// Get audio URLs for sample phrases
    /// - Parameter word: The vocabulary word
    /// - Returns: Array of URLs (may contain nils for missing audio)
    func getSampleAudioURLs(for word: VocabularyWord) -> [URL?] {
        return word.sampleAudioPaths.map { path in
            guard !path.isEmpty else { return nil }
            return audioService.getAbsoluteURL(from: path)
        }
    }

    // MARK: - Utility

    /// Check if a word has audio
    /// - Parameter word: The vocabulary word
    /// - Returns: True if word has at least word audio or one sample audio
    func hasAudio(for word: VocabularyWord) -> Bool {
        if word.wordAudioPath != nil && !word.wordAudioPath!.isEmpty {
            return true
        }

        return word.sampleAudioPaths.contains { !$0.isEmpty }
    }

    /// Delete audio files for a word
    /// - Parameter word: The vocabulary word
    func deleteAudio(for word: VocabularyWord) {
        // Delete word audio
        if let wordPath = word.wordAudioPath, !wordPath.isEmpty {
            if let url = audioService.getAbsoluteURL(from: wordPath) {
                try? FileManager.default.removeItem(at: url)
                print("🗑️ Deleted word audio: \(wordPath)")
            }
        }

        // Delete sample audios
        for path in word.sampleAudioPaths where !path.isEmpty {
            if let url = audioService.getAbsoluteURL(from: path) {
                try? FileManager.default.removeItem(at: url)
                print("🗑️ Deleted sample audio: \(path)")
            }
        }
    }
}
