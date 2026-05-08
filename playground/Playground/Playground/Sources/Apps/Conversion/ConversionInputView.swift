import SwiftUI
import UniformTypeIdentifiers

/// Input view for creating a new conversion
struct ConversionInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var conversions: [Conversion]

    @State private var selectedType: ConversionType = .textToText
    @State private var inputText: String = ""
    @State private var selectedFileURL: URL? = nil
    @State private var showFilePicker = false
    @State private var isConverting = false
    @State private var streamingOutput = ""
    @State private var currentConversion: Conversion? = nil

    private let conversionService = ConversionService.shared

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

                // Streaming output (if applicable)
                if isConverting && selectedType == .textToText && !streamingOutput.isEmpty {
                    Section {
                        Text(streamingOutput)
                            .font(.body)
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    } header: {
                        HStack {
                            Text("Output")
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            }
            .navigationTitle("New Conversion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isConverting)
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
        case .imageToText:
            return [.image]
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

        Task { @MainActor in
            do {
                // Use streaming for text-to-text, non-streaming for others
                if selectedType == .textToText {
                    streamingOutput = ""

                    for try await event in conversionService.convertStream(
                        type: selectedType,
                        inputText: inputText.isEmpty ? nil : inputText,
                        inputFileURL: selectedFileURL
                    ) {
                        switch event {
                        case .conversionCreated(let conversion):
                            currentConversion = conversion
                            conversions.insert(conversion, at: 0)

                        case .textChunk(let chunk):
                            streamingOutput += chunk

                        case .completed(let fullText):
                            // Update the conversion in the list
                            if let index = conversions.firstIndex(where: { $0.id == currentConversion?.id }) {
                                var updated = conversions[index]
                                updated.outputText = fullText
                                conversions[index] = updated
                            }

                            isConverting = false
                            dismiss()

                        case .progress:
                            break
                        }
                    }
                } else {
                    // Non-streaming conversion
                    let conversion = try await conversionService.convert(
                        type: selectedType,
                        inputText: inputText.isEmpty ? nil : inputText,
                        inputFileURL: selectedFileURL
                    )

                    conversions.insert(conversion, at: 0)
                    isConverting = false
                    dismiss()
                }
            } catch {
                print("❌ Conversion failed: \(error)")
                isConverting = false
                // TODO: Show error alert
            }
        }
    }
}

#Preview {
    ConversionInputView(conversions: .constant([]))
}
