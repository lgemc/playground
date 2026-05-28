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

    // Custom decoding/encoding for metadata
    static func databaseJSONDecoder(for column: String) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func databaseJSONEncoder(for column: String) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["type"] = type.rawValue
        container["input_text"] = inputText
        container["input_file_id"] = inputFileId
        container["output_text"] = outputText
        container["output_file_id"] = outputFileId
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt

        // Encode metadata as JSON string
        if let metadataData = try? JSONEncoder().encode(metadata),
           let metadataString = String(data: metadataData, encoding: .utf8) {
            container["metadata"] = metadataString
        } else {
            container["metadata"] = "{}"
        }
    }

    init(row: Row) throws {
        id = row["id"]

        // Decode enum from string
        let typeString: String = row["type"]
        guard let decodedType = ConversionType(rawValue: typeString) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Invalid conversion type: \(typeString)"
                )
            )
        }
        type = decodedType

        inputText = row["input_text"]
        inputFileId = row["input_file_id"]
        outputText = row["output_text"]
        outputFileId = row["output_file_id"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]

        // Decode metadata from JSON string
        if let metadataString: String = row["metadata"],
           let metadataData = metadataString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: metadataData) {
            metadata = decoded
        } else {
            metadata = [:]
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
