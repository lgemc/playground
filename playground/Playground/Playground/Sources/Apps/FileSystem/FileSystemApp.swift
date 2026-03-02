import SwiftUI
import Combine

/// File System sub-app - Document management and text extraction
class FileSystemApp: SubApp {
    let id = "fileSystem"
    let name = "Files"
    let iconName = "doc.fill"
    let themeColor = Color.orange

    let supportsSearch = true
    let supportsSharing = true
    let acceptedShareTypes = ["text/plain", "text/*", "application/json", "application/xml"]

    // ObservableObject conformance
    let objectWillChange = ObservableObjectPublisher()

    init() {}

    func buildView() -> AnyView {
        AnyView(FileListView())
    }

    // MARK: - Lifecycle

    func onInit() async {
        print("✅ File System app initialized")
    }

    // MARK: - Search

    func search(query: String) async -> [SearchResult] {
        let filesResult = FileStorage.shared.searchFiles(query: query, limit: 50)
        guard let files = filesResult.value else {
            print("❌ File search failed: \(filesResult.error?.localizedDescription ?? "unknown error")")
            return []
        }

        return files.map { file in
            let preview: String?
            if let extractedText = file.extractedText {
                let text = extractedText.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                preview = text.count > 100 ? String(text.prefix(100)) + "..." : text
            } else {
                preview = nil
            }

            return SearchResult(
                id: file.id,
                type: .file,
                appId: id,
                title: file.name,
                subtitle: file.formattedSize,
                preview: preview,
                navigationData: ["fileId": file.id],
                timestamp: file.createdAt
            )
        }
    }

    func navigateToSearchResult(result: SearchResult) async {
        // Navigation will be handled by the UI layer
    }

    // MARK: - Sharing

    func onReceiveShare(content: SharedContent) async {
        do {
            // Create a temporary file from shared content
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "shared_\(Date().timeIntervalSince1970).txt"
            let fileURL = tempDir.appendingPathComponent(fileName)

            try content.data.write(to: fileURL)

            // Get file info
            let fileInfo = try FileExtractionService.shared.getFileInfo(at: fileURL.path)

            // Create file in storage
            let fileResult = FileStorage.shared.createFile(
                name: fileName,
                path: fileURL.path,
                mimeType: content.type,
                sizeBytes: fileInfo.size
            )
            let file = try fileResult.get()

            // Extract text if supported
            if FileExtractionService.shared.isSupported(mimeType: content.type) {
                try await FileExtractionService.shared.extractAndUpdateFile(fileId: file.id)
            }

            print("✅ Received shared file: \(fileName)")
        } catch {
            print("❌ Failed to receive shared content: \(error)")
        }
    }
}
