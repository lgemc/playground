import SwiftUI

/// Hierarchical file browser view showing folders and files
struct FileBrowserView: View {
    let currentPath: String

    @State private var folders: [Folder] = []
    @State private var files: [File] = []
    @State private var showingCreateFolder = false
    @State private var showingAddFile = false
    @State private var showingImportFolder = false
    @State private var showingRenameFolder = false
    @State private var folderToRename: Folder?
    @State private var isLoading = false
    @State private var showingCleanupAlert = false
    @State private var cleanupReport: CleanupReport?
    @State private var showingCleanupConfirm = false

    init(currentPath: String = "") {
        self.currentPath = currentPath
    }

    var body: some View {
        mainContent
    }

    private var mainContent: some View {
        List {
            foldersSection
            filesSection
        }
        .navigationTitle(navigationTitle)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingCreateFolder) {
            NavigationStack {
                CreateFolderView(parentPath: currentPath, onFolderCreated: loadContents)
            }
        }
        .sheet(isPresented: $showingAddFile) {
            NavigationStack {
                AddFileView(folderPath: currentPath, onFileAdded: loadContents)
            }
        }
        .sheet(isPresented: $showingImportFolder) {
            NavigationStack {
                AddFolderView(onFoldersAdded: loadContents)
            }
        }
        .sheet(isPresented: $showingRenameFolder) {
            if let folder = folderToRename {
                NavigationStack {
                    RenameFolderView(folder: folder, onFolderRenamed: loadContents)
                }
            }
        }
        .onAppear(perform: loadContents)
        .refreshable {
            loadContents()
        }
        .alert("Cleanup Storage", isPresented: $showingCleanupConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clean Up", role: .destructive) {
                performCleanup()
            }
        } message: {
            Text("This will remove orphaned files (files on disk but not in database) and old storage directories. This action cannot be undone.")
        }
        .alert("Cleanup Complete", isPresented: $showingCleanupAlert) {
            Button("OK") {}
        } message: {
            if let report = cleanupReport {
                Text(report.summary)
            }
        }
    }

    @ViewBuilder
    private var foldersSection: some View {
        if !folders.isEmpty {
            Section("Folders") {
                ForEach(folders) { folder in
                    FolderRowView(
                        folder: folder,
                        onRename: {
                            folderToRename = folder
                            showingRenameFolder = true
                        },
                        onDelete: {
                            deleteFolder(folder)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var filesSection: some View {
        let sectionTitle = files.isEmpty ? "" : "Files"
        Section(sectionTitle) {
            if folders.isEmpty && files.isEmpty {
                emptyStateView
            } else if files.isEmpty && !folders.isEmpty {
                emptyFilesView
            } else {
                filesList
            }
        }
    }

    private var filesList: some View {
        ForEach(files) { file in
            FileRowView(
                file: file,
                onDelete: { deleteFile(file) },
                onToggleFavorite: { toggleFavorite(file) },
                onFileUpdated: loadContents
            )
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Items",
            systemImage: "folder",
            description: Text("Create a folder or add files to get started")
        )
    }

    private var emptyFilesView: some View {
        Text("No files in this folder")
            .foregroundColor(.secondary)
            .font(.caption)
    }

    private var navigationTitle: String {
        currentPath.isEmpty ? "Files" : pathDisplayName
    }

    private var pathDisplayName: String {
        let components = currentPath.split(separator: "/")
        return components.last.map(String.init) ?? "Files"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                Button(action: debugPrintFileSystem) {
                    Label("Debug Info", systemImage: "info.circle")
                }

                Button(role: .destructive, action: { showingCleanupConfirm = true }) {
                    Label("Cleanup Storage", systemImage: "trash.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            addMenu
        }
    }

    private var addMenu: some View {
        Menu {
            Button(action: { showingCreateFolder = true }) {
                Label("New Folder", systemImage: "folder.badge.plus")
            }

            Button(action: { showingAddFile = true }) {
                Label("Add File", systemImage: "doc.badge.plus")
            }

            Button(action: { showingImportFolder = true }) {
                Label("Import Folder", systemImage: "folder.badge.gearshape")
            }
        } label: {
            Image(systemName: "plus")
        }
    }

    private func debugPrintFileSystem() {
        print("\n📁 ===== FILE SYSTEM DEBUG =====")
        print("Current path: '\(currentPath)'")

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        print("Documents directory: \(documentsURL.path)")

        // Check storage directory
        let storageDirectory = documentsURL
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("file_system", isDirectory: true)
            .appendingPathComponent("storage", isDirectory: true)

        print("\n📂 Storage directory: \(storageDirectory.path)")
        print("   Exists: \(FileManager.default.fileExists(atPath: storageDirectory.path))")

        if let contents = try? FileManager.default.contentsOfDirectory(atPath: storageDirectory.path) {
            print("   Contents (\(contents.count) items):")
            for item in contents {
                let itemPath = storageDirectory.appendingPathComponent(item).path
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDir)
                print("     - \(item) (\(isDir.boolValue ? "dir" : "file"))")
            }
        } else {
            print("   Failed to read contents or directory doesn't exist")
        }

        // Check old Files directory (if exists)
        let oldFilesDirectory = documentsURL.appendingPathComponent("Files")
        print("\n📂 Old 'Files' directory: \(oldFilesDirectory.path)")
        print("   Exists: \(FileManager.default.fileExists(atPath: oldFilesDirectory.path))")

        if FileManager.default.fileExists(atPath: oldFilesDirectory.path) {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: oldFilesDirectory.path) {
                print("   ⚠️ WARNING: Old files found (\(contents.count) items):")
                for item in contents {
                    print("     - \(item)")
                }
            }
        }

        // Print database records
        print("\n💾 Database records (current path: '\(currentPath)'):")
        print("   Folders: \(folders.count)")
        folders.forEach { folder in
            print("     - \(folder.name) (path: \(folder.path))")
        }
        print("   Files: \(files.count)")
        files.forEach { file in
            print("     - \(file.name)")
            print("       DB path: \(file.path)")
            print("       Relative path: \(file.relativePath ?? "nil")")
            print("       Absolute path: \(file.absolutePath)")
            print("       Exists on disk: \(FileManager.default.fileExists(atPath: file.absolutePath))")
        }

        print("===== END DEBUG =====\n")
    }

    private func loadContents() {
        isLoading = true

        // Load folders
        let foldersResult = FileStorage.shared.getFoldersInPath(parentPath: currentPath)
        if foldersResult.isErr {
            print("❌ Failed to load folders: \(foldersResult.error!)")
        } else {
            folders = foldersResult.value!
        }

        // Load files
        let filesResult = FileStorage.shared.getFilesInFolder(folderPath: currentPath)
        if filesResult.isErr {
            print("❌ Failed to load files: \(filesResult.error!)")
        } else {
            files = filesResult.value!
        }

        isLoading = false
    }

    private func deleteFolder(_ folder: Folder) {
        let result = FileStorage.shared.deleteFolder(id: folder.id)

        if result.isErr {
            print("❌ Failed to delete folder: \(result.error!)")
        } else {
            folders.removeAll { $0.id == folder.id }
        }
    }

    private func deleteFile(_ file: File) {
        let result = FileStorage.shared.deleteFile(id: file.id)

        if result.isErr {
            print("❌ Failed to delete file: \(result.error!)")
        } else {
            files.removeAll { $0.id == file.id }
        }
    }

    private func toggleFavorite(_ file: File) {
        let result = FileStorage.shared.toggleFavorite(id: file.id)

        if result.isErr {
            print("❌ Failed to toggle favorite: \(result.error!)")
        } else {
            // Reload to get updated favorite status
            loadContents()
        }
    }

    private func performCleanup() {
        print("🧹 Starting storage cleanup...")
        let result = FileStorage.shared.cleanupOrphanedFiles()

        if let report = result.value {
            cleanupReport = report
            showingCleanupAlert = true

            // Reload contents after cleanup
            loadContents()
        } else if let error = result.error {
            print("❌ Cleanup failed: \(error)")
            cleanupReport = CleanupReport(errors: ["Cleanup failed: \(error.localizedDescription)"])
            showingCleanupAlert = true
        }
    }
}

// MARK: - Supporting Views

struct FolderRowView: View {
    let folder: Folder
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationLink(destination: FileBrowserView(currentPath: folder.path)) {
            Label(folder.name, systemImage: "folder.fill")
                .foregroundColor(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct FileRowView: View {
    let file: File
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void
    let onFileUpdated: () -> Void

    var body: some View {
        NavigationLink(destination: FileDetailView(file: file, onFileUpdated: onFileUpdated)) {
            fileContent
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: onToggleFavorite) {
                Label("Favorite", systemImage: file.isFavorite ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
    }

    private var fileContent: some View {
        HStack {
            Image(systemName: file.iconName)
                .foregroundColor(.orange)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.headline)

                fileMetadata
            }
        }
        .padding(.vertical, 4)
    }

    private var fileMetadata: some View {
        HStack {
            Text(file.formattedSize)
                .font(.caption)
                .foregroundColor(.secondary)

            if file.extractedText != nil {
                Image(systemName: "text.magnifyingglass")
                    .font(.caption2)
                    .foregroundColor(.green)
            }

            if file.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundColor(.yellow)
            }
        }
    }
}

#Preview {
    NavigationStack {
        FileBrowserView()
    }
}
