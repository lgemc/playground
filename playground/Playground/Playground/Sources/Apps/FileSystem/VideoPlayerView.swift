import SwiftUI
import AVKit
import AVFoundation

/// Video Player component for displaying video files
struct VideoPlayerView: View {
    let file: File

    @State private var player: AVPlayer?
    @State private var loadError: String?
    @State private var isPlaying = false

    var body: some View {
        VStack(spacing: 0) {
            if let error = loadError {
                errorView(message: error)
            } else if let player = player {
                VideoPlayer(player: player)
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        // Auto-play when view appears
                        player.play()
                        isPlaying = true
                    }
                    .onDisappear {
                        // Pause when view disappears
                        player.pause()
                        isPlaying = false
                    }
            } else {
                loadingView
            }
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadVideo)
        .onDisappear {
            // Clean up player
            player?.pause()
            player = nil
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading Video...")
                .foregroundColor(.secondary)
        }
    }

    private func errorView(message: String) -> some View {
        ContentUnavailableView(
            "Cannot Play Video",
            systemImage: "video.fill.badge.exclamationmark",
            description: Text(message)
        )
    }

    private func loadVideo() {
        let absolutePath = file.absolutePath

        // Debug logging
        print("🎥 VideoPlayerView - Loading video:")
        print("   File name: \(file.name)")
        print("   File.path: \(file.path)")
        print("   File.relativePath: \(file.relativePath ?? "nil")")
        print("   File.folderPath: \(file.folderPath ?? "nil")")
        print("   Computed absolutePath: \(absolutePath)")
        print("   File exists: \(FileManager.default.fileExists(atPath: absolutePath))")

        // List files in Documents to see what's actually there
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            print("   Documents path: \(documentsURL.path)")
            if let filesInDocs = try? FileManager.default.contentsOfDirectory(atPath: documentsURL.path) {
                print("   Contents of Documents: \(filesInDocs)")
            }
        }

        guard FileManager.default.fileExists(atPath: absolutePath) else {
            loadError = "File not found at path: \(absolutePath)"
            return
        }

        let url = URL(fileURLWithPath: absolutePath)

        // Verify the video file is readable
        let asset = AVAsset(url: url)
        let keys = ["playable", "hasProtectedContent"]

        Task {
            do {
                // Load asset properties asynchronously
                try await asset.load(.isPlayable)
                let isPlayable = asset.isPlayable

                if !isPlayable {
                    await MainActor.run {
                        loadError = "Video file is not playable"
                    }
                    return
                }

                // Create player on main actor
                await MainActor.run {
                    player = AVPlayer(url: url)
                }
            } catch {
                await MainActor.run {
                    loadError = "Failed to load video: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        VideoPlayerView(
            file: File(
                name: "example.mp4",
                path: "/path/to/example.mp4",
                mimeType: "video/mp4",
                sizeBytes: 10485760
            )
        )
    }
}
