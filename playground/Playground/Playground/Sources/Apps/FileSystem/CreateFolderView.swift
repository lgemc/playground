import SwiftUI

/// View for creating a new folder in the virtual drive
struct CreateFolderView: View {
    @Environment(\.dismiss) private var dismiss
    let parentPath: String
    let onFolderCreated: () -> Void

    @State private var folderName: String = ""
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Form {
            Section("Folder Details") {
                TextField("Folder Name", text: $folderName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !parentPath.isEmpty {
                    HStack {
                        Text("Location")
                        Spacer()
                        Text(parentPath)
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
                Text("Create a virtual folder in the file system drive. This folder exists only in the app's database.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("New Folder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Create") {
                    createFolder()
                }
                .disabled(folderName.isEmpty || isCreating)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func createFolder() {
        let trimmedName = folderName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Folder name cannot be empty"
            showError = true
            return
        }

        // Validate folder name (no slashes, special characters)
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        if trimmedName.rangeOfCharacter(from: invalidCharacters) != nil {
            errorMessage = "Folder name contains invalid characters: / \\ : * ? \" < > |"
            showError = true
            return
        }

        isCreating = true

        let result = FileStorage.shared.createFolder(name: trimmedName, parentPath: parentPath)

        if result.isErr {
            errorMessage = "Failed to create folder: \(result.error!.localizedDescription)"
            showError = true
            isCreating = false
        } else {
            isCreating = false
            onFolderCreated()
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        CreateFolderView(parentPath: "", onFolderCreated: {})
    }
}
