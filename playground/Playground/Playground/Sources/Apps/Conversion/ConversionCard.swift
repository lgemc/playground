import SwiftUI
import AVFoundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Card view for displaying a single conversion in the history
struct ConversionCard: View {
    let conversion: Conversion
    @State private var outputImage: PlatformImage? = nil
    @State private var inputImage: PlatformImage? = nil
    @State private var navigateToFileId: String? = nil
    @State private var isPlaying: Bool = false
    @State private var audioPlayer: AVAudioPlayer? = nil

    private let fileStorage = FileStorage.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Type + Timestamp + Model
            header

            Divider()

            // Input section
            inputSection

            // Arrow
            HStack {
                Spacer()
                Image(systemName: "arrow.down")
                    .foregroundColor(.secondary)
                    .font(.title3)
                Spacer()
            }
            .padding(.vertical, 4)

            // Output section
            outputSection
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .onAppear {
            loadImages()
        }
        .navigationDestination(item: $navigateToFileId) { fileId in
            FileViewerView(fileId: fileId)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            // Type icon and label
            HStack(spacing: 6) {
                Image(systemName: conversion.type.inputIcon)
                    .foregroundColor(.blue)
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Image(systemName: conversion.type.outputIcon)
                    .foregroundColor(.green)

                Text(conversion.type.displayName)
                    .font(.headline)
            }

            Spacer()

            // Timestamp + Model
            VStack(alignment: .trailing, spacing: 2) {
                Text(conversion.formattedTime)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let model = conversion.modelUsed {
                    Text(model)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INPUT")
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.semibold)

            if let fileId = conversion.inputFileId {
                Button {
                    navigateToFileId = fileId
                } label: {
                    filePreview(fileId: fileId, image: inputImage, inputText: nil)
                }
                .buttonStyle(.plain)
            } else if let text = conversion.inputText, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            } else {
                Text("[No input]")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OUTPUT")
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.semibold)

            if let fileId = conversion.outputFileId {
                // Check if it's an audio file
                let fileResult = fileStorage.getFile(id: fileId)
                if case .ok(let file) = fileResult, let file = file, isAudioFile(file) {
                    // For audio files, don't make the whole card clickable (only play button works)
                    filePreview(fileId: fileId, image: outputImage, inputText: conversion.inputText)
                } else {
                    // For non-audio files, allow navigation
                    Button {
                        navigateToFileId = fileId
                    } label: {
                        filePreview(fileId: fileId, image: outputImage, inputText: conversion.inputText)
                    }
                    .buttonStyle(.plain)
                }
            } else if let text = conversion.outputText, !text.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(previewText(from: text))
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    if text.count > 150 {
                        Text("Tap to view full content...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing...")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Audio Playback

    private func isAudioFile(_ file: File) -> Bool {
        let ext = file.fileExtension.lowercased()
        return ext == "m4a" || ext == "mp3" || ext == "wav" || ext == "aac"
    }

    private func togglePlayAudio(file: File) {
        if isPlaying {
            stopAudio()
        } else {
            playAudio(file: file)
        }
    }

    private func playAudio(file: File) {
        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)

            let url = URL(fileURLWithPath: file.absolutePath)

            // Check if file exists
            guard FileManager.default.fileExists(atPath: file.absolutePath) else {
                print("❌ Audio file not found: \(file.absolutePath)")
                return
            }

            print("🔊 Playing audio from: \(file.absolutePath)")
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()

            guard let player = audioPlayer else {
                print("❌ Failed to create audio player")
                return
            }

            let success = player.play()
            if success {
                isPlaying = true
                print("✅ Audio started playing (duration: \(player.duration)s)")

                // Auto-stop when done
                DispatchQueue.main.asyncAfter(deadline: .now() + player.duration + 0.5) {
                    self.isPlaying = false
                }
            } else {
                print("❌ Failed to start audio playback")
            }
        } catch {
            print("❌ Failed to play audio: \(error)")
            isPlaying = false
        }
    }

    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    // MARK: - Helpers

    private func friendlyFileName(for file: File, inputText: String?) -> String {
        let ext = file.fileExtension

        // For audio files, create friendly name from input
        if ext == "m4a" || ext == "mp3" || ext == "wav" {
            if let input = inputText, !input.isEmpty {
                let preview = String(input.prefix(30))
                return "Audio: \(preview)\(input.count > 30 ? "..." : "").\(ext)"
            }
            return "Generated Audio.\(ext)"
        }

        // For images, create friendly name from input
        if ext == "png" || ext == "jpg" || ext == "jpeg" {
            if let input = inputText, !input.isEmpty {
                let preview = String(input.prefix(30))
                return "Image: \(preview)\(input.count > 30 ? "..." : "").\(ext)"
            }
            return "Generated Image.\(ext)"
        }

        // For other files, use original name
        return file.name
    }

    private func previewText(from text: String) -> String {
        // Strip markdown and LaTeX for preview
        var preview = text

        // Remove LaTeX formulas (display mode $$...$$)
        preview = preview.replacing(/\$\$[^\$]+\$\$/) { _ in "[formula]" }

        // Remove LaTeX formulas (inline mode $...$)
        preview = preview.replacing(/\$[^\$]+\$/) { _ in "[math]" }

        // Remove markdown bold **text**
        preview = preview.replacing(/\*\*([^\*]+)\*\*/) { match in
            String(match.output.1)
        }

        // Remove markdown italic *text*
        preview = preview.replacing(/\*([^\*]+)\*/) { match in
            String(match.output.1)
        }

        // Remove markdown code `text`
        preview = preview.replacing(/`([^`]+)`/) { match in
            String(match.output.1)
        }

        // Collapse multiple newlines
        preview = preview.replacing(/\n+/) { _ in " " }

        // Trim and truncate
        preview = preview.trimmingCharacters(in: .whitespacesAndNewlines)

        if preview.count > 150 {
            let index = preview.index(preview.startIndex, offsetBy: 147)
            preview = String(preview[..<index]) + "..."
        }

        return preview
    }

    @ViewBuilder
    private func filePreview(fileId: String, image: PlatformImage?, inputText: String?) -> some View {
        let fileResult = fileStorage.getFile(id: fileId)
        if case .ok(let file) = fileResult, let file = file {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: file.iconName)
                        .foregroundColor(.blue)

                    // Show friendly name instead of raw filename
                    Text(friendlyFileName(for: file, inputText: inputText))
                        .font(.body)
                        .lineLimit(1)

                    Spacer()

                    // Play button for audio files
                    if isAudioFile(file) {
                        Button(action: {
                            togglePlayAudio(file: file)
                        }) {
                            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(isPlaying ? Color.red : Color.blue)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if let size = file.sizeBytes {
                        Text(file.formattedSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Show image thumbnail if available
                if let img = image {
                    #if canImport(UIKit)
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                    #elseif canImport(AppKit)
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                    #endif
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .foregroundColor(.secondary)
                Text("[File not found]")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }

    // MARK: - Helpers

    private func loadImages() {
        // Load input image if applicable
        if let fileId = conversion.inputFileId {
            loadImage(fileId: fileId) { image in
                inputImage = image
            }
        }

        // Load output image if applicable
        if let fileId = conversion.outputFileId {
            loadImage(fileId: fileId) { image in
                outputImage = image
            }
        }
    }

    private func loadImage(fileId: String, completion: @escaping (PlatformImage?) -> Void) {
        let fileResult = fileStorage.getFile(id: fileId)
        guard case .ok(let file) = fileResult,
              let file = file,
              file.fileExtension == "png" || file.fileExtension == "jpg" || file.fileExtension == "jpeg" else {
            completion(nil)
            return
        }

        #if canImport(UIKit)
        if let image = UIImage(contentsOfFile: file.absolutePath) {
            completion(image)
        } else {
            completion(nil)
        }
        #elseif canImport(AppKit)
        if let image = NSImage(contentsOfFile: file.absolutePath) {
            completion(image)
        } else {
            completion(nil)
        }
        #endif
    }
}

#Preview {
    VStack(spacing: 16) {
        // Text to text conversion
        ConversionCard(
            conversion: Conversion(
                type: .textToText,
                inputText: "What is the capital of France?",
                outputText: "The capital of France is Paris, a major European city and a global center for art, fashion, gastronomy and culture.",
                metadata: ["model": "mlx"]
            )
        )

        // Text to image conversion (processing)
        ConversionCard(
            conversion: Conversion(
                type: .textToImage,
                inputText: "A serene mountain landscape at sunset",
                metadata: ["model": "flux"]
            )
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
