import Foundation
import SwiftUI

/// Service to orchestrate all AI conversion operations
@MainActor
class ConversionService {
    static let shared = ConversionService()

    private let storage = ConversionStorage.shared
    private let fileStorage = FileStorage.shared
    private let mlx = MLXService.shared
    private let flux = MLXFluxService.shared
    private let fileExtraction = FileExtractionService.shared

    private init() {}

    // MARK: - Conversion Execution

    /// Perform a conversion and save to storage
    func convert(
        type: ConversionType,
        inputText: String? = nil,
        inputFileURL: URL? = nil
    ) async throws -> Conversion {
        // Create initial conversion record
        var inputFileId: String? = nil

        // If a file was provided, import it to internal storage
        if let fileURL = inputFileURL {
            inputFileId = try await importFile(url: fileURL)
        }

        // Create the conversion record
        let result = storage.createConversion(
            type: type,
            inputText: inputText,
            inputFileId: inputFileId
        )

        let conversion: Conversion
        switch result {
        case .ok(let conv):
            conversion = conv
        case .err(let error):
            throw ConversionError.storageFailed(error)
        }

        // Perform the actual conversion asynchronously
        Task {
            do {
                try await performConversion(conversion: conversion)
            } catch {
                print("❌ Conversion failed: \(error)")
                // Update with error in metadata
                _ = storage.updateConversion(
                    id: conversion.id,
                    metadata: ["error": error.localizedDescription]
                )
            }
        }

        return conversion
    }

    /// Perform a streaming conversion (for text-to-text)
    func convertStream(
        type: ConversionType,
        inputText: String? = nil,
        inputFileURL: URL? = nil
    ) -> AsyncThrowingStream<ConversionStreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    // Create conversion record
                    var inputFileId: String? = nil
                    if let fileURL = inputFileURL {
                        inputFileId = try await self.importFile(url: fileURL)
                    }

                    let result = self.storage.createConversion(
                        type: type,
                        inputText: inputText,
                        inputFileId: inputFileId
                    )

                    let conversion: Conversion
                    switch result {
                    case .ok(let conv):
                        conversion = conv
                    case .err(let error):
                        throw ConversionError.storageFailed(error)
                    }

                    continuation.yield(.conversionCreated(conversion))

                    // Stream the conversion
                    try await self.performStreamingConversion(
                        conversion: conversion,
                        continuation: continuation
                    )

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Conversion Logic

    private func performConversion(conversion: Conversion) async throws {
        let startTime = Date()

        switch conversion.type {
        case .textToText:
            try await performTextToText(conversion: conversion)

        case .textToImage:
            try await performTextToImage(conversion: conversion)

        case .imageToText:
            try await performImageToText(conversion: conversion)

        case .textToAudio:
            try await performTextToAudio(conversion: conversion)

        case .audioToText:
            try await performAudioToText(conversion: conversion)

        case .videoToText:
            try await performVideoToText(conversion: conversion)

        case .fileToText:
            try await performFileToText(conversion: conversion)
        }

        let duration = Date().timeIntervalSince(startTime)
        print("✅ Conversion completed in \(String(format: "%.2f", duration))s")
    }

    private func performStreamingConversion(
        conversion: Conversion,
        continuation: AsyncThrowingStream<ConversionStreamEvent, Error>.Continuation
    ) async throws {
        guard conversion.type == .textToText else {
            throw ConversionError.streamingNotSupported(conversion.type)
        }

        guard let inputText = conversion.inputText, !inputText.isEmpty else {
            throw ConversionError.missingInput
        }

        let startTime = Date()
        var accumulatedText = ""

        // Stream from MLX
        for try await chunk in mlx.promptStream(inputText) {
            accumulatedText += chunk
            continuation.yield(.textChunk(chunk))
        }

        // Save final result
        let duration = Date().timeIntervalSince(startTime)
        let metadata: [String: String] = [
            "model": "mlx",
            "duration": String(format: "%.2f", duration)
        ]

        _ = storage.updateConversion(
            id: conversion.id,
            outputText: accumulatedText,
            metadata: metadata
        )

        continuation.yield(.completed(accumulatedText))
    }

    // MARK: - Conversion Type Implementations

    private func performTextToText(conversion: Conversion) async throws {
        guard let inputText = conversion.inputText, !inputText.isEmpty else {
            throw ConversionError.missingInput
        }

        let output = try await mlx.prompt(inputText)

        _ = storage.updateConversion(
            id: conversion.id,
            outputText: output,
            metadata: ["model": "mlx"]
        )
    }

    private func performTextToImage(conversion: Conversion) async throws {
        guard let prompt = conversion.inputText, !prompt.isEmpty else {
            throw ConversionError.missingInput
        }

        // Generate image with Flux
        let image = try await flux.generate(prompt: prompt)

        // Save image to file storage
        let imageData: Data
        #if canImport(UIKit)
        guard let data = image.pngData() else {
            throw ConversionError.imageConversionFailed
        }
        imageData = data
        #elseif canImport(AppKit)
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let data = bitmapImage.representation(using: .png, properties: [:]) else {
            throw ConversionError.imageConversionFailed
        }
        imageData = data
        #endif

        let filename = "image_\(Date().timeIntervalSince1970).png"
        let outputFileId = try await saveGeneratedFile(
            data: imageData,
            filename: filename,
            mimeType: "image/png"
        )

        _ = storage.updateConversion(
            id: conversion.id,
            outputFileId: outputFileId,
            metadata: ["model": "flux"]
        )
    }

    private func performImageToText(conversion: Conversion) async throws {
        guard let fileId = conversion.inputFileId else {
            throw ConversionError.missingInput
        }

        // Load file
        let fileResult = fileStorage.getFile(id: fileId)
        guard case .ok(let fileOpt) = fileResult, let file = fileOpt else {
            throw ConversionError.fileNotFound
        }

        // TODO: Implement vision model (MLX Vision) when available
        // For now, return placeholder
        let output = "Image description: [Vision model not yet implemented]"

        _ = storage.updateConversion(
            id: conversion.id,
            outputText: output,
            metadata: ["model": "placeholder"]
        )
    }

    private func performTextToAudio(conversion: Conversion) async throws {
        guard let text = conversion.inputText, !text.isEmpty else {
            throw ConversionError.missingInput
        }

        // Generate audio with TTS
        let audioData = try await mlx.tts.synthesize(text: text)

        let filename = "audio_\(Date().timeIntervalSince1970).m4a"
        let outputFileId = try await saveGeneratedFile(
            data: audioData,
            filename: filename,
            mimeType: "audio/m4a"
        )

        _ = storage.updateConversion(
            id: conversion.id,
            outputFileId: outputFileId,
            metadata: ["model": "mlx_tts"]
        )
    }

    private func performAudioToText(conversion: Conversion) async throws {
        guard let fileId = conversion.inputFileId else {
            throw ConversionError.missingInput
        }

        // Load file
        let fileResult = fileStorage.getFile(id: fileId)
        guard case .ok(let fileOpt) = fileResult, let file = fileOpt else {
            throw ConversionError.fileNotFound
        }

        // Transcribe with Whisper
        let response = try await mlx.whisper.transcribe(audioURL: URL(fileURLWithPath: file.absolutePath))

        _ = storage.updateConversion(
            id: conversion.id,
            outputText: response.text,
            metadata: ["model": "mlx_whisper"]
        )
    }

    private func performVideoToText(conversion: Conversion) async throws {
        guard let fileId = conversion.inputFileId else {
            throw ConversionError.missingInput
        }

        // Load file
        let fileResult = fileStorage.getFile(id: fileId)
        guard case .ok(let fileOpt) = fileResult, let file = fileOpt else {
            throw ConversionError.fileNotFound
        }

        // Transcribe video with Whisper
        let response = try await mlx.whisper.transcribe(audioURL: URL(fileURLWithPath: file.absolutePath))

        _ = storage.updateConversion(
            id: conversion.id,
            outputText: response.text,
            metadata: ["model": "mlx_whisper"]
        )
    }

    private func performFileToText(conversion: Conversion) async throws {
        guard let fileId = conversion.inputFileId else {
            throw ConversionError.missingInput
        }

        // Load file
        let fileResult = fileStorage.getFile(id: fileId)
        guard case .ok(let fileOpt) = fileResult, let file = fileOpt else {
            throw ConversionError.fileNotFound
        }

        // Extract text from file
        let extractedText = try fileExtraction.extractText(from: file.absolutePath)

        // Summarize with LLM
        let systemPrompt = "You are a helpful assistant that summarizes documents concisely."
        let userPrompt = "Summarize the following document:\n\n\(extractedText)"

        let summary = try await mlx.prompt(userPrompt, systemPrompt: systemPrompt)

        _ = storage.updateConversion(
            id: conversion.id,
            outputText: summary,
            metadata: ["model": "mlx", "extracted_length": String(extractedText.count)]
        )
    }

    // MARK: - File Management

    private func importFile(url: URL) async throws -> String {
        let filename = url.lastPathComponent
        let data = try Data(contentsOf: url)

        return try await saveGeneratedFile(
            data: data,
            filename: filename,
            mimeType: url.mimeType
        )
    }

    private func saveGeneratedFile(
        data: Data,
        filename: String,
        mimeType: String
    ) async throws -> String {
        // Write to conversions directory
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let conversionDir = documentsURL
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("conversions", isDirectory: true)
            .appendingPathComponent("files", isDirectory: true)

        try FileManager.default.createDirectory(at: conversionDir, withIntermediateDirectories: true)

        let fileURL = conversionDir.appendingPathComponent(filename)
        try data.write(to: fileURL)

        // Create file record
        let result = fileStorage.createFile(
            name: filename,
            path: fileURL.path,
            mimeType: mimeType,
            sizeBytes: Int64(data.count)
        )

        switch result {
        case .ok(let file):
            return file.id
        case .err(let error):
            throw ConversionError.storageFailed(error)
        }
    }

    // MARK: - Retrieval

    func getConversion(id: String) -> Conversion? {
        let result = storage.getConversion(id: id)
        return try? result.get() ?? nil
    }

    func getAllConversions() -> [Conversion] {
        let result = storage.getAllConversions()
        return (try? result.get()) ?? []
    }

    func deleteConversion(id: String) throws {
        let result = storage.deleteConversion(id: id)
        try result.get()
    }

    func deleteAllConversions() throws {
        let result = storage.deleteAllConversions()
        try result.get()
    }
}

// MARK: - Supporting Types

enum ConversionStreamEvent {
    case conversionCreated(Conversion)
    case textChunk(String)
    case progress(Double)
    case completed(String)
}

enum ConversionError: LocalizedError {
    case missingInput
    case storageFailed(Error)
    case fileNotFound
    case imageConversionFailed
    case streamingNotSupported(ConversionType)

    var errorDescription: String? {
        switch self {
        case .missingInput:
            return "Missing required input"
        case .storageFailed(let error):
            return "Storage failed: \(error.localizedDescription)"
        case .fileNotFound:
            return "Input file not found"
        case .imageConversionFailed:
            return "Failed to convert image data"
        case .streamingNotSupported(let type):
            return "Streaming not supported for \(type.displayName)"
        }
    }
}

// MARK: - Extensions

extension URL {
    var mimeType: String {
        let ext = pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/m4a"
        case "wav": return "audio/wav"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "md": return "text/markdown"
        default: return "application/octet-stream"
        }
    }
}
