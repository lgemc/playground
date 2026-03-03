import SwiftUI
import PDFKit

/// PDF Viewer component for displaying PDF files
struct PDFViewerView: View {
    let file: File

    @State private var pdfDocument: PDFDocument?
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 0
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let error = loadError {
                errorView(message: error)
            } else if let pdfDocument = pdfDocument {
                PDFKitView(document: pdfDocument, currentPage: $currentPage)
                    .edgesIgnoringSafeArea(.all)

                // Page navigation toolbar
                pageNavigationToolbar
            } else {
                loadingView
            }
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadPDF)
    }

    private var pageNavigationToolbar: some View {
        HStack {
            Button(action: previousPage) {
                Image(systemName: "chevron.left")
                    .font(.title2)
            }
            .disabled(currentPage <= 1)

            Spacer()

            Text("Page \(currentPage) of \(totalPages)")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: nextPage) {
                Image(systemName: "chevron.right")
                    .font(.title2)
            }
            .disabled(currentPage >= totalPages)
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(radius: 2)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading PDF...")
                .foregroundColor(.secondary)
        }
    }

    private func errorView(message: String) -> some View {
        ContentUnavailableView(
            "Cannot Display PDF",
            systemImage: "doc.fill.badge.exclamationmark",
            description: Text(message)
        )
    }

    private func loadPDF() {
        let absolutePath = file.absolutePath
        guard FileManager.default.fileExists(atPath: absolutePath) else {
            loadError = "File not found at path: \(absolutePath)"
            return
        }

        let url = URL(fileURLWithPath: absolutePath)

        guard let document = PDFDocument(url: url) else {
            loadError = "Failed to load PDF document"
            return
        }

        pdfDocument = document
        totalPages = document.pageCount
        currentPage = 1
    }

    private func previousPage() {
        if currentPage > 1 {
            currentPage -= 1
        }
    }

    private func nextPage() {
        if currentPage < totalPages {
            currentPage += 1
        }
    }
}

// MARK: - PDFKit UIViewRepresentable

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical

        // Set up notification for page changes
        NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { _ in
            if let currentPDFPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPDFPage) {
                currentPage = pageIndex + 1
            }
        }

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        // Update the displayed page when currentPage binding changes
        if let page = document.page(at: currentPage - 1) {
            pdfView.go(to: page)
        }
    }
}

#Preview {
    NavigationStack {
        PDFViewerView(
            file: File(
                name: "example.pdf",
                path: "/path/to/example.pdf",
                mimeType: "application/pdf",
                sizeBytes: 102400
            )
        )
    }
}
