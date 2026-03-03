import SwiftUI

/// File detail view - shows information about a single file
struct FileDetailView: View {
    let file: File
    let onFileUpdated: () -> Void

    @State private var showingDeleteAlert = false
    @State private var isExtracting = false
    @State private var extractionError: String?
    @State private var availableGenerators: [DerivativeGenerator] = []
    @State private var generatingDerivatives: Set<String> = []
    @State private var derivativeErrors: [String: String] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Show preview for supported file types
            viewerSection

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

            // Derivatives section
            derivativesSection

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
        .onAppear(perform: loadAvailableGenerators)
    }

    // MARK: - Viewer Section

    @ViewBuilder
    private var viewerSection: some View {
        let ext = file.fileExtension.lowercased()

        if ext == "pdf" {
            Section {
                NavigationLink(destination: PDFViewerView(file: file)) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.orange)
                        Text("View PDF")
                    }
                }
            }
        } else if ["mp4", "mov", "avi", "m4v"].contains(ext) {
            Section {
                NavigationLink(destination: VideoPlayerView(file: file)) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.orange)
                        Text("Play Video")
                    }
                }
            }
        }
    }

    // MARK: - Derivatives Section

    @ViewBuilder
    private var derivativesSection: some View {
        if !availableGenerators.isEmpty {
            Section("Derivatives") {
                ForEach(availableGenerators, id: \.type) { generator in
                    derivativeRow(for: generator)
                }
            }
        }
    }

    @ViewBuilder
    private func derivativeRow(for generator: DerivativeGenerator) -> some View {
        let isGenerating = generatingDerivatives.contains(generator.type)
        let error = derivativeErrors[generator.type]

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: generator.icon)
                    .foregroundColor(.blue)

                Text(generator.displayName)

                Spacer()

                if isGenerating {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: {
                        generateDerivative(generator: generator)
                    }) {
                        Text("Generate")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
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

    // MARK: - Derivatives

    private func loadAvailableGenerators() {
        // Convert File to FileItem
        let fileItem = FileItem(
            id: file.id,
            path: file.path,
            name: file.name,
            mimeType: file.mimeType,
            size: file.sizeBytes,
            createdAt: file.createdAt,
            updatedAt: file.updatedAt
        )

        // Get available generators for this file
        availableGenerators = DerivativeService.shared.getAvailableGenerators(for: fileItem)
    }

    private func generateDerivative(generator: DerivativeGenerator) {
        generatingDerivatives.insert(generator.type)
        derivativeErrors.removeValue(forKey: generator.type)

        // Request derivative generation through the queue system
        DerivativeService.shared.requestDerivative(
            fileId: file.id,
            filePath: file.path,
            type: generator.type
        )

        // Simulate completion after a delay (in reality, listen to AppBus events)
        Task {
            // Wait a bit then remove from generating set
            try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

            await MainActor.run {
                generatingDerivatives.remove(generator.type)
            }
        }
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
