import SwiftUI
import Combine

/// Chat sub-app - LLM-powered conversations
class ChatApp: SubApp {
    let id = "chat"
    let name = "Chat"
    let iconName = "bubble.left.and.bubble.right.fill"
    let themeColor = Color.blue

    let supportsSearch = true

    // ObservableObject conformance
    let objectWillChange = ObservableObjectPublisher()

    init() {}

    func buildView() -> AnyView {
        AnyView(ChatListView())
    }

    // MARK: - Lifecycle

    func onInit() async {
        print("✅ Chat app initialized")
    }

    // MARK: - Search

    func search(query: String) async -> [SearchResult] {
        // Search in chat titles
        let chatsResult = ChatStorage.shared.searchChats(query: query, limit: 25)
        guard let chats = chatsResult.value else {
            print("❌ Chat search failed: \(chatsResult.error?.localizedDescription ?? "unknown error")")
            return []
        }

        let chatResults = chats.map { chat in
            SearchResult(
                id: chat.id,
                type: .chat,
                appId: id,
                title: chat.title,
                subtitle: nil,
                preview: nil,
                navigationData: ["chatId": chat.id],
                timestamp: chat.updatedAt
            )
        }

        // Search in message content
        let messagesResult = ChatStorage.shared.searchMessages(query: query, limit: 25)
        guard let messages = messagesResult.value else {
            print("❌ Message search failed: \(messagesResult.error?.localizedDescription ?? "unknown error")")
            return chatResults
        }

        let messageResults = messages.compactMap { message -> SearchResult? in
            let chatResult = ChatStorage.shared.getChat(id: message.chatId)
            guard let chat = chatResult.value, let unwrappedChat = chat else {
                return nil
            }

            let preview = message.content.count > 100
                ? String(message.content.prefix(100)) + "..."
                : message.content

            return SearchResult(
                id: message.id,
                type: .chatMessage,
                appId: id,
                title: unwrappedChat.title,
                subtitle: message.role.rawValue.capitalized,
                preview: preview,
                navigationData: ["chatId": message.chatId, "messageId": message.id],
                timestamp: message.createdAt
            )
        }

        return (chatResults + messageResults)
            .sorted { ($0.timestamp ?? Date.distantPast) > ($1.timestamp ?? Date.distantPast) }
    }

    func navigateToSearchResult(result: SearchResult) async {
        // Navigation will be handled by the UI layer
        // This is a placeholder for now
    }
}
