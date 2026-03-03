import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Folder picker view - allows browsing and selecting folders using UIDocumentPickerViewController
struct FolderPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onFolderSelected: (URL) -> Void

    @State private var showingDocumentPicker = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("Select a Folder")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose a folder to add to your file system. You'll have access to all files in the selected folder.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: {
                showingDocumentPicker = true
            }) {
                Label("Browse Folders", systemImage: "folder")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: 280)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.top, 20)

            Spacer()
        }
        .navigationTitle("Select Folder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker(onFolderSelected: { url in
                onFolderSelected(url)
                dismiss()
            })
        }
    }
}

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {
    let onFolderSelected: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFolderSelected: onFolderSelected)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFolderSelected: (URL) -> Void

        init(onFolderSelected: @escaping (URL) -> Void) {
            self.onFolderSelected = onFolderSelected
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
                let bookmarkKey = "folder_bookmark_\(url.path.hash)"
                UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)

                print("✅ Created bookmark for folder: \(url.path)")
            } catch {
                print("⚠️ Failed to create bookmark: \(error.localizedDescription)")
            }

            // Call the completion handler
            onFolderSelected(url)

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

// MARK: - Preview

#Preview {
    NavigationStack {
        FolderPickerView { url in
            print("Selected folder: \(url)")
        }
    }
}
