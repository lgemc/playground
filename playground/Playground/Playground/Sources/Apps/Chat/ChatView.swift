import SwiftUI

/// Chat conversation view - displays messages and handles LLM streaming
struct ChatView: View {
    let chatId: String

    @State private var chat: Chat?
    @State private var messages: [Message] = []
    @State private var inputText: String = ""
    @State private var isGenerating = false
    @State private var streamingContent = ""
    @State private var scrollTarget: String?
    @State private var useMLX = true // Toggle: true = local MLX, false = OpenAI
    @State private var isLoadingChat = false
    @State private var selectedModel: MLXModelConfig.ChatModel = .llama3_3b_4bit

    private let autocompletion = AutocompletionService.shared
    private let mlx = MLXService.shared

    // Reusable date formatter to avoid creating new instances
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        let _ = print("🔄 ChatView body render - messages: \(messages.count)")
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                timeFormatter: Self.timeFormatter,
                                useMarkdown: false
                            )
                            .id(message.id)
                        }

                        // Streaming message (while generating)
                        if isGenerating && !streamingContent.isEmpty {
                            MessageBubble(
                                message: Message(
                                    id: "streaming",
                                    chatId: chatId,
                                    role: .assistant,
                                    content: streamingContent
                                ),
                                timeFormatter: Self.timeFormatter,
                                useMarkdown: false
                            )
                            .id("streaming")
                        }
                    }
                    .padding()
                }
                .onChange(of: scrollTarget) { oldValue, newValue in
                    guard let target = newValue else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(target, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input area
            HStack(spacing: 12) {
                TextField("Message", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isGenerating || isLoadingChat)
                    .submitLabel(.return)
                    .autocorrectionDisabled()
                    .disableAutocorrection(true)
                    .autocapitalization(.none)

                Button(action: sendMessage) {
                    Image(systemName: isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(inputText.isEmpty && !isGenerating ? .gray : .blue)
                }
                .disabled(inputText.isEmpty && !isGenerating)
            }
            .padding()
            .padding(.bottom, 20)  // Add extra padding to avoid gesture gate
            .background(Color(.systemBackground))
        }
        .navigationTitle(chat?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 8) {
                    // Provider toggle
                    Button(action: {
                        useMLX.toggle()
                        // Unload model when switching to API to free memory
                        if !useMLX {
                            mlx.chat.unloadModel()
                        }
                    }) {
                        Image(systemName: useMLX ? "cpu" : "cloud")
                            .foregroundColor(useMLX ? .green : .blue)
                    }

                    // Model picker (only when MLX is active)
                    if useMLX {
                        Picker("", selection: $selectedModel) {
                            ForEach(MLXModelConfig.ChatModel.allCases, id: \.self) { model in
                                Text(modelShortName(model)).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .foregroundColor(.green)
                    } else {
                        Text("API")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: regenerateTitle) {
                    Image(systemName: "pencil")
                }
            }
        }
        .onAppear(perform: loadChat)
    }

    private func loadChat() {
        guard !isLoadingChat else { return }
        isLoadingChat = true

        print("⏱️ loadChat started")

        Task.detached(priority: .userInitiated) {
            let start = Date()
            let chatResult = await ChatStorage.shared.getChat(id: chatId)
            print("⏱️ getChat took: \(Date().timeIntervalSince(start))s")

            let start2 = Date()
            let messagesResult = await ChatStorage.shared.getMessages(chatId: chatId)
            let messagesCount = await messagesResult.isOk ? messagesResult.value?.count ?? 0 : 0
            print("⏱️ getMessages took: \(Date().timeIntervalSince(start2))s, count: \(messagesCount)")

            await MainActor.run {
                if chatResult.isErr {
                    print("❌ Failed to load chat: \(chatResult.error!)")
                } else {
                    chat = chatResult.value!
                }

                if messagesResult.isErr {
                    print("❌ Failed to load messages: \(messagesResult.error!)")
                } else {
                    messages = messagesResult.value!
                }

                isLoadingChat = false
            }
        }
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }

        let userMessage = inputText
        inputText = ""

        // Dismiss keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        Task.detached(priority: .userInitiated) {
            // Save user message on background thread
            let result = await ChatStorage.shared.createMessage(
                chatId: chatId,
                role: .user,
                content: userMessage
            )

            await MainActor.run {
                if result.isErr {
                    print("❌ Failed to send message: \(result.error!)")
                    return
                }

                messages.append(result.value!)
                scrollTarget = result.value!.id
            }

            // Generate response
            await generateResponse()
        }
    }

    private func generateResponse() async {
        isGenerating = true
        streamingContent = ""

        // Scroll to streaming message initially
        scrollTarget = "streaming"

        do {
            // Convert messages to API format
            let apiMessages = messages.map {
                AutocompletionService.ChatMessage(
                    role: $0.role.rawValue,
                    content: $0.content
                )
            }

            // Stream response with throttled UI updates
            var buffer = ""
            var chunkCount = 0

            // Use MLX or OpenAI based on toggle
            let stream: AsyncThrowingStream<String, Error>
            if useMLX {
                stream = mlx.chat.completeStream(messages: apiMessages, model: selectedModel)
            } else {
                stream = autocompletion.completeStream(messages: apiMessages)
            }

            for try await chunk in stream {
                buffer += chunk
                chunkCount += 1

                // Only update UI every 5 chunks or when buffer is large
                if chunkCount % 5 == 0 || buffer.count > 50 {
                    streamingContent += buffer
                    buffer = ""

                    // Scroll without animation to reduce lag
                    if chunkCount % 20 == 0 {
                        scrollTarget = "streaming"
                    }
                }
            }

            // Flush remaining buffer
            if !buffer.isEmpty {
                streamingContent += buffer
            }

            // Save assistant message
            if !streamingContent.isEmpty {
                let finalContent = streamingContent
                let result = ChatStorage.shared.createMessage(
                    chatId: chatId,
                    role: .assistant,
                    content: finalContent
                )

                if result.isErr {
                    print("❌ Failed to save assistant message: \(result.error!)")
                } else {
                    messages.append(result.value!)
                    scrollTarget = result.value!.id

                    // Auto-generate title if this is the first exchange
                    if messages.count == 2 {
                        await generateTitle()
                    }
                }
            }

        } catch {
            print("❌ Generation failed: \(error)")
        }

        streamingContent = ""
        isGenerating = false
    }

    private func generateTitle() async {
        guard let firstMessage = messages.first else { return }

        let systemPrompt = """
        Generate a concise title (3-5 words) for this conversation based on the user's first message.
        Output ONLY the title, nothing else.
        """

        let result = await autocompletion.prompt(
            firstMessage.content,
            systemPrompt: systemPrompt,
            temperature: 0.3,
            maxTokens: 20
        )

        if result.isErr {
            print("❌ Failed to generate title: \(result.error!)")
            return
        }

        let cleanTitle = result.value!.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty {
            let updateResult = ChatStorage.shared.updateChat(id: chatId, title: cleanTitle)

            if updateResult.isErr {
                print("❌ Failed to update chat title: \(updateResult.error!)")
            } else {
                chat?.title = cleanTitle
            }
        }
    }

    private func regenerateTitle() {
        Task {
            await generateTitle()
        }
    }

    // MARK: - Model Display Helpers

    private func modelShortName(_ model: MLXModelConfig.ChatModel) -> String {
        switch model {
        case .lfm25_1b_4bit:
            return "1.2B"
        case .llama3_3b_4bit:
            return "3B"
        case .mistral_7b_4bit:
            return "7B"
        }
    }

    private func modelDisplayName(_ model: MLXModelConfig.ChatModel) -> String {
        switch model {
        case .lfm25_1b_4bit:
            return "LFM 1.2B (Fast, ~800MB)"
        case .llama3_3b_4bit:
            return "Llama 3.2 3B (~2GB)"
        case .mistral_7b_4bit:
            return "Mistral 7B (Best, ~4.5GB)"
        }
    }
}

/// Message bubble component
struct MessageBubble: View {
    let message: Message
    let timeFormatter: DateFormatter
    let useMarkdown: Bool

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Group {
                    if useMarkdown {
                        MarkdownText(content: message.content, textColor: foregroundColor)
                    } else {
                        Text(message.content)
                            .foregroundColor(foregroundColor)
                    }
                }
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(backgroundColor)
                .cornerRadius(16)

                Text(timeFormatter.string(from: message.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if message.role == .assistant || message.role == .system {
                Spacer()
            }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return .blue
        case .assistant:
            return Color(.systemGray5)
        case .system:
            return Color(.systemGray6)
        }
    }

    private var foregroundColor: Color {
        message.role == .user ? .white : .primary
    }
}

#Preview {
    NavigationStack {
        ChatView(chatId: "preview-chat")
    }
}
