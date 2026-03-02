import Foundation
import GRDB

/// Vocabulary word model - simple implementation matching Dart version
struct VocabularyWord: Codable, Identifiable {
    var id: String
    var word: String
    var meaning: String
    var samplePhrases: [String]
    var wordAudioPath: String?
    var sampleAudioPaths: [String]
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         word: String,
         meaning: String = "",
         samplePhrases: [String] = [],
         wordAudioPath: String? = nil,
         sampleAudioPaths: [String] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.word = word
        self.meaning = meaning
        self.samplePhrases = samplePhrases
        self.wordAudioPath = wordAudioPath
        self.sampleAudioPaths = sampleAudioPaths
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// GRDB conformance
extension VocabularyWord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "vocabulary_words"

    enum Columns {
        static let id = Column("id")
        static let word = Column("word")
        static let meaning = Column("meaning")
        static let samplePhrases = Column("sample_phrases")
        static let wordAudioPath = Column("word_audio_path")
        static let sampleAudioPaths = Column("sample_audio_paths")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    // Custom encoding to convert arrays to JSON strings
    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.word] = word
        container[Columns.meaning] = meaning
        container[Columns.wordAudioPath] = wordAudioPath
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt

        // Encode arrays as JSON strings
        let encoder = JSONEncoder()
        container[Columns.samplePhrases] = try String(data: encoder.encode(samplePhrases), encoding: .utf8)
        container[Columns.sampleAudioPaths] = try String(data: encoder.encode(sampleAudioPaths), encoding: .utf8)
    }

    // Custom decoding to parse JSON strings to arrays
    init(row: Row) throws {
        id = row[Columns.id]
        word = row[Columns.word]
        meaning = row[Columns.meaning] ?? ""
        wordAudioPath = row[Columns.wordAudioPath]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]

        // Decode JSON strings to arrays
        let decoder = JSONDecoder()
        if let phrasesJSON: String = row[Columns.samplePhrases],
           let phrasesData = phrasesJSON.data(using: .utf8) {
            samplePhrases = try decoder.decode([String].self, from: phrasesData)
        } else {
            samplePhrases = []
        }

        if let audioPathsJSON: String = row[Columns.sampleAudioPaths],
           let audioPathsData = audioPathsJSON.data(using: .utf8) {
            sampleAudioPaths = try decoder.decode([String].self, from: audioPathsData)
        } else {
            sampleAudioPaths = []
        }
    }
}
