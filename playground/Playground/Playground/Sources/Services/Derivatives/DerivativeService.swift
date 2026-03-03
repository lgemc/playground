import Foundation

/// Service that manages derivative generation
/// Matches the Dart DerivativeService implementation with queue integration
class DerivativeService {
    static let shared = DerivativeService()

    private let logger: Logger
    private let queueService = QueueService.shared
    private var generators: [String: DerivativeGenerator] = [:]
    private var queueSubscriptionId: String?

    private init() {
        self.logger = Logger(appId: "file_system", appName: "File System")
    }

    // MARK: - Initialization

    /// Initialize the service and register default generators
    func initialize() {
        // Register default generators
        registerGenerator(TranscriptDerivativeGenerator())
        registerGenerator(SummaryDerivativeGenerator())

        // Subscribe to derivative.create queue
        queueSubscriptionId = queueService.subscribe(
            id: "derivative-service",
            queueId: "derivative-generator",
            name: "Derivative Generator Service"
        ) { [weak self] message in
            await self?.processDerivativeMessage(message) ?? false
        }

        logger.info(
            "DerivativeService initialized with \(generators.count) generators",
            eventType: "derivative.service.init",
            metadata: [
                "generators": Array(generators.keys)
            ]
        )
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
    }

    // MARK: - Queue Message Processing

    /// Process derivative.create message from queue
    private func processDerivativeMessage(_ message: QueueMessage) async -> Bool {
        guard let payload = message.getPayload() else {
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

        // Create FileItem from payload
        guard let fileURL = URL(string: filePath) else {
            logger.error(
                "Invalid file path: \(filePath)",
                eventType: "derivative.queue.error",
                metadata: ["message_id": message.id]
            )
            return false
        }

        let file = createFileItem(
            id: fileId,
            path: filePath,
            url: fileURL,
            payload: payload
        )

        // Generate derivative
        do {
            let outputPath = try await generator.generate(file: file)

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
