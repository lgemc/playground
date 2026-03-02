import SwiftUI

/// Protocol that all sub-apps must implement
/// Defines the interface for modular apps within the Playground container
@MainActor
protocol SubApp: AnyObject, Identifiable, ObservableObject {
    /// Unique identifier for the app (e.g., "chat", "notes", "vocabulary")
    var id: String { get }

    /// Display name shown in launcher and UI
    var name: String { get }

    /// SF Symbol icon name for the app
    var iconName: String { get }

    /// Theme color for the app
    var themeColor: Color { get }

    /// Whether this app supports global search
    var supportsSearch: Bool { get }

    /// Whether this app supports sharing content
    var supportsSharing: Bool { get }

    /// Accepted content types for sharing (e.g., ["text/plain", "image/png"])
    var acceptedShareTypes: [String] { get }

    /// Build the main view for this app
    @ViewBuilder
    func buildView() -> AnyView

    /// Lifecycle: Called when app is first initialized
    func onInit() async

    /// Lifecycle: Called when app enters foreground
    func onResume() async

    /// Lifecycle: Called when app enters background
    func onPause() async

    /// Lifecycle: Called when app is disposed
    func onDispose() async

    /// Search within this app (if supportsSearch is true)
    func search(query: String) async -> [SearchResult]

    /// Navigate to a specific search result
    func navigateToSearchResult(result: SearchResult) async

    /// Handle shared content from other apps (if supportsSharing is true)
    func onReceiveShare(content: SharedContent) async
}

// Default implementations for optional functionality
extension SubApp {
    var supportsSearch: Bool { false }
    var supportsSharing: Bool { false }
    var acceptedShareTypes: [String] { [] }

    func onInit() async {}
    func onResume() async {}
    func onPause() async {}
    func onDispose() async {}

    func search(query: String) async -> [SearchResult] { [] }
    func navigateToSearchResult(result: SearchResult) async {}
    func onReceiveShare(content: SharedContent) async {}
}

// MARK: - Search Support

/// Represents a search result from a sub-app
struct SearchResult: Identifiable {
    let id: String
    let type: SearchResultType
    let appId: String
    let title: String
    let subtitle: String?
    let preview: String?
    let navigationData: [String: Any]
    let timestamp: Date?

    enum SearchResultType: String {
        case file
        case note
        case vocabularyWord
        case chat
        case chatMessage
        case course
        case activity
    }
}

// MARK: - Sharing Support

/// Represents content being shared between apps
struct SharedContent {
    let type: String // MIME type
    let data: Data
    let metadata: [String: Any]?
}
