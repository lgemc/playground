import SwiftUI

/// File detail view - shows information about a single file
struct FileDetailView: View {
    let file: File
    let onFileUpdated: () -> Void

    @State private var showingDeleteAlert = false
    @State private var isExtracting = false
    @State private var extractionError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("File Information") {
                HStack {
                    Image(systemName: file.iconName)
                        .foregroundColor(.orange)
                        .font(.largeTitle)
                        .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.name)
                            .font(.headline)

                        Text(file.formattedSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)

                HStack {
                    Text("Path")
                    Spacer()
                    Text(file.path)
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }

                if let mimeType = file.mimeType {
                    HStack {
                        Text("MIME Type")
                        Spacer()
                        Text(mimeType)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }

                HStack {
                    Text("Extension")
                    Spacer()
                    Text(file.fileExtension.isEmpty ? "None" : file.fileExtension)
                        .foregroundColor(.secondary)
                }
            }

            // Extracted text section
            if let extractedText = file.extractedText {
                Section("Extracted Text") {
                    Text(extractedText)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.vertical, 8)
                }
            } else if FileExtractionService.shared.isSupported(fileExtension: file.fileExtension) {
                Section("Text Extraction") {
                    if isExtracting {
                        HStack {
                            ProgressView()
                            Text("Extracting text...")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: extractText) {
                            HStack {
                                Image(systemName: "text.magnifyingglass")
                                Text("Extract Text from File")
                            }
                        }

                        if let error = extractionError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }

            // Metadata
            Section("Metadata") {
                HStack {
                    Text("Created")
                    Spacer()
                    Text(formatDate(file.createdAt))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Updated")
                    Spacer()
                    Text(formatDate(file.updatedAt))
                        .foregroundColor(.secondary)
                }
            }

            // Actions
            Section {
                Button(role: .destructive, action: { showingDeleteAlert = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete File")
                    }
                }
            }
        }
        .navigationTitle("File Details")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete File", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteFile()
            }
        } message: {
            Text("Are you sure you want to delete '\(file.name)'? This action cannot be undone.")
        }
    }

    private func extractText() {
        isExtracting = true
        extractionError = nil

        Task {
            do {
                try await FileExtractionService.shared.extractAndUpdateFile(fileId: file.id)
                await MainActor.run {
                    isExtracting = false
                    onFileUpdated()
                }
            } catch {
                await MainActor.run {
                    isExtracting = false
                    extractionError = "Failed to extract text: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteFile() {
        let result = FileStorage.shared.deleteFile(id: file.id)
        if result.isOk {
            dismiss()
        } else if let error = result.error {
            print("❌ Failed to delete file: \(error)")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        FileDetailView(
            file: File(
                name: "example.txt",
                path: "/path/to/example.txt",
                mimeType: "text/plain",
                sizeBytes: 1024,
                extractedText: "This is some example text content."
            ),
            onFileUpdated: {}
        )
    }
}
