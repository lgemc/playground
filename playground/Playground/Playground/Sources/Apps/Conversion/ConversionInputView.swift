import SwiftUI
import UniformTypeIdentifiers

/// Input view for creating a new conversion
struct ConversionInputView: View {
    @Environment(\.dismiss) private var dismiss

    let preselectedType: ConversionType?
    let onComplete: (String) -> Void

    @State private var selectedType: ConversionType = .textToText
    @State private var inputText: String = ""
    @State private var selectedFileURL: URL? = nil
    @State private var showFilePicker = false
    @State private var isConverting = false
    @State private var streamingOutput = ""
    @State private var currentConversion: Conversion? = nil
    @State private var progressStatus = ""
    @State private var progressPercentage: Double = 0.0
    @State private var elapsedTime: TimeInterval = 0
    @State private var statusTimer: Timer? = nil

    private let conversionService = ConversionService.shared

    init(preselectedType: ConversionType? = nil, onComplete: @escaping (String) -> Void) {
        self.preselectedType = preselectedType
        self.onComplete = onComplete
        self._selectedType = State(initialValue: preselectedType ?? .textToText)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Conversion type picker
                Section {
                    Picker("Conversion Type", selection: $selectedType) {
                        ForEach(ConversionType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.inputIcon)
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                Image(systemName: type.outputIcon)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedType) { oldValue, newValue in
                        // Clear input when switching types
                        inputText = ""
                        selectedFileURL = nil
                    }
                } header: {
                    Text("Select Type")
                }

                // Input section
                Section {
                    if selectedType.requiresFile {
                        fileInputSection
                    } else {
                        textInputSection
                    }
                } header: {
                    Text("Input")
                }

                // Progress status
                if isConverting && !progressStatus.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text(progressStatus)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatElapsedTime(elapsedTime))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if progressPercentage > 0 {
                                ProgressView(value: progressPercentage, total: 1.0)
                                    .progressViewStyle(.linear)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Progress")
                    }
                }

                // Streaming output (if applicable)
                if isConverting && (selectedType == .textToText || selectedType == .fileToText) && !streamingOutput.isEmpty {
                    Section {
                        MarkdownText(content: streamingOutput, textColor: .primary)
                            .textSelection(.enabled)
                    } header: {
                        Text(selectedType == .fileToText ? "Summary" : "Output")
                    }
                }
            }
            .navigationTitle("New Conversion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isConverting {
                            // Stop the conversion
                            isConverting = false
                            statusTimer?.invalidate()
                            print("🛑 User cancelled conversion")
                        }
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isConverting ? "Converting..." : "Convert") {
                        performConversion()
                    }
                    .disabled(!canConvert || isConverting)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: allowedFileTypes,
                allowsMultipleSelection: false
            ) { (result: Swift.Result<[URL], Error>) in
                handleFileSelection(result)
            }
        }
    }

    @ViewBuilder
    private var textInputSection: some View {
        TextField("Enter text...", text: $inputText, axis: .vertical)
            .lineLimit(5...10)
            .disabled(isConverting)
    }

    @ViewBuilder
    private var fileInputSection: some View {
        if let fileURL = selectedFileURL {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileURL.lastPathComponent)
                        .font(.body)
                    Text(fileURL.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: { selectedFileURL = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        } else {
            Button(action: { showFilePicker = true }) {
                HStack {
                    Image(systemName: "doc.badge.plus")
                    Text("Choose File")
                }
            }
            .disabled(isConverting)
        }
    }

    // MARK: - Computed Properties

    private var canConvert: Bool {
        if selectedType.requiresFile {
            return selectedFileURL != nil
        } else {
            return !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var allowedFileTypes: [UTType] {
        switch selectedType {
        case .audioToText:
            return [.audio]
        case .videoToText:
            return [.movie]
        case .fileToText:
            return [.pdf, .text, .plainText]
        default:
            return [.data]
        }
    }

    // MARK: - Actions

    private func handleFileSelection(_ result: Swift.Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                selectedFileURL = url
            }
        case .failure(let error):
            print("❌ File selection failed: \(error)")
        }
    }

    private func performConversion() {
        isConverting = true
        elapsedTime = 0
        progressStatus = "🔄 Starting conversion..."
        progressPercentage = 0

        // Start timer
        let startTime = Date()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.elapsedTime = Date().timeIntervalSince(startTime)
        }

        Task { @MainActor in
            do {
                // Use streaming for text-to-text and file-to-text
                if selectedType == .textToText || selectedType == .fileToText {
                    streamingOutput = ""

                    for try await event in conversionService.convertStream(
                        type: selectedType,
                        inputText: inputText.isEmpty ? nil : inputText,
                        inputFileURL: selectedFileURL
                    ) {
                        switch event {
                        case .conversionCreated(let conversion):
                            currentConversion = conversion
                            progressStatus = "📄 Processing file..."
                            progressPercentage = 0.3

                        case .textChunk(let chunk):
                            streamingOutput += chunk
                            progressStatus = "✨ Generating..."
                            progressPercentage = 0.5

                        case .completed(_, let chatId):
                            progressStatus = "✅ Complete!"
                            progressPercentage = 1.0
                            statusTimer?.invalidate()
                            isConverting = false
                            dismiss()
                            if let chatId = chatId {
                                onComplete(chatId)
                            }

                        case .progress:
                            break
                        }
                    }
                } else {
                    // Non-streaming conversion
                    progressStatus = "🔄 Converting..."
                    progressPercentage = 0.5

                    let (_, chatId) = try await conversionService.convert(
                        type: selectedType,
                        inputText: inputText.isEmpty ? nil : inputText,
                        inputFileURL: selectedFileURL
                    )

                    progressStatus = "✅ Complete!"
                    progressPercentage = 1.0
                    statusTimer?.invalidate()

                    isConverting = false
                    dismiss()
                    if let chatId = chatId {
                        onComplete(chatId)
                    }
                }
            } catch {
                print("❌ Conversion failed: \(error)")
                progressStatus = "❌ Failed: \(error.localizedDescription)"
                statusTimer?.invalidate()
                isConverting = false
            }
        }
    }

    private func formatElapsedTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(secs)s"
        }
    }

    private func getModelName(for type: ConversionType) -> String {
        switch type {
        case .textToText, .fileToText:
            return "Qwen 3.5 2B"
        case .textToAudio:
            return "Kokoro TTS"
        case .audioToText, .videoToText:
            return "Whisper"
        }
    }
}

#Preview {
    ConversionInputView { _ in }
}
