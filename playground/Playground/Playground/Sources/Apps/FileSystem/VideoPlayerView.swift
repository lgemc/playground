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
        guard FileManager.default.fileExists(atPath: file.path) else {
            loadError = "File not found at path: \(file.path)"
            return
        }

        let url = URL(fileURLWithPath: file.path)

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
