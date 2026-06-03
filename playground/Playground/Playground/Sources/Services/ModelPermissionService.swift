import Foundation
import GRDB

/// Model download permission
struct ModelPermission: Codable {
    let modelId: String
    let modelType: String
    var approved: Bool
    var approvedAt: Date?
    var deniedAt: Date?
    var lastPromptedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    enum Columns {
        static let modelId = Column("model_id")
        static let modelType = Column("model_type")
        static let approved = Column("approved")
        static let approvedAt = Column("approved_at")
        static let deniedAt = Column("denied_at")
        static let lastPromptedAt = Column("last_prompted_at")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }
}

extension ModelPermission: FetchableRecord, PersistableRecord {
    static let databaseTableName = "model_permissions"

    func encode(to container: inout PersistenceContainer) throws {
        container["model_id"] = modelId
        container["model_type"] = modelType
        container["approved"] = approved
        container["approved_at"] = approvedAt
        container["denied_at"] = deniedAt
        container["last_prompted_at"] = lastPromptedAt
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }
}

/// Service to manage model download permissions
class ModelPermissionService {
    static let shared = ModelPermissionService()
    private let database = PlaygroundDatabase.shared

    private init() {}

    // MARK: - Permission Check

    /// Check if model download is approved
    func isApproved(modelId: String) -> Bool {
        let result: Result<Bool, Error> = Result {
            try database.read { db in
                if let permission = try ModelPermission.fetchOne(db, key: modelId) {
                    return permission.approved
                }
                return false
            }
        }

        switch result {
        case .ok(let approved):
            return approved
        case .err:
            return false
        }
    }

    /// Get permission for a model
    func getPermission(modelId: String) -> Result<ModelPermission?, Error> {
        return Result {
            try database.read { db in
                try ModelPermission.fetchOne(db, key: modelId)
            }
        }
    }

    // MARK: - Approve/Deny

    /// Approve model download
    func approve(modelId: String, modelType: String) -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                let now = Date()

                if var existing = try ModelPermission.fetchOne(db, key: modelId) {
                    // Update existing
                    existing.approved = true
                    existing.approvedAt = now
                    existing.deniedAt = nil
                    existing.updatedAt = now
                    try existing.update(db)
                } else {
                    // Create new
                    let permission = ModelPermission(
                        modelId: modelId,
                        modelType: modelType,
                        approved: true,
                        approvedAt: now,
                        deniedAt: nil,
                        lastPromptedAt: now,
                        createdAt: now,
                        updatedAt: now
                    )
                    try permission.insert(db)
                }
            }
        }
    }

    /// Deny model download
    func deny(modelId: String, modelType: String) -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                let now = Date()

                if var existing = try ModelPermission.fetchOne(db, key: modelId) {
                    // Update existing
                    existing.approved = false
                    existing.approvedAt = nil
                    existing.deniedAt = now
                    existing.updatedAt = now
                    try existing.update(db)
                } else {
                    // Create new
                    let permission = ModelPermission(
                        modelId: modelId,
                        modelType: modelType,
                        approved: false,
                        approvedAt: nil,
                        deniedAt: now,
                        lastPromptedAt: now,
                        createdAt: now,
                        updatedAt: now
                    )
                    try permission.insert(db)
                }
            }
        }
    }

    /// Record that user was prompted for this model
    func recordPrompt(modelId: String, modelType: String) -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                let now = Date()

                if var existing = try ModelPermission.fetchOne(db, key: modelId) {
                    existing.lastPromptedAt = now
                    existing.updatedAt = now
                    try existing.update(db)
                } else {
                    let permission = ModelPermission(
                        modelId: modelId,
                        modelType: modelType,
                        approved: false,
                        approvedAt: nil,
                        deniedAt: nil,
                        lastPromptedAt: now,
                        createdAt: now,
                        updatedAt: now
                    )
                    try permission.insert(db)
                }
            }
        }
    }

    /// Reset permission (delete)
    func resetPermission(modelId: String) -> Result<Void, Error> {
        return Result {
            try database.execute { db in
                _ = try ModelPermission.deleteOne(db, key: modelId)
            }
        }
    }

    /// Get all permissions
    func getAllPermissions() -> Result<[ModelPermission], Error> {
        return Result {
            try database.read { db in
                try ModelPermission.fetchAll(db)
            }
        }
    }
}
