import Foundation
import GRDB

/// Storage service for vocabulary words (simple version, no spaced repetition)
/// Matches the Dart implementation
class VocabularyStorage {
    static let shared = VocabularyStorage()
    private let database = PlaygroundDatabase.shared

    private init() {}

    // MARK: - Vocabulary Word CRUD

    func createWord(word: String,
                   meaning: String = "",
                   samplePhrases: [String] = []) -> Result<VocabularyWord, Error> {
        return Result {
            let vocabWord = VocabularyWord(
                word: word,
                meaning: meaning,
                samplePhrases: samplePhrases
            )

            try database.execute { db in
                try vocabWord.insert(db)
            }

            return vocabWord
        }
    }

    func getWord(id: String) async -> Result<VocabularyWord?, Error> {
        return Result {
            try database.read { db in
                try VocabularyWord.fetchOne(db, key: id)
            }
        }
    }

    func getAllWords(includeDeleted: Bool = false) -> Result<[VocabularyWord], Error> {
        return Result {
            try database.read { db in
                let query = VocabularyWord.order(VocabularyWord.Columns.createdAt.desc)
                return try query.fetchAll(db)
            }
        }
    }

    func updateWord(id: String,
                   word: String? = nil,
                   meaning: String? = nil,
                   samplePhrases: [String]? = nil,
                   wordAudioPath: String? = nil,
                   sampleAudioPaths: [String]? = nil) -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                if var existingWord = try VocabularyWord.fetchOne(db, key: id) {
                    if let word = word { existingWord.word = word }
                    if let meaning = meaning { existingWord.meaning = meaning }
                    if let samplePhrases = samplePhrases { existingWord.samplePhrases = samplePhrases }
                    if let wordAudioPath = wordAudioPath { existingWord.wordAudioPath = wordAudioPath }
                    if let sampleAudioPaths = sampleAudioPaths { existingWord.sampleAudioPaths = sampleAudioPaths }
                    existingWord.updatedAt = Date()

                    try existingWord.update(db)
                }
            }
        }
    }

    func deleteWord(id: String) -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                _ = try VocabularyWord.deleteOne(db, key: id)
            }
        }
    }

    // MARK: - Search

    func searchWords(query: String, limit: Int = 50) -> Result<[VocabularyWord], Error> {
        return Result {
            try database.read { db in
                try VocabularyWord
                    .filter(
                        VocabularyWord.Columns.word.like("%\(query)%") ||
                        VocabularyWord.Columns.meaning.like("%\(query)%")
                    )
                    .order(VocabularyWord.Columns.createdAt.desc)
                    .limit(limit)
                    .fetchAll(db)
            }
        }
    }
}
