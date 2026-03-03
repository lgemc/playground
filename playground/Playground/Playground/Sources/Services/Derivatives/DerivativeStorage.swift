import Foundation
import GRDB

/// Storage service for derivative management
class DerivativeStorage {
    static let shared = DerivativeStorage()
    private let database = PlaygroundDatabase.shared

    private init() {}

    // MARK: - Derivative CRUD

    /// Create a new derivative record
    func createDerivative(fileId: String, type: String) -> Result<Derivative, Error> {
        return Result {
            let derivative = Derivative(
                fileId: fileId,
                type: type,
                status: .pending
            )

            try database.execute { db in
                try derivative.insert(db)
            }

            print("📝 Created derivative record: \(derivative.id) (\(type)) for file \(fileId)")

            return derivative
        }
    }

    /// Get a derivative by ID
    func getDerivative(id: String) -> Result<Derivative?, Error> {
        return Result {
            try database.read { db in
                try Derivative.fetchOne(db, key: id)
            }
        }
    }

    /// Get all derivatives for a file
    func getDerivatives(forFileId fileId: String) -> Result<[Derivative], Error> {
        return Result {
            try database.read { db in
                try Derivative
                    .filter(Derivative.Columns.fileId == fileId)
                    .order(Derivative.Columns.createdAt.desc)
                    .fetchAll(db)
            }
        }
    }

    /// Get a specific derivative by file ID and type
    func getDerivative(forFileId fileId: String, type: String) -> Result<Derivative?, Error> {
        return Result {
            try database.read { db in
                try Derivative
                    .filter(Derivative.Columns.fileId == fileId)
                    .filter(Derivative.Columns.type == type)
                    .fetchOne(db)
            }
        }
    }

    /// Update derivative status to complete
    func markDerivativeComplete(fileId: String, type: String, outputPath: String) -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                // Find the derivative
                guard var derivative = try Derivative
                    .filter(Derivative.Columns.fileId == fileId)
                    .filter(Derivative.Columns.type == type)
                    .filter(Derivative.Columns.status == DerivativeStatus.pending.rawValue)
                    .fetchOne(db) else {
                    print("⚠️ No pending derivative found for file \(fileId) type \(type)")
                    return
                }

                // Update status
                derivative.status = .complete
                derivative.outputPath = outputPath
                derivative.completedAt = Date()
                derivative.updatedAt = Date()

                try derivative.update(db)

                print("✅ Marked derivative \(derivative.id) as complete: \(outputPath)")
            }
        }
    }

    /// Update derivative status to failed
    func markDerivativeFailed(fileId: String, type: String, errorMessage: String) -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                // Find the derivative
                guard var derivative = try Derivative
                    .filter(Derivative.Columns.fileId == fileId)
                    .filter(Derivative.Columns.type == type)
                    .filter(Derivative.Columns.status == DerivativeStatus.pending.rawValue)
                    .fetchOne(db) else {
                    print("⚠️ No pending derivative found for file \(fileId) type \(type)")
                    return
                }

                // Update status
                derivative.status = .failed
                derivative.errorMessage = errorMessage
                derivative.updatedAt = Date()

                try derivative.update(db)

                print("❌ Marked derivative \(derivative.id) as failed: \(errorMessage)")
            }
        }
    }

    /// Delete a derivative
    func deleteDerivative(id: String) -> Result<Void, Error> {
        return Result {
            // Get derivative info before deletion to access the output path
            let derivativeToDelete = try database.read { db in
                try Derivative.fetchOne(db, key: id)
            }

            // Delete from database
            try database.execute { db in
                _ = try Derivative.deleteOne(db, key: id)
            }

            // Delete physical file if it exists
            if let derivative = derivativeToDelete,
               let outputPath = derivative.outputPath {
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let fileURL = documentsURL.appendingPathComponent(outputPath)

                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                    print("🗑️ Deleted derivative file: \(fileURL.path)")
                }
            }

            print("✅ Deleted derivative record: \(id)")
        }
    }

    /// Get all pending derivatives
    func getPendingDerivatives() -> Result<[Derivative], Error> {
        return Result {
            try database.read { db in
                try Derivative
                    .filter(Derivative.Columns.status == DerivativeStatus.pending.rawValue)
                    .order(Derivative.Columns.createdAt.desc)
                    .fetchAll(db)
            }
        }
    }

    /// Get derivatives by status
    func getDerivatives(status: DerivativeStatus) -> Result<[Derivative], Error> {
        return Result {
            try database.read { db in
                try Derivative
                    .filter(Derivative.Columns.status == status.rawValue)
                    .order(Derivative.Columns.createdAt.desc)
                    .fetchAll(db)
            }
        }
    }

    /// Delete all derivatives for a file
    func deleteDerivatives(forFileId fileId: String) -> Result<Void, Error> {
        return Result {
            // Get all derivatives for the file
            let derivatives = try database.read { db in
                try Derivative
                    .filter(Derivative.Columns.fileId == fileId)
                    .fetchAll(db)
            }

            // Delete physical files
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            for derivative in derivatives {
                if let outputPath = derivative.outputPath {
                    let fileURL = documentsURL.appendingPathComponent(outputPath)
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                }
            }

            // Delete from database
            try database.execute { db in
                _ = try Derivative
                    .filter(Derivative.Columns.fileId == fileId)
                    .deleteAll(db)
            }

            print("🗑️ Deleted all derivatives for file: \(fileId)")
        }
    }
}
