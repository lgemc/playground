import Foundation
import Combine
import GRDB

/// Event model for the AppBus
struct AppBusEvent: Codable, Identifiable {
    let id: String
    let type: String
    let appId: String?
    let payload: String? // JSON
    let timestamp: Date

    init(id: String = UUID().uuidString,
         type: String,
         appId: String? = nil,
         payload: [String: Any]? = nil) {
        self.id = id
        self.type = type
        self.appId = appId
        self.timestamp = Date()

        // Encode payload to JSON
        if let payload = payload {
            self.payload = try? String(
                data: JSONSerialization.data(withJSONObject: payload),
                encoding: .utf8
            )
        } else {
            self.payload = nil
        }
    }

    /// Decode payload from JSON
    func getPayload() -> [String: Any]? {
        guard let payloadString = payload,
              let data = payloadString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

// GRDB conformance
extension AppBusEvent: FetchableRecord, PersistableRecord {
    static let databaseTableName = "app_bus_events"
}

/// Pub/Sub event bus for inter-app communication
/// Events are persisted to SQLite for durability
class AppBus: ObservableObject {
    static let shared = AppBus()

    private let database = PlaygroundDatabase.shared
    private var subscribers: [String: [(AppBusEvent) -> Void]] = [:]
    private let eventSubject = PassthroughSubject<AppBusEvent, Never>()

    private init() {
        // Set up event stream forwarding to subscribers
        eventSubject
            .sink { [weak self] event in
                self?.notifySubscribers(event: event)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Publish Events

    /// Emit an event to the bus
    /// Events are persisted to database and broadcast to subscribers
    func emit(type: String, appId: String? = nil, payload: [String: Any]? = nil) {
        let event = AppBusEvent(type: type, appId: appId, payload: payload)

        // Persist to database
        do {
            try database.execute { db in
                try event.insert(db)
            }
        } catch {
            print("❌ Failed to persist event: \(error)")
        }

        // Broadcast to subscribers
        eventSubject.send(event)
    }

    // MARK: - Subscribe to Events

    /// Subscribe to events of a specific type
    /// Returns a subscription ID that can be used to unsubscribe
    @discardableResult
    func subscribe(eventType: String, handler: @escaping (AppBusEvent) -> Void) -> String {
        let subscriptionId = UUID().uuidString

        if subscribers[eventType] == nil {
            subscribers[eventType] = []
        }

        subscribers[eventType]?.append(handler)
        return subscriptionId
    }

    /// Subscribe to all events (useful for debugging/logging)
    @discardableResult
    func subscribeToAll(handler: @escaping (AppBusEvent) -> Void) -> String {
        return subscribe(eventType: "*", handler: handler)
    }

    /// Unsubscribe from events (currently removes all handlers for a type)
    func unsubscribe(eventType: String) {
        subscribers.removeValue(forKey: eventType)
    }

    private func notifySubscribers(event: AppBusEvent) {
        // Notify type-specific subscribers
        if let handlers = subscribers[event.type] {
            for handler in handlers {
                handler(event)
            }
        }

        // Notify wildcard subscribers
        if let wildcardHandlers = subscribers["*"] {
            for handler in wildcardHandlers {
                handler(event)
            }
        }
    }

    // MARK: - Query Events

    /// Get all events of a specific type
    func getEvents(type: String, limit: Int = 100) -> [AppBusEvent] {
        do {
            return try database.read { db in
                try AppBusEvent
                    .filter(Column("type") == type)
                    .order(Column("timestamp").desc)
                    .limit(limit)
                    .fetchAll(db)
            }
        } catch {
            print("❌ Failed to fetch events: \(error)")
            return []
        }
    }

    /// Get events from a specific app
    func getEvents(fromApp appId: String, limit: Int = 100) -> [AppBusEvent] {
        do {
            return try database.read { db in
                try AppBusEvent
                    .filter(Column("app_id") == appId)
                    .order(Column("timestamp").desc)
                    .limit(limit)
                    .fetchAll(db)
            }
        } catch {
            print("❌ Failed to fetch events: \(error)")
            return []
        }
    }

    /// Get recent events (for debugging)
    func getRecentEvents(limit: Int = 50) -> [AppBusEvent] {
        do {
            return try database.read { db in
                try AppBusEvent
                    .order(Column("timestamp").desc)
                    .limit(limit)
                    .fetchAll(db)
            }
        } catch {
            print("❌ Failed to fetch events: \(error)")
            return []
        }
    }

    /// Clear old events (cleanup)
    func clearOldEvents(olderThan days: Int = 30) throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        try database.execute { db in
            _ = try AppBusEvent
                .filter(Column("timestamp") < cutoffDate)
                .deleteAll(db)
        }
    }
}
