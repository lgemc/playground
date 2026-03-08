import SwiftUI

/// File detail view - shows information about a single file
struct FileDetailView: View {
    let file: File
    let onFileUpdated: () -> Void

    @State private var showingDeleteAlert = false
    @State private var isExtracting = false
    @State private var extractionError: String?
    @State private var availableGenerators: [DerivativeGenerator] = []
    @State private var derivatives: [Derivative] = []
    @State private var derivativeToDelete: Derivative?
    @State private var showingDeleteDerivativeAlert = false
    @State private var refreshTimer: Timer?
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
        .alert("Delete Derivative", isPresented: $showingDeleteDerivativeAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let derivative = derivativeToDelete {
                    deleteDerivative(derivative)
                }
            }
        } message: {
            Text("Are you sure you want to delete this derivative? This action cannot be undone.")
        }
        .onAppear {
            loadAvailableGenerators()
            loadDerivatives()
            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
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
        } else if ["md", "markdown"].contains(ext) {
            Section {
                NavigationLink(destination: MarkdownViewerView(file: file)) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.orange)
                        Text("View Markdown")
                    }
                }
            }
        } else if ext == "json" && isTranscriptFile() {
            Section {
                NavigationLink(destination: transcriptViewer()) {
                    HStack {
                        Image(systemName: "text.bubble.fill")
                            .foregroundColor(.orange)
                        Text("View Transcript")
                    }
                }
            }
        }
    }

    // MARK: - Transcript Support

    private func isTranscriptFile() -> Bool {
        // Check if file name suggests it's a transcript
        let name = file.name.lowercased()
        return name.contains("transcript") ||
               name.contains("_transcript.json") ||
               name.hasSuffix("-transcript.json")
    }

    @ViewBuilder
    private func transcriptViewer() -> some View {
        if let transcript = loadTranscript() {
            TranscriptViewerView(
                transcript: transcript,
                fileName: file.name
            )
        } else {
            ContentUnavailableView(
                "Invalid Transcript",
                systemImage: "exclamationmark.triangle",
                description: Text("Could not load transcript from this file")
            )
        }
    }

    private func loadTranscript() -> Transcript? {
        let absolutePath = file.absolutePath

        guard FileManager.default.fileExists(atPath: absolutePath) else {
            print("❌ Transcript file not found: \(absolutePath)")
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: absolutePath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let transcript = try decoder.decode(Transcript.self, from: data)
            return transcript
        } catch {
            print("❌ Failed to load transcript: \(error)")
            return nil
        }
    }

    // MARK: - Derivatives Section

    @ViewBuilder
    private var derivativesSection: some View {
        if !availableGenerators.isEmpty || !derivatives.isEmpty {
            Section("Derivatives") {
                // Show available generators
                ForEach(availableGenerators, id: \.type) { generator in
                    availableGeneratorRow(for: generator)
                }

                // Show existing derivatives
                if !derivatives.isEmpty {
                    ForEach(derivatives) { derivative in
                        existingDerivativeRow(for: derivative)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func availableGeneratorRow(for generator: DerivativeGenerator) -> some View {
        // Check if there's already a derivative for this type
        let existingDerivative = derivatives.first(where: { $0.type == generator.type })

        // Only show generate button if no derivative exists or if previous one failed
        if existingDerivative == nil || existingDerivative?.status == .failed {
            HStack {
                Image(systemName: generator.icon)
                    .foregroundColor(.blue)

                Text(generator.displayName)

                Spacer()

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
    }

    @ViewBuilder
    private func existingDerivativeRow(for derivative: Derivative) -> some View {
        let content = HStack {
            Image(systemName: derivative.icon)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(derivative.displayName)
                    .font(.body)

                if derivative.status == .pending {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Generating...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if derivative.status == .complete {
                    Text("Complete")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if derivative.status == .failed {
                    Text("Failed: \(derivative.errorMessage ?? "Unknown error")")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            // Status icon
            Image(systemName: derivative.statusIcon)
                .foregroundColor(statusColorFor(derivative.status))

            // Delete button (only for non-pending derivatives)
            if derivative.status != .pending {
                Button(action: {
                    derivativeToDelete = derivative
                    showingDeleteDerivativeAlert = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }

        // Make transcript derivatives clickable when complete
        if derivative.type == "transcript" && derivative.status == .complete, let outputPath = derivative.outputPath {
            NavigationLink(destination: transcriptViewerForDerivative(outputPath: outputPath)) {
                content
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private func transcriptViewerForDerivative(outputPath: String) -> some View {
        if let transcript = loadTranscriptFromPath(outputPath) {
            TranscriptViewerView(
                transcript: transcript,
                fileName: file.name
            )
        } else {
            ContentUnavailableView(
                "Invalid Transcript",
                systemImage: "exclamationmark.triangle",
                description: Text("Could not load transcript from derivative")
            )
        }
    }

    private func loadTranscriptFromPath(_ path: String) -> Transcript? {
        // Check if path is absolute or relative
        let absolutePath: String
        if path.hasPrefix("/") {
            absolutePath = path
        } else {
            // Path is relative to Documents/data/file_system/storage/
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                print("❌ Could not access documents directory")
                return nil
            }

            let storageURL = documentsURL
                .appendingPathComponent("data")
                .appendingPathComponent("file_system")
                .appendingPathComponent("storage")
                .appendingPathComponent(path)

            absolutePath = storageURL.path
        }

        guard FileManager.default.fileExists(atPath: absolutePath) else {
            print("❌ Transcript file not found: \(absolutePath)")
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: absolutePath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let transcript = try decoder.decode(Transcript.self, from: data)
            return transcript
        } catch {
            print("❌ Failed to load transcript: \(error)")
            return nil
        }
    }

    private func statusColorFor(_ status: DerivativeStatus) -> Color {
        switch status {
        case .pending:
            return .orange
        case .complete:
            return .green
        case .failed:
            return .red
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
        // Use absolutePath to resolve relative paths
        let fileItem = FileItem(
            id: file.id,
            path: file.absolutePath,
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
        // Request derivative generation through the queue system
        // Use absolutePath to resolve relative paths
        print("🎬 FileDetailView - Requesting derivative:")
        print("   Generator: \(generator.displayName)")
        print("   File.path: \(file.path)")
        print("   File.relativePath: \(file.relativePath ?? "nil")")
        print("   File.folderPath: \(file.folderPath ?? "nil")")
        print("   File.absolutePath: \(file.absolutePath)")
        print("   File exists at absolutePath: \(FileManager.default.fileExists(atPath: file.absolutePath))")

        DerivativeService.shared.requestDerivative(
            fileId: file.id,
            filePath: file.absolutePath,
            type: generator.type
        )

        // Reload derivatives to show the new pending derivative
        loadDerivatives()
    }

    private func loadDerivatives() {
        let result = DerivativeStorage.shared.getDerivatives(forFileId: file.id)
        if result.isOk {
            derivatives = result.value ?? []
        } else if let error = result.error {
            print("❌ Failed to load derivatives: \(error)")
        }
    }

    private func deleteDerivative(_ derivative: Derivative) {
        let result = DerivativeStorage.shared.deleteDerivative(id: derivative.id)
        if result.isOk {
            loadDerivatives()
        } else if let error = result.error {
            print("❌ Failed to delete derivative: \(error)")
        }
    }

    private func startRefreshTimer() {
        // Poll for derivative updates every 2 seconds if there are pending derivatives
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [self] _ in
            // Only refresh if there are pending derivatives
            if derivatives.contains(where: { $0.status == .pending }) {
                loadDerivatives()
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
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
