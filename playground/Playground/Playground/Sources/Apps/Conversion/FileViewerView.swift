import SwiftUI
import AVKit

/// View for displaying converted files (videos, audio, PDFs, images)
struct FileViewerView: View {
    let fileId: String

    @State private var file: File?
    @State private var isLoading = true
    @State private var error: String?

    private let fileStorage = FileStorage.shared

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading file...")
            } else if let error = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("Error loading file")
                        .font(.headline)
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else if let file = file {
                fileContentView(for: file)
            }
        }
        .navigationTitle(file?.name ?? "File")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadFile()
        }
    }

    @ViewBuilder
    private func fileContentView(for file: File) -> some View {
        let ext = file.fileExtension.lowercased()

        switch ext {
        case "mp4", "mov", "m4v":
            VideoPlayerView(file: file)

        case "mp3", "m4a", "wav":
            ConversionAudioPlayerView(file: file)

        case "pdf":
            PDFViewerView(file: file)

        case "png", "jpg", "jpeg", "gif":
            ConversionImageViewerView(file: file)

        default:
            VStack(spacing: 16) {
                Image(systemName: file.iconName)
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)

                Text("Preview not available")
                    .font(.headline)

                Text("File type: \(ext)")
                    .font(.body)
                    .foregroundColor(.secondary)

                if let size = file.sizeBytes {
                    Text("Size: \(file.formattedSize)")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }

    private func loadFile() {
        let result = fileStorage.getFile(id: fileId)

        switch result {
        case .ok(let loadedFile):
            if let loadedFile = loadedFile {
                file = loadedFile

                // Check if file exists
                if !FileManager.default.fileExists(atPath: loadedFile.absolutePath) {
                    error = "File not found at path: \(loadedFile.absolutePath)"
                }
            } else {
                error = "File not found in database"
            }

        case .err(let err):
            error = err.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Audio Player

struct ConversionAudioPlayerView: View {
    let file: File

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Audio icon
            Image(systemName: "music.note")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            // File name
            Text(file.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Progress slider
            VStack(spacing: 8) {
                Slider(value: $currentTime, in: 0...max(duration, 1), onEditingChanged: { editing in
                    if !editing {
                        player?.seek(to: CMTime(seconds: currentTime, preferredTimescale: 1))
                    }
                })

                HStack {
                    Text(formatTime(currentTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatTime(duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)

            // Play/Pause button
            Button {
                togglePlayPause()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
            }

            Spacer()
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func setupPlayer() {
        let url = URL(fileURLWithPath: file.absolutePath)
        player = AVPlayer(url: url)

        // Get duration
        let asset = AVAsset(url: url)
        Task {
            if let durationTime = try? await asset.load(.duration) {
                await MainActor.run {
                    duration = CMTimeGetSeconds(durationTime)
                }
            }
        }

        // Update current time
        player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 1), queue: .main) { time in
            currentTime = CMTimeGetSeconds(time)
        }
    }

    private func togglePlayPause() {
        guard let player = player else { return }

        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Image Viewer

struct ConversionImageViewerView: View {
    let file: File

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Group {
            if let image = image {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = value
                                }
                        )
                }
            } else {
                ProgressView("Loading image...")
            }
        }
        .onAppear {
            image = UIImage(contentsOfFile: file.absolutePath)
        }
    }
}

#Preview {
    NavigationStack {
        Text("File Viewer Preview")
    }
}
