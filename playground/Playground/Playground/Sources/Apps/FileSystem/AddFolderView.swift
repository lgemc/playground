import SwiftUI

/// Add folder view - allows picking an iOS folder and adding all its files to the system
struct AddFolderView: View {
    @Environment(\.dismiss) private var dismiss
    let onFoldersAdded: () -> Void

    @State private var selectedFolderPath: String = ""
    @State private var showFolderPicker = false
    @State private var isAdding = false
    @State private var addRecursively = false
    @State private var autoExtractText = true

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var fileCount: Int?
    @State private var totalSize: Int64?

    var body: some View {
        Form {
            Section("Folder Selection") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if selectedFolderPath.isEmpty {
                            Text("No folder selected")
                                .foregroundColor(.secondary)
                        } else {
                            Text(URL(fileURLWithPath: selectedFolderPath).lastPathComponent)
                                .font(.headline)

                            Text(selectedFolderPath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    Button("Browse") {
                        showFolderPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }

            // Folder info preview
            if !selectedFolderPath.isEmpty {
                Section("Folder Preview") {
                    if let count = fileCount {
                        HStack {
                            Text("Files")
                            Spacer()
                            Text("\(count)")
                                .foregroundColor(.secondary)
                        }
                    }

                    if let size = totalSize {
                        HStack {
                            Text("Total Size")
                            Spacer()
                            Text(formatBytes(size))
                                .foregroundColor(.secondary)
                        }
                    }

                    if fileCount == nil && totalSize == nil {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Analyzing folder...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("Options") {
                Toggle("Include subfolders", isOn: $addRecursively)
                    .tint(.orange)

                Toggle("Auto-extract text if supported", isOn: $autoExtractText)
                    .tint(.orange)

                Text("If enabled, text will be automatically extracted from supported file types (txt, md, json, etc.)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Add Folder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add") {
                    addFolder()
                }
                .disabled(selectedFolderPath.isEmpty || isAdding)
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            NavigationStack {
                FolderPickerView { selectedURL in
                    selectedFolderPath = selectedURL.path
                    analyzeFolderContents()
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func analyzeFolderContents() {
        fileCount = nil
        totalSize = nil

        Task {
            do {
                var count = 0
                var bytes: Int64 = 0

                let folderURL = URL(fileURLWithPath: selectedFolderPath)

                if addRecursively {
                    // Recursive enumeration
                    if let enumerator = FileManager.default.enumerator(
                        at: folderURL,
                        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) {
                        let urls = enumerator.allObjects.compactMap { $0 as? URL }
                        for fileURL in urls {
                            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                            if resourceValues.isRegularFile == true {
                                count += 1
                                bytes += Int64(resourceValues.fileSize ?? 0)
                            }
                        }
                    }
                } else {
                    // Single directory only
                    let contents = try FileManager.default.contentsOfDirectory(
                        at: folderURL,
                        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    )

                    for fileURL in contents {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                        if resourceValues.isRegularFile == true {
                            count += 1
                            bytes += Int64(resourceValues.fileSize ?? 0)
                        }
                    }
                }

                await MainActor.run {
                    fileCount = count
                    totalSize = bytes
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to analyze folder: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    private func addFolder() {
        guard !selectedFolderPath.isEmpty else { return }

        isAdding = true

        Task {
            do {
                let folderURL = URL(fileURLWithPath: selectedFolderPath)
                var addedCount = 0

                if addRecursively {
                    // Recursive enumeration
                    if let enumerator = FileManager.default.enumerator(
                        at: folderURL,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) {
                        let urls = enumerator.allObjects.compactMap { $0 as? URL }
                        for fileURL in urls {
                            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                            if resourceValues.isRegularFile == true {
                                try await addSingleFile(fileURL)
                                addedCount += 1
                            }
                        }
                    }
                } else {
                    // Single directory only
                    let contents = try FileManager.default.contentsOfDirectory(
                        at: folderURL,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    )

                    for fileURL in contents {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                        if resourceValues.isRegularFile == true {
                            try await addSingleFile(fileURL)
                            addedCount += 1
                        }
                    }
                }

                await MainActor.run {
                    isAdding = false
                    onFoldersAdded()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to add folder: \(error.localizedDescription)"
                    showError = true
                    isAdding = false
                }
            }
        }
    }

    private func addSingleFile(_ fileURL: URL) async throws {
        // Get file info from original location
        let fileInfo = try FileExtractionService.shared.getFileInfo(at: fileURL.path)

        // Create app's files directory structure
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filesDirectory = documentsURL.appendingPathComponent("Files")

        // Create the Files directory if it doesn't exist
        try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)

        // Create destination URL with unique name if file already exists
        var destinationURL = filesDirectory.appendingPathComponent(fileInfo.name)
        var counter = 1
        while FileManager.default.fileExists(atPath: destinationURL.path) {
            let nameWithoutExt = (fileInfo.name as NSString).deletingPathExtension
            let ext = (fileInfo.name as NSString).pathExtension
            let uniqueName = ext.isEmpty ? "\(nameWithoutExt)_\(counter)" : "\(nameWithoutExt)_\(counter).\(ext)"
            destinationURL = filesDirectory.appendingPathComponent(uniqueName)
            counter += 1
        }

        // Copy file to app's storage
        try FileManager.default.copyItem(at: fileURL, to: destinationURL)

        print("✅ Copied file to: \(destinationURL.path)")

        // Detect MIME type
        let mimeType = detectMimeType(fileExtension: fileInfo.fileExtension)

        // Create file in storage with the new internal path (imported files go to root folder)
        let fileResult = FileStorage.shared.createFile(
            name: destinationURL.lastPathComponent,
            path: destinationURL.path,
            folderPath: "",
            mimeType: mimeType,
            sizeBytes: fileInfo.size
        )
        let file = try fileResult.get()

        // Extract text if enabled and supported
        if autoExtractText && FileExtractionService.shared.isSupported(fileExtension: fileInfo.fileExtension) {
            try await FileExtractionService.shared.extractAndUpdateFile(fileId: file.id)
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

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    NavigationStack {
        AddFolderView(onFoldersAdded: {})
    }
}
