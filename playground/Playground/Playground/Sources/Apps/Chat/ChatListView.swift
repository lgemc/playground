import SwiftUI

/// Chat list view - shows all conversations
struct ChatListView: View {
    @State private var chats: [Chat] = []
    @State private var isLoading = false

    var body: some View {
        List {
            ForEach(chats) { chat in
                NavigationLink(destination: ChatView(chatId: chat.id)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chat.title)
                            .font(.headline)

                        Text(formatDate(chat.updatedAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: deleteChats)
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: createNewChat) {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .onAppear(perform: loadChats)
        .refreshable {
            loadChats()
        }
    }

    private func loadChats() {
        isLoading = true

        let result = ChatStorage.shared.getAllChats()
        if result.isErr {
            print("❌ Failed to load chats: \(result.error!)")
        } else {
            chats = result.value!
        }

        isLoading = false
    }

    private func createNewChat() {
        let result = ChatStorage.shared.createChat()
        if result.isErr {
            print("❌ Failed to create chat: \(result.error!)")
        } else {
            chats.insert(result.value!, at: 0)
        }
    }

    private func deleteChats(at offsets: IndexSet) {
        for index in offsets {
            let chat = chats[index]
            let result = ChatStorage.shared.deleteChat(id: chat.id)

            if result.isErr {
                print("❌ Failed to delete chat: \(result.error!)")
            } else {
                chats.remove(at: index)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationStack {
        ChatListView()
    }
}
