import Foundation
import GRDB

/// Represents a single AI conversion operation in the history
struct Conversion: Codable, Identifiable {
    var id: String
    var type: ConversionType
    var inputText: String?
    var inputFileId: String?
    var outputText: String?
    var outputFileId: String?
    var metadata: [String: String]
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         type: ConversionType,
         inputText: String? = nil,
         inputFileId: String? = nil,
         outputText: String? = nil,
         outputFileId: String? = nil,
         metadata: [String: String] = [:],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.type = type
        self.inputText = inputText
        self.inputFileId = inputFileId
        self.outputText = outputText
        self.outputFileId = outputFileId
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// GRDB conformance
extension Conversion: FetchableRecord, PersistableRecord {
    static let databaseTableName = "conversions"

    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    enum Columns {
        static let id = Column("id")
        static let type = Column("type")
        static let inputText = Column("input_text")
        static let inputFileId = Column("input_file_id")
        static let outputText = Column("output_text")
        static let outputFileId = Column("output_file_id")
        static let metadata = Column("metadata")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    // Custom encoding/decoding for metadata dictionary
    enum CodingKeys: String, CodingKey {
        case id, type, inputText = "input_text", inputFileId = "input_file_id"
        case outputText = "output_text", outputFileId = "output_file_id"
        case metadata, createdAt = "created_at", updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(ConversionType.self, forKey: .type)
        inputText = try container.decodeIfPresent(String.self, forKey: .inputText)
        inputFileId = try container.decodeIfPresent(String.self, forKey: .inputFileId)
        outputText = try container.decodeIfPresent(String.self, forKey: .outputText)
        outputFileId = try container.decodeIfPresent(String.self, forKey: .outputFileId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        // Decode metadata as JSON string
        if let metadataString = try container.decodeIfPresent(String.self, forKey: .metadata),
           let metadataData = metadataString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: metadataData) {
            metadata = decoded
        } else {
            metadata = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(inputText, forKey: .inputText)
        try container.encodeIfPresent(inputFileId, forKey: .inputFileId)
        try container.encodeIfPresent(outputText, forKey: .outputText)
        try container.encodeIfPresent(outputFileId, forKey: .outputFileId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)

        // Encode metadata as JSON string
        if let metadataData = try? JSONEncoder().encode(metadata),
           let metadataString = String(data: metadataData, encoding: .utf8) {
            try container.encode(metadataString, forKey: .metadata)
        }
    }
}

// Computed properties
extension Conversion {
    /// Display-friendly timestamp (e.g., "2:34 PM")
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    /// Model used for this conversion (from metadata)
    var modelUsed: String? {
        metadata["model"]
    }

    /// Processing duration in seconds (from metadata)
    var durationSeconds: Double? {
        if let durationString = metadata["duration"] {
            return Double(durationString)
        }
        return nil
    }

    /// Short preview of input (first 100 chars)
    var inputPreview: String {
        guard let text = inputText, !text.isEmpty else {
            return inputFileId != nil ? "[File]" : "[No input]"
        }
        return text.count > 100 ? String(text.prefix(100)) + "..." : text
    }

    /// Short preview of output (first 100 chars)
    var outputPreview: String {
        guard let text = outputText, !text.isEmpty else {
            return outputFileId != nil ? "[File]" : "[Processing...]"
        }
        return text.count > 100 ? String(text.prefix(100)) + "..." : text
    }
}
