import Foundation

/// Represents a complete transcript with segments and metadata
struct Transcript: Codable, Identifiable {
    var id: String { sourceFile ?? UUID().uuidString }
    let status: String
    let language: String
    let segments: [TranscriptSegment]
    let sourceFile: String?
    let generatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case status
        case language
        case segments
        case sourceFile = "source_file"
        case generatedAt = "generated_at"
    }

    init(status: String = "completed",
         language: String = "en",
         segments: [TranscriptSegment] = [],
         sourceFile: String? = nil,
         generatedAt: Date? = nil) {
        self.status = status
        self.language = language
        self.segments = segments
        self.sourceFile = sourceFile
        self.generatedAt = generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        segments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .segments) ?? []
        sourceFile = try container.decodeIfPresent(String.self, forKey: .sourceFile)

        if let dateString = try container.decodeIfPresent(String.self, forKey: .generatedAt) {
            let formatter = ISO8601DateFormatter()
            generatedAt = formatter.date(from: dateString)
        } else {
            generatedAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(language, forKey: .language)
        try container.encode(segments, forKey: .segments)
        try container.encodeIfPresent(sourceFile, forKey: .sourceFile)

        if let date = generatedAt {
            let formatter = ISO8601DateFormatter()
            try container.encode(formatter.string(from: date), forKey: .generatedAt)
        }
    }

    /// Get full transcript text by concatenating all segments
    var fullText: String {
        segments.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Get total duration in seconds
    var duration: Double {
        guard let last = segments.last else { return 0.0 }
        return last.end
    }

    /// Find segment at a specific timestamp
    func segment(at timestamp: Double) -> TranscriptSegment? {
        segments.first { timestamp >= $0.start && timestamp <= $0.end }
    }

    /// Get all unique speakers
    var speakers: Set<String> {
        Set(segments.map { $0.speaker })
    }

    /// Convert to formatted JSON string
    func toJSONString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Represents a segment of transcribed text with timing information
struct TranscriptSegment: Codable, Identifiable {
    var id: String { "\(start)_\(end)" }
    let start: Double
    let end: Double
    let text: String
    let words: [TranscriptWord]
    let speaker: String

    init(start: Double, end: Double, text: String, words: [TranscriptWord] = [], speaker: String = "UNKNOWN") {
        self.start = start
        self.end = end
        self.text = text
        self.words = words
        self.speaker = speaker
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeIfPresent(Double.self, forKey: .start) ?? 0.0
        end = try container.decodeIfPresent(Double.self, forKey: .end) ?? 0.0
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        words = try container.decodeIfPresent([TranscriptWord].self, forKey: .words) ?? []
        speaker = try container.decodeIfPresent(String.self, forKey: .speaker) ?? "UNKNOWN"
    }

    /// Get duration of this segment in seconds
    var duration: Double {
        end - start
    }

    /// Format timestamp as HH:MM:SS or MM:SS
    static func formatTimestamp(_ timestamp: Double) -> String {
        let hours = Int(timestamp) / 3600
        let minutes = (Int(timestamp) % 3600) / 60
        let seconds = Int(timestamp) % 60
        let milliseconds = Int((timestamp.truncatingRemainder(dividingBy: 1)) * 1000)

        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
        }
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }

    var startFormatted: String {
        Self.formatTimestamp(start)
    }

    var endFormatted: String {
        Self.formatTimestamp(end)
    }
}

/// Represents a single word with timing and confidence information
struct TranscriptWord: Codable, Identifiable {
    var id: String { "\(word)_\(start)" }
    let word: String
    let start: Double
    let end: Double
    let score: Double
    let speaker: String

    init(word: String, start: Double, end: Double, score: Double = 1.0, speaker: String = "UNKNOWN") {
        self.word = word
        self.start = start
        self.end = end
        self.score = score
        self.speaker = speaker
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        word = try container.decodeIfPresent(String.self, forKey: .word) ?? ""
        start = try container.decodeIfPresent(Double.self, forKey: .start) ?? 0.0
        end = try container.decodeIfPresent(Double.self, forKey: .end) ?? 0.0
        score = try container.decodeIfPresent(Double.self, forKey: .score) ?? 0.0
        speaker = try container.decodeIfPresent(String.self, forKey: .speaker) ?? "UNKNOWN"
    }

    /// Get duration of this word in seconds
    var duration: Double {
        end - start
    }

    /// Get confidence percentage (0-100)
    var confidencePercent: Double {
        score * 100
    }
}
