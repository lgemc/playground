import SwiftUI

/// Add file view - form for adding new files to the system
struct AddFileView: View {
    @Environment(\.dismiss) private var dismiss
    let onFileAdded: () -> Void

    @State private var filePath: String = ""
    @State private var customName: String = ""
    @State private var autoExtractText: Bool = true

    @State private var isAdding = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showFolderPicker = false

    var body: some View {
        Form {
            Section("File Path") {
                HStack {
                    TextField("Enter file path", text: $filePath)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))

                    Button(action: { showFolderPicker = true }) {
                        Image(systemName: "folder.badge.plus")
                            .foregroundColor(.blue)
                    }
                }

                Text("Enter the full path or browse for a folder")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Options") {
                TextField("Custom name (optional)", text: $customName)
                    .autocapitalization(.none)

                Toggle("Auto-extract text if supported", isOn: $autoExtractText)
                    .tint(.orange)

                Text("If enabled, text will be automatically extracted from supported file types (txt, md, json, etc.)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // File info preview (if path looks valid)
            if !filePath.isEmpty && FileManager.default.fileExists(atPath: filePath) {
                Section("File Preview") {
                    if let fileInfo = try? FileExtractionService.shared.getFileInfo(at: filePath) {
                        HStack {
                            Text("Name")
                            Spacer()
                            Text(fileInfo.name)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Size")
                            Spacer()
                            Text(fileInfo.formattedSize)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Extension")
                            Spacer()
                            Text(fileInfo.fileExtension.isEmpty ? "None" : fileInfo.fileExtension)
                                .foregroundColor(.secondary)
                        }

                        if FileExtractionService.shared.isSupported(fileExtension: fileInfo.fileExtension) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Text extraction supported")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Add File")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add") {
                    addFile()
                }
                .disabled(filePath.isEmpty || isAdding)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showFolderPicker) {
            NavigationStack {
                FolderPickerView { selectedURL in
                    filePath = selectedURL.path
                }
            }
        }
    }

    private func addFile() {
        guard !filePath.isEmpty else { return }

        isAdding = true

        Task {
            do {
                // Get file info
                let fileInfo = try FileExtractionService.shared.getFileInfo(at: filePath)

                // Determine file name
                let fileName = customName.isEmpty ? fileInfo.name : customName

                // Detect MIME type
                let mimeType = detectMimeType(fileExtension: fileInfo.fileExtension)

                // Create file in storage
                let fileResult = FileStorage.shared.createFile(
                    name: fileName,
                    path: filePath,
                    mimeType: mimeType,
                    sizeBytes: fileInfo.size
                )
                let file = try fileResult.get()

                // Extract text if enabled and supported
                if autoExtractText && FileExtractionService.shared.isSupported(fileExtension: fileInfo.fileExtension) {
                    try await FileExtractionService.shared.extractAndUpdateFile(fileId: file.id)
                }

                await MainActor.run {
                    isAdding = false
                    onFileAdded()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to add file: \(error.localizedDescription)"
                    showError = true
                    isAdding = false
                }
            }
        }
    }

    private func detectMimeType(fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "txt":
            return "text/plain"
        case "md", "markdown":
            return "text/markdown"
        case "json":
            return "application/json"
        case "xml":
            return "application/xml"
        case "html", "htm":
            return "text/html"
        case "css":
            return "text/css"
        case "js":
            return "application/javascript"
        case "pdf":
            return "application/pdf"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "mp3":
            return "audio/mpeg"
        case "mp4":
            return "video/mp4"
        case "zip":
            return "application/zip"
        default:
            return "application/octet-stream"
        }
    }
}

#Preview {
    NavigationStack {
        AddFileView(onFileAdded: {})
    }
}
