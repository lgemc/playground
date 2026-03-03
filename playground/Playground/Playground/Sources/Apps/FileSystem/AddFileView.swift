import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Add file view - form for adding new files to the system
struct AddFileView: View {
    @Environment(\.dismiss) private var dismiss
    let folderPath: String
    let onFileAdded: () -> Void

    @State private var selectedFileURL: URL?
    @State private var customName: String = ""
    @State private var autoExtractText: Bool = true

    @State private var isAdding = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showFilePicker = false

    var body: some View {
        Form {
            Section("File Selection") {
                if let url = selectedFileURL {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: fileIcon(for: url))
                                .font(.title)
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .font(.headline)

                                Text(url.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        Button("Change File") {
                            showFilePicker = true
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)
                    }
                    .padding(.vertical, 4)
                } else {
                    Button(action: { showFilePicker = true }) {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                                .font(.title2)

                            Text("Select File")
                                .font(.headline)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(.blue)
                        .padding(.vertical, 8)
                    }
                }
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

            // File info preview
            if let url = selectedFileURL,
               let fileInfo = try? FileExtractionService.shared.getFileInfo(at: url.path) {
                Section("File Preview") {
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
                .disabled(selectedFileURL == nil || isAdding)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showFilePicker) {
            FileDocumentPicker(onFileSelected: { url in
                selectedFileURL = url
            })
        }
    }

    private func fileIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.text.fill"
        case "mp4", "mov", "avi", "mkv": return "video.fill"
        case "mp3", "m4a", "wav": return "music.note"
        case "jpg", "jpeg", "png", "gif": return "photo.fill"
        case "txt", "md": return "doc.text"
        case "zip", "rar": return "doc.zipper"
        default: return "doc.fill"
        }
    }

    private func addFile() {
        guard let fileURL = selectedFileURL else { return }

        isAdding = true

        Task {
            do {
                // Start accessing security-scoped resource
                let startedAccess = fileURL.startAccessingSecurityScopedResource()
                defer {
                    if startedAccess {
                        fileURL.stopAccessingSecurityScopedResource()
                    }
                }

                // Get file info from original location
                let fileInfo = try FileExtractionService.shared.getFileInfo(at: fileURL.path)

                // Determine file name
                let fileName = customName.isEmpty ? fileInfo.name : customName

                // Create app's files directory structure
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let filesDirectory = documentsURL.appendingPathComponent("Files")

                // Create the Files directory if it doesn't exist
                try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)

                // Create folder path within Files directory if needed
                let destinationFolder: URL
                if folderPath.isEmpty {
                    destinationFolder = filesDirectory
                } else {
                    destinationFolder = filesDirectory.appendingPathComponent(folderPath)
                    try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                }

                // Create destination URL with unique name if file already exists
                var destinationURL = destinationFolder.appendingPathComponent(fileName)
                var counter = 1
                while FileManager.default.fileExists(atPath: destinationURL.path) {
                    let nameWithoutExt = (fileName as NSString).deletingPathExtension
                    let ext = (fileName as NSString).pathExtension
                    let uniqueName = ext.isEmpty ? "\(nameWithoutExt)_\(counter)" : "\(nameWithoutExt)_\(counter).\(ext)"
                    destinationURL = destinationFolder.appendingPathComponent(uniqueName)
                    counter += 1
                }

                // Copy file to app's storage
                try FileManager.default.copyItem(at: fileURL, to: destinationURL)

                print("✅ Copied file to: \(destinationURL.path)")

                // Detect MIME type
                let mimeType = detectMimeType(fileExtension: fileInfo.fileExtension)

                // Create file in storage with the new internal path
                let fileResult = FileStorage.shared.createFile(
                    name: destinationURL.lastPathComponent,
                    path: destinationURL.path,
                    folderPath: folderPath,
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

// MARK: - File Document Picker

struct FileDocumentPicker: UIViewControllerRepresentable {
    let onFileSelected: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Allow all file types
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFileSelected: onFileSelected)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFileSelected: (URL) -> Void

        init(onFileSelected: @escaping (URL) -> Void) {
            self.onFileSelected = onFileSelected
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }

            // Start accessing security-scoped resource
            let startedAccess = url.startAccessingSecurityScopedResource()

            // Create security-scoped bookmark for persistent access
            do {
                let bookmarkData = try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )

                // Store bookmark in UserDefaults for persistent access
                let bookmarkKey = "file_bookmark_\(url.path.hash)"
                UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)

                print("✅ Created bookmark for file: \(url.lastPathComponent)")
            } catch {
                print("⚠️ Failed to create bookmark: \(error.localizedDescription)")
            }

            // Call the completion handler
            onFileSelected(url)

            // Stop accessing when done
            if startedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // User cancelled, do nothing
        }
    }
}

#Preview {
    NavigationStack {
        AddFileView(folderPath: "", onFileAdded: {})
    }
}
