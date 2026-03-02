import SwiftUI

/// Folder picker view - allows browsing and selecting iOS file system folders
struct FolderPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onFolderSelected: (URL) -> Void

    @State private var currentPath: URL
    @State private var folders: [FolderInfo] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    // Initialize with user's home directory or documents
    init(onFolderSelected: @escaping (URL) -> Void) {
        self.onFolderSelected = onFolderSelected

        // Start with Documents directory
        #if os(iOS)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        #else
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        #endif

        _currentPath = State(initialValue: documentsPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb navigation
            FolderBreadcrumb(currentPath: currentPath, onNavigate: navigateToPath)

            Divider()

            // Folder list
            if isLoading {
                Spacer()
                ProgressView("Loading folders...")
                Spacer()
            } else if folders.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 64))
                        .foregroundColor(.gray)

                    Text("No accessible folders")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("This folder may be empty or you may not have permission to access its contents")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
            } else {
                List {
                    // Parent directory option (if not at root)
                    if canGoUp {
                        Button(action: goUp) {
                            HStack {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title2)

                                Text("Parent Folder")
                                    .foregroundColor(.primary)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Folder list
                    ForEach(folders) { folder in
                        Button(action: { navigateToFolder(folder) }) {
                            HStack {
                                Image(systemName: folder.isSpecialFolder ? "folder.fill" : "folder")
                                    .foregroundColor(folder.isSpecialFolder ? .orange : .blue)
                                    .font(.title2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.name)
                                        .foregroundColor(.primary)

                                    if let itemCount = folder.itemCount {
                                        Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Select Folder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Select") {
                    onFolderSelected(currentPath)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadFolders()
        }
    }

    // MARK: - Navigation

    private var canGoUp: Bool {
        // Can go up if not at root
        return currentPath.path != "/"
    }

    private func goUp() {
        let parent = currentPath.deletingLastPathComponent()
        navigateToPath(parent)
    }

    private func navigateToFolder(_ folder: FolderInfo) {
        navigateToPath(folder.url)
    }

    private func navigateToPath(_ path: URL) {
        currentPath = path
        loadFolders()
    }

    // MARK: - Data Loading

    private func loadFolders() {
        isLoading = true
        folders = []

        Task {
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: currentPath,
                    includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )

                // Filter to directories only
                var folderInfos: [FolderInfo] = []

                for url in contents {
                    let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                    if resourceValues.isDirectory == true {
                        // Try to count items in folder
                        let itemCount = try? FileManager.default.contentsOfDirectory(atPath: url.path).count

                        folderInfos.append(FolderInfo(
                            url: url,
                            name: url.lastPathComponent,
                            itemCount: itemCount,
                            isSpecialFolder: isSpecialFolder(url)
                        ))
                    }
                }

                // Sort folders alphabetically
                folderInfos.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                await MainActor.run {
                    folders = folderInfos
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load folders: \(error.localizedDescription)"
                    showError = true
                    isLoading = false
                }
            }
        }
    }

    private func isSpecialFolder(_ url: URL) -> Bool {
        // Check if it's a special system folder
        let specialFolders = [
            FileManager.SearchPathDirectory.documentDirectory,
            .downloadsDirectory,
            .desktopDirectory,
            .picturesDirectory,
            .moviesDirectory,
            .musicDirectory
        ]

        for directory in specialFolders {
            if let specialPath = FileManager.default.urls(for: directory, in: .userDomainMask).first,
               url.path == specialPath.path {
                return true
            }
        }

        return false
    }
}

// MARK: - Supporting Types

struct FolderInfo: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let itemCount: Int?
    let isSpecialFolder: Bool
}

// MARK: - Breadcrumb Component

private struct FolderBreadcrumb: View {
    let currentPath: URL
    let onNavigate: (URL) -> Void

    private var pathComponents: [PathComponent] {
        var components: [PathComponent] = []
        var currentURL = currentPath

        // Build path from current to root
        while currentURL.path != "/" {
            let name = currentURL.lastPathComponent
            if !name.isEmpty {
                components.insert(PathComponent(name: name, url: currentURL), at: 0)
            }
            currentURL = currentURL.deletingLastPathComponent()
        }

        // Add root
        #if os(iOS)
        // On iOS, use Documents directory as root
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            components.insert(PathComponent(name: "Documents", url: documentsURL), at: 0)
        }
        #else
        components.insert(PathComponent(name: "~", url: FileManager.default.homeDirectoryForCurrentUser), at: 0)
        #endif

        return components
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(pathComponents.enumerated()), id: \.element.id) { index, component in
                    Button(action: { onNavigate(component.url) }) {
                        Text(component.name)
                            .font(.subheadline)
                            .foregroundColor(index == pathComponents.count - 1 ? .primary : .blue)
                            .fontWeight(index == pathComponents.count - 1 ? .semibold : .regular)
                            .lineLimit(1)
                    }

                    if index < pathComponents.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
    }

    private struct PathComponent: Identifiable {
        let id = UUID()
        let name: String
        let url: URL
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
