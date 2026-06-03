import SwiftUI
import FoundationModels
import ImagePlayground
import AVFoundation

/// Chat conversation view - displays messages and handles LLM streaming
struct ChatView: View {
    let chatId: String

    @State private var chat: Chat?
    @State private var messages: [Message] = []
    @State private var inputText: String = ""
    @State private var isGenerating = false
    @State private var streamingContent = ""
    @State private var scrollTarget: String?
    @State private var isLoadingChat = false
    private let selectedModel: MLXModelConfig.ChatModel = .qwen3_5_2b_6bit


    private let mlx = MLXService.shared

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
            .onAppear(perform: loadChat)
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
            let conversationHistory = messages.map {
                AutocompletionService.ChatMessage(
                    role: $0.role.rawValue,
                    content: $0.content
                )
            }

            var buffer = ""
            var chunkCount = 0

            // Use MLX streaming with Qwen2B
            let stream = mlx.chat.completeStream(messages: conversationHistory, model: selectedModel)

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

            // Save the message
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
            streamingContent += "\n\n_Error: \(error.localizedDescription)_"
        }

        streamingContent = ""
        isGenerating = false
    }


    private func generateTitle() async {
        guard let firstMessage = messages.first else { return }

        do {
            var titleBuffer = ""

            let messages = [
                AutocompletionService.ChatMessage(role: "system", content: "Generate a concise title (3-5 words) for this conversation. Output ONLY the title."),
                AutocompletionService.ChatMessage(role: "user", content: firstMessage.content)
            ]

            let stream = mlx.chat.completeStream(messages: messages, model: selectedModel)
            for try await chunk in stream {
                titleBuffer += chunk
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


}

/// Message bubble component
struct MessageBubble: View {
    let message: Message
    let timeFormatter: DateFormatter
    let useMarkdown: Bool

    @State private var isPlaying: Bool = false
    @State private var audioPlayer: AVAudioPlayer? = nil
    private let fileStorage = FileStorage.shared

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
                } else if message.content.hasPrefix("audio://") {
                    // Audio file message
                    let fileId = String(message.content.dropFirst("audio://".count))
                    audioPlayerView(fileId: fileId)
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

    @ViewBuilder
    private func audioPlayerView(fileId: String) -> some View {
        let fileResult = fileStorage.getFile(id: fileId)
        if case .ok(let file) = fileResult, let file = file {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .foregroundColor(foregroundColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.body)
                        .foregroundColor(foregroundColor)
                        .lineLimit(1)

                    Text(file.formattedSize)
                        .font(.caption)
                        .foregroundColor(foregroundColor.opacity(0.7))
                }

                Spacer()

                Button(action: {
                    togglePlayAudio(file: file)
                }) {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(isPlaying ? Color.red : Color.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(backgroundColor)
            .cornerRadius(16)
        } else {
            Text("🔊 Audio file not found")
                .foregroundColor(.secondary)
                .padding(12)
                .background(backgroundColor)
                .cornerRadius(16)
        }
    }

    private func togglePlayAudio(file: File) {
        if isPlaying {
            stopAudio()
        } else {
            playAudio(file: file)
        }
    }

    private func playAudio(file: File) {
        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)

            let url = URL(fileURLWithPath: file.absolutePath)

            // Check if file exists
            guard FileManager.default.fileExists(atPath: file.absolutePath) else {
                print("❌ Audio file not found: \(file.absolutePath)")
                return
            }

            print("🔊 Playing audio from: \(file.absolutePath)")
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()

            guard let player = audioPlayer else {
                print("❌ Failed to create audio player")
                return
            }

            let success = player.play()
            if success {
                isPlaying = true
                print("✅ Audio started playing (duration: \(player.duration)s)")

                // Auto-stop when done
                DispatchQueue.main.asyncAfter(deadline: .now() + player.duration + 0.5) {
                    self.isPlaying = false
                }
            } else {
                print("❌ Failed to start audio playback")
            }
        } catch {
            print("❌ Failed to play audio: \(error)")
            isPlaying = false
        }
    }

    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }
}

#Preview {
    NavigationStack {
        ChatView(chatId: "preview-chat")
    }
}
