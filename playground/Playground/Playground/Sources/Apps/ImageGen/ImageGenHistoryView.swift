import SwiftUI

struct ImageGenHistoryView: View {
    @State private var generatedImages: [GeneratedImageInfo] = []

    var body: some View {
        ScrollView {
            if generatedImages.isEmpty {
                emptyStateView
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(generatedImages) { imageInfo in
                        NavigationLink(destination: ImageDetailView(imageInfo: imageInfo)) {
                            ImageThumbnail(imageInfo: imageInfo)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Generation History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadHistory()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Generated Images")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Images you generate will appear here")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func loadHistory() async {
        // TODO: Load generated images from FileStorage
        // For now, scan the generated/images directory

        guard let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return
        }

        let imagesDirectory = documentsDirectory
            .appendingPathComponent("data/file_system/storage/generated/images")

        guard FileManager.default.fileExists(atPath: imagesDirectory.path) else {
            return
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: imagesDirectory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
            )

            generatedImages = files.compactMap { url in
                guard url.pathExtension == "png" else { return nil }

                let attributes = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                let createdAt = attributes?.creationDate ?? Date()

                return GeneratedImageInfo(
                    id: url.lastPathComponent,
                    url: url,
                    prompt: extractPromptFromFilename(url.lastPathComponent),
                    createdAt: createdAt
                )
            }
            .sorted { $0.createdAt > $1.createdAt }

        } catch {
            print("❌ Failed to load image history: \(error)")
        }
    }

    private func extractPromptFromFilename(_ filename: String) -> String {
        // Filename format: prompt_timestamp.png
        let components = filename.replacingOccurrences(of: ".png", with: "").split(separator: "_")
        guard components.count > 1 else { return "Unknown" }

        // Remove timestamp (last component)
        let promptParts = components.dropLast()
        return promptParts.joined(separator: " ").replacingOccurrences(of: "_", with: " ")
    }
}

// MARK: - Image Thumbnail

struct ImageThumbnail: View {
    let imageInfo: GeneratedImageInfo
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 150)
                    .clipped()
                    .cornerRadius(12)
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 150)
                    .cornerRadius(12)
                    .overlay {
                        ProgressView()
                    }
            }

            Text(imageInfo.prompt)
                .font(.caption)
                .lineLimit(2)
                .foregroundColor(.primary)

            Text(imageInfo.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .task {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        if let data = try? Data(contentsOf: imageInfo.url),
           let image = UIImage(data: data) {
            thumbnail = image
        }
    }
}

// MARK: - Image Detail View

struct ImageDetailView: View {
    let imageInfo: GeneratedImageInfo
    @State private var fullImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let fullImage = fullImage {
                    Image(uiImage: fullImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(12)
                } else {
                    ProgressView()
                        .frame(height: 300)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Prompt")
                        .font(.headline)

                    Text(imageInfo.prompt)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)

                    Text("Created")
                        .font(.headline)
                        .padding(.top)

                    Text(imageInfo.createdAt.formatted(date: .long, time: .shortened))
                        .font(.body)
                }
                .padding()
            }
        }
        .navigationTitle("Image Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadFullImage()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        saveToPhotos()
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        shareImage()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        deleteImage()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func loadFullImage() {
        if let data = try? Data(contentsOf: imageInfo.url),
           let image = UIImage(data: data) {
            fullImage = image
        }
    }

    private func saveToPhotos() {
        guard let image = fullImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }

    private func shareImage() {
        // TODO: Implement share sheet
        print("📤 Share requested")
    }

    private func deleteImage() {
        do {
            try FileManager.default.removeItem(at: imageInfo.url)
            print("✅ Image deleted")
        } catch {
            print("❌ Failed to delete image: \(error)")
        }
    }
}

// MARK: - Supporting Types

struct GeneratedImageInfo: Identifiable {
    let id: String
    let url: URL
    let prompt: String
    let createdAt: Date
}

#Preview {
    NavigationStack {
        ImageGenHistoryView()
    }
}
