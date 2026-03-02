import SwiftUI

/// File list view - shows all files with search and statistics
struct FileListView: View {
    @State private var files: [File] = []
    @State private var statistics: FileStatistics?
    @State private var showingAddFile = false
    @State private var showingAddFolder = false
    @State private var searchText = ""
    @State private var isLoading = false

    var filteredFiles: [File] {
        if searchText.isEmpty {
            return files
        } else {
            return files.filter { file in
                file.name.localizedCaseInsensitiveContains(searchText) ||
                (file.extractedText?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }

    var body: some View {
        List {
            // Statistics section
            if let stats = statistics {
                Section {
                    VStack(spacing: 12) {
                        StatRow(label: "Total Files", value: "\(stats.totalFiles)")
                        StatRow(label: "Total Size", value: stats.formattedTotalSize)
                        StatRow(label: "With Extracted Text", value: "\(stats.filesWithExtractedText)")
                    }
                    .padding(.vertical, 8)
                }
            }

            // File list
            Section("Files") {
                if filteredFiles.isEmpty {
                    Text(searchText.isEmpty ? "No files yet" : "No matching files")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .padding()
                } else {
                    ForEach(filteredFiles) { file in
                        NavigationLink(destination: FileDetailView(file: file, onFileUpdated: loadFiles)) {
                            HStack {
                                Image(systemName: file.iconName)
                                    .foregroundColor(.orange)
                                    .frame(width: 30)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.name)
                                        .font(.headline)

                                    HStack {
                                        Text(file.formattedSize)
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        if file.extractedText != nil {
                                            Image(systemName: "text.magnifyingglass")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: deleteFiles)
                }
            }
        }
        .navigationTitle("Files")
        .searchable(text: $searchText, prompt: "Search files")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingAddFile = true }) {
                        Label("Add File", systemImage: "doc.badge.plus")
                    }

                    Button(action: { showingAddFolder = true }) {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddFile) {
            NavigationStack {
                AddFileView(onFileAdded: loadFiles)
            }
        }
        .sheet(isPresented: $showingAddFolder) {
            NavigationStack {
                AddFolderView(onFoldersAdded: loadFiles)
            }
        }
        .onAppear(perform: loadFiles)
        .refreshable {
            loadFiles()
        }
    }

    private func loadFiles() {
        isLoading = true

        let filesResult = FileStorage.shared.getAllFiles()
        if filesResult.isErr {
            print("❌ Failed to load files: \(filesResult.error!)")
        } else {
            files = filesResult.value!
        }

        let statsResult = FileStorage.shared.getStatistics()
        if statsResult.isErr {
            print("❌ Failed to load statistics: \(statsResult.error!)")
        } else {
            statistics = statsResult.value
        }

        isLoading = false
    }

    private func deleteFiles(at offsets: IndexSet) {
        for index in offsets {
            let file = filteredFiles[index]
            let result = FileStorage.shared.deleteFile(id: file.id)

            if result.isErr {
                print("❌ Failed to delete file: \(result.error!)")
            } else {
                files.removeAll { $0.id == file.id }
            }
        }
    }
}

// MARK: - Supporting Views

private struct StatRow: View {
    let label: String
    let value: String
    var highlight: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(highlight ? .orange : .primary)
        }
    }
}

#Preview {
    NavigationStack {
        FileListView()
    }
}
