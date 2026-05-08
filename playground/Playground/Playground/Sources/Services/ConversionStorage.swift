import Foundation
import GRDB

/// Storage service for AI conversions
class ConversionStorage {
    static let shared = ConversionStorage()
    private let database = PlaygroundDatabase.shared

    private init() {}

    // MARK: - CRUD Operations

    func createConversion(type: ConversionType,
                         inputText: String? = nil,
                         inputFileId: String? = nil,
                         outputText: String? = nil,
                         outputFileId: String? = nil,
                         metadata: [String: String] = [:]) -> Result<Conversion, Error> {
        return Result {
            let conversion = Conversion(
                type: type,
                inputText: inputText,
                inputFileId: inputFileId,
                outputText: outputText,
                outputFileId: outputFileId,
                metadata: metadata
            )
            try database.execute { db in
                try conversion.insert(db)
            }
            return conversion
        }
    }

    func getConversion(id: String) -> Result<Conversion?, Error> {
        return Result {
            try database.read { db in
                try Conversion.fetchOne(db, key: id)
            }
        }
    }

    func getAllConversions() -> Result<[Conversion], Error> {
        return Result {
            try database.read { db in
                try Conversion
                    .order(Conversion.Columns.createdAt.desc)
                    .fetchAll(db)
            }
        }
    }

    func getConversionsByType(type: ConversionType) -> Result<[Conversion], Error> {
        return Result {
            try database.read { db in
                try Conversion
                    .filter(Conversion.Columns.type == type.rawValue)
                    .order(Conversion.Columns.createdAt.desc)
                    .fetchAll(db)
            }
        }
    }

    func updateConversion(id: String,
                         outputText: String? = nil,
                         outputFileId: String? = nil,
                         metadata: [String: String]? = nil) -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                var updates: [String] = []
                var arguments: [DatabaseValueConvertible?] = []

                if let outputText = outputText {
                    updates.append("output_text = ?")
                    arguments.append(outputText)
                }

                if let outputFileId = outputFileId {
                    updates.append("output_file_id = ?")
                    arguments.append(outputFileId)
                }

                if let metadata = metadata,
                   let metadataData = try? JSONEncoder().encode(metadata),
                   let metadataString = String(data: metadataData, encoding: .utf8) {
                    updates.append("metadata = ?")
                    arguments.append(metadataString)
                }

                updates.append("updated_at = ?")
                arguments.append(Date())

                arguments.append(id)

                let sql = "UPDATE conversions SET \(updates.joined(separator: ", ")) WHERE id = ?"
                try db.execute(sql: sql, arguments: StatementArguments(arguments))
            }
        }
    }

    func deleteConversion(id: String) -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                _ = try Conversion.deleteOne(db, key: id)
            }
        }
    }

    func deleteAllConversions() -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                try db.execute(sql: "DELETE FROM conversions")
            }
        }
    }

    // MARK: - Search

    func searchConversions(query: String, limit: Int = 50) -> Result<[Conversion], Error> {
        return Result {
            try database.read { db in
                try Conversion
                    .filter(
                        Conversion.Columns.inputText.like("%\(query)%") ||
                        Conversion.Columns.outputText.like("%\(query)%")
                    )
                    .order(Conversion.Columns.createdAt.desc)
                    .limit(limit)
                    .fetchAll(db)
            }
        }
    }

    // MARK: - Statistics

    func getConversionCount() -> Result<Int, Error> {
        return Result {
            try database.read { db in
                try Conversion.fetchCount(db)
            }
        }
    }

    func getConversionCountByType(type: ConversionType) -> Result<Int, Error> {
        return Result {
            try database.read { db in
                try Conversion
                    .filter(Conversion.Columns.type == type.rawValue)
                    .fetchCount(db)
            }
        }
    }
}
