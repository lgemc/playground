import SwiftUI

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
                filePreview(fileId: fileId, image: inputImage)
            } else if let text = conversion.inputText, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(5)
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
                filePreview(fileId: fileId, image: outputImage)
            } else if let text = conversion.outputText, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(5)
                    .textSelection(.enabled)
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

    @ViewBuilder
    private func filePreview(fileId: String, image: PlatformImage?) -> some View {
        let fileResult = fileStorage.getFile(id: fileId)
        if case .ok(let file) = fileResult, let file = file {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: file.iconName)
                        .foregroundColor(.blue)
                    Text(file.name)
                        .font(.body)
                        .lineLimit(1)
                    Spacer()
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
