import SwiftUI

/// Markdown Viewer component for displaying Markdown files
struct MarkdownViewerView: View {
    let file: File

    @State private var markdownContent: String?
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let error = loadError {
                errorView(message: error)
            } else if let content = markdownContent {
                ScrollView {
                    MarkdownText(content: content, textColor: .primary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                loadingView
            }
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadMarkdown)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading Markdown...")
                .foregroundColor(.secondary)
        }
    }

    private func errorView(message: String) -> some View {
        ContentUnavailableView(
            "Cannot Display Markdown",
            systemImage: "doc.text.fill.badge.exclamationmark",
            description: Text(message)
        )
    }

    private func loadMarkdown() {
        let absolutePath = file.absolutePath
        guard FileManager.default.fileExists(atPath: absolutePath) else {
            loadError = "File not found at path: \(absolutePath)"
            return
        }

        do {
            let content = try String(contentsOfFile: absolutePath, encoding: .utf8)
            markdownContent = content
        } catch {
            loadError = "Failed to load markdown file: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        MarkdownViewerView(
            file: File(
                name: "example.md",
                path: "/path/to/example.md",
                mimeType: "text/markdown",
                sizeBytes: 1024
            )
        )
    }
}
