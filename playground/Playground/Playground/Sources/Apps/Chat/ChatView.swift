import SwiftUI
import FoundationModels
import ImagePlayground

/// Chat conversation view - displays messages and handles LLM streaming
struct ChatView: View {
    enum ChatProvider: String, CaseIterable {
        case foundationModels = "Apple"
        case mlx = "MLX"
        case openai = "API"

        var icon: String {
            switch self {
            case .foundationModels: return "apple.logo"
            case .mlx: return "cpu"
            case .openai: return "cloud"
            }
        }
    }

    let chatId: String

    @State private var chat: Chat?
    @State private var messages: [Message] = []
    @State private var inputText: String = ""
    @State private var isGenerating = false
    @State private var streamingContent = ""
    @State private var scrollTarget: String?
    @State private var selectedProvider: ChatProvider = .foundationModels
    @State private var isLoadingChat = false
    @State private var selectedModel: MLXModelConfig.ChatModel = .qwen3_5_4b_4bit
    @State private var foundationSession: LanguageModelSession?

    // Image generation
    @State private var showImageGenerator = false
    @State private var showImagePromptDialog = false
    @State private var imagePrompt = ""

    private let autocompletion = AutocompletionService.shared
    private let mlx = MLXService.shared
    private let systemModel = SystemLanguageModel.default

    // Reusable date formatter to avoid creating new instances
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        let _ = print("🔄 ChatView body render - messages: \(messages.count)")
        contentView
            .navigationTitle(chat?.title ?? "Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear(perform: handleOnAppear)
            .alert("Generate Image", isPresented: $showImagePromptDialog) {
                imagePromptAlertContent
            } message: {
                Text("Describe what you want to generate")
            }
            .imagePlaygroundSheet(
                isPresented: $showImageGenerator,
                concept: imagePrompt.isEmpty ? "a creative image" : imagePrompt,
                onCompletion: handleImageCompletion
            )
    }

    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: 0) {
            messagesScrollView
            Divider()
            inputArea
        }
    }

    @ViewBuilder
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(
                            message: message,
                            timeFormatter: Self.timeFormatter,
                            useMarkdown: true
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
                            useMarkdown: true
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
    }

    @ViewBuilder
    private var inputArea: some View {
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
        .padding(.bottom, 20)
        .background(Color(.systemBackground))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            HStack(spacing: 8) {
                providerPicker
                if selectedProvider == .mlx {
                    modelPicker
                }
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            actionsMenu
        }
    }

    @ViewBuilder
    private var providerPicker: some View {
        Picker("", selection: $selectedProvider) {
            ForEach(availableProviders(), id: \.self) { provider in
                Label(provider.rawValue, systemImage: provider.icon)
                    .tag(provider)
            }
        }
        .pickerStyle(.menu)
        .onChange(of: selectedProvider) { oldValue, newValue in
            if oldValue == .mlx && newValue != .mlx {
                mlx.chat.unloadModel()
            }
        }
    }

    @ViewBuilder
    private var modelPicker: some View {
        Picker("", selection: $selectedModel) {
            ForEach(MLXModelConfig.ChatModel.allCases, id: \.self) { model in
                Text(modelShortName(model)).tag(model)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var actionsMenu: some View {
        Menu {
            Button(action: { showImagePromptDialog = true }) {
                Label("Generate Image", systemImage: "photo.on.rectangle.angled")
            }

            Button(action: regenerateTitle) {
                Label("Regenerate Title", systemImage: "pencil")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private var imagePromptAlertContent: some View {
        TextField("Describe the image...", text: $imagePrompt)
        Button("Generate") {
            if !imagePrompt.isEmpty {
                showImageGenerator = true
            }
        }
        Button("Cancel", role: .cancel) {
            imagePrompt = ""
        }
    }

    private func handleOnAppear() {
        loadChat()
        initializeFoundationModels()

        if systemModel.availability != .available && selectedProvider == .foundationModels {
            selectedProvider = .mlx
        }
    }

    private func handleImageCompletion(url: URL?) {
        if let url = url {
            Task {
                await handleGeneratedImage(url: url)
            }
        }
        imagePrompt = ""
    }

    private func availableProviders() -> [ChatProvider] {
        var providers: [ChatProvider] = []

        // Check if Foundation Models is available
        if systemModel.availability == .available {
            providers.append(.foundationModels)
        }

        providers.append(.mlx)
        providers.append(.openai)

        return providers
    }

    private func initializeFoundationModels() {
        guard systemModel.availability == .available else {
            print("⚠️ Foundation Models not available: \(systemModel.availability)")
            return
        }

        foundationSession = LanguageModelSession {
            """
            You are a helpful assistant. Keep responses clear, concise, and friendly.
            """
        }

        print("✅ Foundation Models session initialized")
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

        // Route to appropriate provider
        switch selectedProvider {
        case .foundationModels:
            await generateWithFoundationModels()
            streamingContent = ""
            isGenerating = false
            return

        case .mlx, .openai:
            break  // Continue with existing implementation below
        }

        do {
            // Convert messages to API format
            var conversationHistory = messages.map {
                AutocompletionService.ChatMessage(
                    role: $0.role.rawValue,
                    content: $0.content
                )
            }

            // Get available tools (only when using API, not MLX or Foundation Models)
            let tools: [[String: Any]]?
            if selectedProvider == .mlx {
                tools = nil  // MLX doesn't support tools
            } else {
                tools = await ToolService.shared.toOpenAIFormat()
            }

            // Tool calling loop - continue until LLM responds without tool calls
            while true {
                var buffer = ""
                var chunkCount = 0
                var toolCalls: [(id: String, name: String, args: [String: Any])] = []
                var isDone = false

                // Stream response with tools support
                if let tools = tools, !tools.isEmpty {
                    // Use tool-enabled streaming
                    let stream = autocompletion.completeWithTools(
                        messages: conversationHistory,
                        tools: tools
                    )

                    for try await event in stream {
                        switch event {
                        case .contentChunk(let chunk):
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

                        case .toolCall(let id, let name, let args):
                            toolCalls.append((id, name, args))

                        case .done:
                            isDone = true
                        }
                    }
                } else {
                    // Use regular streaming (no tools)
                    let stream: AsyncThrowingStream<String, Error>
                    if selectedProvider == .mlx {
                        stream = mlx.chat.completeStream(messages: conversationHistory, model: selectedModel)
                    } else {
                        stream = autocompletion.completeStream(messages: conversationHistory)
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
                    isDone = true
                }

                // Flush remaining buffer
                if !buffer.isEmpty {
                    streamingContent += buffer
                }

                // If no tool calls, we're done - save the message
                if toolCalls.isEmpty {
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
                    break  // Exit the tool calling loop
                }

                // Save current streaming content before tool execution
                let assistantContentBeforeTools = streamingContent

                // Execute tool calls
                for toolCall in toolCalls {
                    print("🛠️ Executing tool: \(toolCall.name) with args: \(toolCall.args)")

                    // Show tool execution status in UI
                    streamingContent += "\n\n_Executing \(toolCall.name)..._"

                    let result = await ToolService.shared.execute(
                        name: toolCall.name,
                        arguments: toolCall.args
                    )

                    print("🛠️ Tool result: \(result.toJSON())")

                    // Add assistant message with tool call to history
                    conversationHistory.append(AutocompletionService.ChatMessage(
                        role: "assistant",
                        content: assistantContentBeforeTools  // Use saved content, not accumulating UI text
                    ))

                    // Add tool result to history
                    let resultJSON = result.toJSON()
                    let resultString = (try? String(data: JSONSerialization.data(withJSONObject: resultJSON), encoding: .utf8)) ?? "{}"
                    conversationHistory.append(AutocompletionService.ChatMessage(
                        role: "tool",
                        content: resultString
                    ))

                    // Update UI to show tool executed
                    if result.isSuccess {
                        streamingContent += " ✅"
                    } else {
                        streamingContent += " ❌"
                    }
                }

                // Reset streaming content for next iteration (clear the tool execution UI messages)
                streamingContent = ""
            }

        } catch {
            print("❌ Generation failed: \(error)")
            streamingContent += "\n\n_Error: \(error.localizedDescription)_"
        }

        streamingContent = ""
        isGenerating = false
    }

    private func generateWithFoundationModels() async {
        guard let session = foundationSession else {
            await MainActor.run {
                streamingContent = "⚠️ Foundation Models not available"
            }
            return
        }

        do {
            // Build conversation context from message history
            let conversationContext = messages.map { message in
                "\(message.role.rawValue): \(message.content)"
            }.joined(separator: "\n\n")

            // Stream response from Foundation Models
            let stream = session.streamResponse(to: conversationContext)

            var chunkCount = 0

            for try await partial in stream {
                // The partial stream returns String.PartialGenerated, access content directly
                let content = String(partial.content)

                // Update UI every 3 chunks for smoother display
                if chunkCount % 3 == 0 {
                    await MainActor.run {
                        streamingContent = content

                        // Scroll periodically
                        if chunkCount % 15 == 0 {
                            scrollTarget = "streaming"
                        }
                    }
                }
                chunkCount += 1
            }

            // Ensure final content is displayed
            await MainActor.run {
                // Save completed message
                if !streamingContent.isEmpty {
                    let result = ChatStorage.shared.createMessage(
                        chatId: chatId,
                        role: .assistant,
                        content: streamingContent
                    )

                    if result.isErr {
                        print("❌ Failed to save assistant message: \(result.error!)")
                    } else {
                        messages.append(result.value!)
                        scrollTarget = result.value!.id

                        // Auto-generate title if this is the first exchange
                        Task {
                            if messages.count == 2 {
                                await generateTitle()
                            }
                        }
                    }
                }
            }

        } catch {
            await MainActor.run {
                // Handle Foundation Models errors
                let errorMessage: String
                if let nsError = error as NSError? {
                    switch nsError.code {
                    case 1: // Context window exceeded
                        errorMessage = "⚠️ Conversation too long (4096 token limit). Please start a new chat."
                    case 2: // Rate limited
                        errorMessage = "⚠️ System is busy. Please try again in a moment."
                    case 3: // Guardrail violation
                        errorMessage = "⚠️ Content was flagged by safety filters."
                    case 4: // Unsupported language
                        errorMessage = "⚠️ Language not supported by Foundation Models."
                    default:
                        errorMessage = "⚠️ Error: \(error.localizedDescription)"
                    }
                } else {
                    errorMessage = "⚠️ Error: \(error.localizedDescription)"
                }
                streamingContent = errorMessage
            }
        }
    }

    private func handleGeneratedImage(url: URL) async {
        // Save image to permanent storage
        guard let permanentURL = saveImageToPermanentStorage(from: url) else {
            print("❌ Failed to save generated image")
            return
        }

        // Create message with image reference
        let imageContent = "image://\(permanentURL.path)"

        await MainActor.run {
            Task.detached(priority: .userInitiated) {
                let result = await ChatStorage.shared.createMessage(
                    chatId: chatId,
                    role: .user,
                    content: imageContent
                )

                await MainActor.run {
                    if result.isErr {
                        print("❌ Failed to save image message: \(result.error!)")
                    } else {
                        messages.append(result.value!)
                        scrollTarget = result.value!.id
                    }
                }
            }
        }
    }

    private func saveImageToPermanentStorage(from tempURL: URL) -> URL? {
        do {
            // Create images directory if it doesn't exist
            let documentsDir = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first!

            let imagesDir = documentsDir.appendingPathComponent("chat_images")

            if !FileManager.default.fileExists(atPath: imagesDir.path) {
                try FileManager.default.createDirectory(
                    at: imagesDir,
                    withIntermediateDirectories: true
                )
            }

            // Generate unique filename
            let filename = "\(UUID().uuidString).png"
            let permanentURL = imagesDir.appendingPathComponent(filename)

            // Copy image from temporary location
            try FileManager.default.copyItem(at: tempURL, to: permanentURL)

            print("✅ Saved image to: \(permanentURL.path)")
            return permanentURL

        } catch {
            print("❌ Failed to save image: \(error)")
            return nil
        }
    }

    private func generateTitle() async {
        guard let firstMessage = messages.first else { return }

        let prompt = """
        Generate a concise title (3-5 words) for this conversation based on the user's first message: "\(firstMessage.content)"

        Output ONLY the title, nothing else.
        """

        do {
            var titleBuffer = ""

            // Prefer Foundation Models if available, otherwise fall back to MLX
            if let foundationSession = foundationSession {
                // Use Apple Foundation Models for title generation
                let stream = foundationSession.streamResponse(to: prompt)

                for try await partial in stream {
                    let content = String(partial.content)
                    titleBuffer = content
                }
            } else {
                // Fall back to MLX model
                let messages = [
                    AutocompletionService.ChatMessage(role: "system", content: "Generate a concise title (3-5 words) for this conversation. Output ONLY the title."),
                    AutocompletionService.ChatMessage(role: "user", content: firstMessage.content)
                ]

                let stream = mlx.chat.completeStream(messages: messages, model: selectedModel)
                for try await chunk in stream {
                    titleBuffer += chunk
                }
            }

            let cleanTitle = titleBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanTitle.isEmpty {
                let updateResult = ChatStorage.shared.updateChat(id: chatId, title: cleanTitle)

                if updateResult.isErr {
                    print("❌ Failed to update chat title: \(updateResult.error!)")
                } else {
                    chat?.title = cleanTitle
                }
            }
        } catch {
            print("❌ Failed to generate title: \(error)")
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
        case .qwen3_5_2b_6bit:
            return "2B"
        case .llama3_2_3b_4bit:
            return "3B"
        case .qwen3_5_4b_4bit:
            return "4B"
        // case .llama3_2_3b_8bit:
        //     return "3B"
        // case .mistral_7b_4bit:
        //     return "7B"
        }
    }

    private func modelDisplayName(_ model: MLXModelConfig.ChatModel) -> String {
        switch model {
        case .lfm25_1b_4bit:
            return "LFM 1.2B (Fast, ~800MB)"
        case .qwen3_5_2b_6bit:
            return "Qwen3.5 2B (Balanced, ~1.6GB)"
        case .llama3_2_3b_4bit:
            return "Llama 3.2 3B-4bit (~1.85GB)"
        case .qwen3_5_4b_4bit:
            return "Qwen3 4B-4bit (~2.8GB)"
        // case .llama3_2_3b_8bit:
        //     return "Llama 3.2 3B-8bit (HQ, ~3.2GB)"
        // case .mistral_7b_4bit:
        //     return "Mistral 7B (Best, ~4.5GB)"
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
                // Check if message contains an image
                if message.content.hasPrefix("image://") {
                    let imagePath = String(message.content.dropFirst("image://".count))
                    if let uiImage = UIImage(contentsOfFile: imagePath) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 300)
                            .cornerRadius(12)
                            .padding(8)
                            .background(backgroundColor)
                            .cornerRadius(16)
                    } else {
                        Text("🖼️ Image not found")
                            .foregroundColor(.secondary)
                            .padding(12)
                            .background(backgroundColor)
                            .cornerRadius(16)
                    }
                } else {
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
                }

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
