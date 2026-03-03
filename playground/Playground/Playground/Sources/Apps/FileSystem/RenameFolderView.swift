import SwiftUI

/// View for renaming an existing folder
struct RenameFolderView: View {
    @Environment(\.dismiss) private var dismiss
    let folder: Folder
    let onFolderRenamed: () -> Void

    @State private var newName: String
    @State private var isRenaming = false
    @State private var showError = false
    @State private var errorMessage = ""

    init(folder: Folder, onFolderRenamed: @escaping () -> Void) {
        self.folder = folder
        self.onFolderRenamed = onFolderRenamed
        _newName = State(initialValue: folder.name)
    }

    var body: some View {
        Form {
            Section("Folder Name") {
                TextField("Folder Name", text: $newName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    Text("Current Name")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(folder.name)
                        .foregroundColor(.secondary)
                }

                if !folder.parentPath.isEmpty {
                    HStack {
                        Text("Location")
                        Spacer()
                        Text(folder.parentPath)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                } else {
                    HStack {
                        Text("Location")
                        Spacer()
                        Text("Root")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }

            Section {
                Text("Renaming this folder will update all files and subfolders within it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Rename Folder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Rename") {
                    renameFolder()
                }
                .disabled(newName.isEmpty || newName == folder.name || isRenaming)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func renameFolder() {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Folder name cannot be empty"
            showError = true
            return
        }

        guard trimmedName != folder.name else {
            dismiss()
            return
        }

        // Validate folder name (no slashes, special characters)
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        if trimmedName.rangeOfCharacter(from: invalidCharacters) != nil {
            errorMessage = "Folder name contains invalid characters: / \\ : * ? \" < > |"
            showError = true
            return
        }

        isRenaming = true

        let result = FileStorage.shared.renameFolder(id: folder.id, newName: trimmedName)

        if result.isErr {
            errorMessage = "Failed to rename folder: \(result.error!.localizedDescription)"
            showError = true
            isRenaming = false
        } else {
            isRenaming = false
            onFolderRenamed()
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        RenameFolderView(
            folder: Folder(name: "Documents", path: "Documents/", parentPath: ""),
            onFolderRenamed: {}
        )
    }
}
