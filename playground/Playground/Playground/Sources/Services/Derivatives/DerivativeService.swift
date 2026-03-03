import Foundation

/// Service that manages derivative generation
/// Matches the Dart DerivativeService implementation with queue integration
class DerivativeService {
    static let shared = DerivativeService()

    private let logger: Logger
    private let queueService = QueueService.shared
    private let storage = DerivativeStorage.shared
    private var generators: [String: DerivativeGenerator] = [:]
    private var queueSubscriptionId: String?

    private init() {
        self.logger = Logger(appId: "file_system", appName: "File System")
    }

    // MARK: - Initialization

    /// Initialize the service and register default generators
    func initialize() {
        print("🚀 [DerivativeService] Initializing...")

        // Register default generators
        registerGenerator(TranscriptDerivativeGenerator())
        registerGenerator(SummaryDerivativeGenerator())

        print("   Registered generators: \(Array(generators.keys))")

        // Subscribe to derivative.create queue
        queueSubscriptionId = queueService.subscribe(
            id: "derivative-service",
            queueId: "derivative-generator",
            name: "Derivative Generator Service"
        ) { [weak self] message in
            await self?.processDerivativeMessage(message) ?? false
        }

        print("   Subscribed to queue: derivative-generator")

        logger.info(
            "DerivativeService initialized with \(generators.count) generators",
            eventType: "derivative.service.init",
            metadata: [
                "generators": Array(generators.keys)
            ]
        )

        print("✅ [DerivativeService] Initialization complete!")
    }

    // MARK: - Generator Registration

    /// Register a derivative generator
    func registerGenerator(_ generator: DerivativeGenerator) {
        generators[generator.type] = generator
        logger.debug(
            "Registered generator: \(generator.displayName) (\(generator.type))",
            eventType: "derivative.generator.register"
        )
    }

    /// Get all registered generators
    func getGenerators() -> [DerivativeGenerator] {
        return Array(generators.values)
    }

    /// Get generator by type
    func getGenerator(type: String) -> DerivativeGenerator? {
        return generators[type]
    }

    /// Get available generators for a file
    func getAvailableGenerators(for file: FileItem) -> [DerivativeGenerator] {
        return generators.values.filter { $0.canProcess(file: file) }
    }

    // MARK: - Derivative Creation

    /// Request derivative generation (emits event to queue)
    /// This matches the Dart implementation pattern
    func requestDerivative(fileId: String, filePath: String, type: String) {
        print("📝 [DerivativeService] Requesting derivative generation")
        print("   Type: \(type)")
        print("   File: \(filePath)")
        print("   File ID: \(fileId)")

        // Create derivative record with pending status
        do {
            _ = try storage.createDerivative(fileId: fileId, type: type).get()
        } catch {
            print("❌ [DerivativeService] Failed to create derivative record: \(error)")
            return
        }

        logger.info(
            "Requesting derivative generation",
            eventType: "derivative.request",
            metadata: [
                "file_id": fileId,
                "type": type
            ]
        )

        // Emit event to AppBus (will be routed to queue)
        AppBus.shared.emit(
            type: "derivative.create",
            appId: "file_system",
            payload: [
                "file_id": fileId,
                "file_path": filePath,
                "type": type
            ]
        )

        print("✅ [DerivativeService] Event emitted to AppBus")
    }

    // MARK: - Queue Message Processing

    /// Process derivative.create message from queue
    private func processDerivativeMessage(_ message: QueueMessage) async -> Bool {
        print("📦 [DerivativeService] Received message from queue")
        print("   Message ID: \(message.id)")
        print("   Event Type: \(message.eventType)")

        guard let payload = message.getPayload() else {
            print("❌ [DerivativeService] Invalid message payload")
            logger.error(
                "Invalid message payload",
                eventType: "derivative.queue.error",
                metadata: ["message_id": message.id]
            )
            return false
        }

        guard let fileId = payload["file_id"] as? String,
              let filePath = payload["file_path"] as? String,
              let type = payload["type"] as? String else {
            print("❌ [DerivativeService] Missing required fields in payload")
            print("   Payload: \(payload)")
            logger.error(
                "Missing required fields in payload",
                eventType: "derivative.queue.error",
                metadata: [
                    "message_id": message.id,
                    "payload": payload
                ]
            )
            return false
        }

        print("🔧 [DerivativeService] Processing derivative generation")
        print("   File ID: \(fileId)")
        print("   File Path: \(filePath)")
        print("   Type: \(type)")
        print("   Delivery Count: \(message.deliveryCount)")

        logger.info(
            "Processing derivative generation from queue",
            eventType: "derivative.queue.process",
            metadata: [
                "message_id": message.id,
                "file_id": fileId,
                "type": type,
                "delivery_count": message.deliveryCount
            ]
        )

        // Find generator
        guard let generator = generators[type] else {
            print("❌ [DerivativeService] No generator found for type: \(type)")
            print("   Available generators: \(Array(generators.keys))")
            logger.error(
                "No generator found for type: \(type)",
                eventType: "derivative.queue.error",
                metadata: [
                    "message_id": message.id,
                    "type": type
                ]
            )
            return false
        }

        print("🎯 [DerivativeService] Found generator: \(generator.displayName)")

        // Resolve file path to absolute path if needed
        let absolutePath = resolveToAbsolutePath(filePath)
        print("📁 [DerivativeService] Resolved path: \(absolutePath)")

        // Create FileItem from payload
        let fileURL = URL(fileURLWithPath: absolutePath)

        let file = createFileItem(
            id: fileId,
            path: absolutePath,
            url: fileURL,
            payload: payload
        )

        // Generate derivative
        do {
            print("⚡ [DerivativeService] Starting generation...")
            let outputPath = try await generator.generate(file: file)

            print("✅ [DerivativeService] Derivative generated successfully!")
            print("   Output: \(outputPath)")

            // Update derivative status to complete
            _ = storage.markDerivativeComplete(fileId: fileId, type: type, outputPath: outputPath)

            logger.info(
                "Derivative generated successfully",
                eventType: "derivative.complete",
                metadata: [
                    "message_id": message.id,
                    "file_id": fileId,
                    "type": type,
                    "output_path": outputPath
                ]
            )

            // Emit completion event
            AppBus.shared.emit(
                type: "derivative.complete",
                appId: "file_system",
                payload: [
                    "file_id": fileId,
                    "type": type,
                    "output_path": outputPath
                ]
            )

            return true
        } catch {
            print("❌ [DerivativeService] Derivative generation failed!")
            print("   Error: \(error.localizedDescription)")

            // Update derivative status to failed
            _ = storage.markDerivativeFailed(fileId: fileId, type: type, errorMessage: error.localizedDescription)

            logger.error(
                "Derivative generation failed: \(error.localizedDescription)",
                eventType: "derivative.error",
                metadata: [
                    "message_id": message.id,
                    "file_id": fileId,
                    "type": type,
                    "error": error.localizedDescription,
                    "delivery_count": message.deliveryCount
                ]
            )
            return false
        }
    }

    // MARK: - Helpers

    /// Create FileItem from message payload
    private func createFileItem(
        id: String,
        path: String,
        url: URL,
        payload: [String: Any]
    ) -> FileItem {
        let mimeType = payload["mime_type"] as? String
        let size = (payload["size"] as? NSNumber)?.int64Value
        let createdAt = (payload["created_at"] as? String).flatMap {
            ISO8601DateFormatter().date(from: $0)
        } ?? Date()
        let updatedAt = (payload["updated_at"] as? String).flatMap {
            ISO8601DateFormatter().date(from: $0)
        } ?? Date()

        return FileItem(
            id: id,
            path: path,
            name: url.lastPathComponent,
            mimeType: mimeType,
            size: size,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Resolve a potentially relative path to an absolute path
    /// Relative paths are relative to data/file_system/storage/
    private func resolveToAbsolutePath(_ path: String) -> String {
        // If already absolute, return as-is
        if path.hasPrefix("/") {
            return path
        }

        // Resolve relative path against data/file_system/storage directory
        guard let documentsURL = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            print("⚠️ [DerivativeService] Failed to get documents directory, using path as-is: \(path)")
            return path
        }

        let storageDirectory = documentsURL
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("file_system", isDirectory: true)
            .appendingPathComponent("storage", isDirectory: true)

        let absolutePath = storageDirectory.appendingPathComponent(path).path
        print("🔧 [DerivativeService] Resolved relative path '\(path)' to '\(absolutePath)'")
        return absolutePath
    }

    // MARK: - Cleanup

    /// Dispose resources
    func dispose() {
        if let subscriptionId = queueSubscriptionId {
            queueService.unsubscribe(subscriptionId: subscriptionId)
            queueSubscriptionId = nil
        }

        logger.info(
            "DerivativeService disposed",
            eventType: "derivative.service.dispose"
        )
    }
}
