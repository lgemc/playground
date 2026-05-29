import Foundation
import SwiftUI

/// Service to orchestrate all AI conversion operations
@MainActor
class ConversionService {
    static let shared = ConversionService()

    private let storage = ConversionStorage.shared
    private let fileStorage = FileStorage.shared
    private let chatStorage = ChatStorage.shared
    private let mlx = MLXService.shared
    private let vlm = MLXVLMService.shared
    private let fileExtraction = FileExtractionService.shared

    private init() {}

    // MARK: - Conversion Execution

    /// Perform a conversion and save to storage
    /// Returns the conversion and the chat ID (if created)
    func convert(
        type: ConversionType,
        inputText: String? = nil,
        inputFileURL: URL? = nil
    ) async throws -> (conversion: Conversion, chatId: String?) {
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

        // Perform the actual conversion synchronously and wait for chat creation
        do {
            try await performConversion(conversion: conversion)

            // Get the updated conversion with chat_id
            if let updated = getConversion(id: conversion.id),
               let chatId = updated.metadata["chat_id"] {
                return (updated, chatId)
            }

            return (conversion, nil)
        } catch {
            print("❌ Conversion failed: \(error)")
            // Update with error in metadata
            try? updateConversionStorage(
                id: conversion.id,
                metadata: ["error": error.localizedDescription]
            )
            throw error
        }
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

    func performConversionPublic(conversion: Conversion) async throws {
        try await performConversion(conversion: conversion)
    }

    private func performConversion(conversion: Conversion) async throws {
        let startTime = Date()

        switch conversion.type {
        case .textToText:
            try await performTextToText(conversion: conversion)

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

        // Create chat for conversions with text output
        try await createChatIfNeeded(for: conversion, duration: duration)
    }

    /// Create a chat from any conversion that has text input/output
    private func createChatIfNeeded(for conversion: Conversion, duration: Double) async throws {
        // Get the updated conversion from storage
        guard let updated = getConversion(id: conversion.id),
              let outputText = updated.outputText,
              !outputText.isEmpty else {
            return
        }

        // Create chat title from input or conversion type
        let title: String
        if let inputText = updated.inputText, !inputText.isEmpty {
            title = String(inputText.prefix(50))
        } else {
            title = "\(updated.type.displayName) - \(updated.formattedTime)"
        }

        let chatResult = chatStorage.createChat(title: title)
        guard case .ok(let chat) = chatResult else {
            return
        }

        // Add user message if there's input text
        if let inputText = updated.inputText, !inputText.isEmpty {
            _ = chatStorage.createMessage(chatId: chat.id, role: .user, content: inputText)
        }

        // Add assistant message with output
        _ = chatStorage.createMessage(chatId: chat.id, role: .assistant, content: outputText)

        // Update conversion metadata with chat ID
        var metadata = updated.metadata
        metadata["chat_id"] = chat.id
        metadata["duration"] = String(format: "%.2f", duration)

        try updateConversionStorage(
            id: updated.id,
            metadata: metadata
        )

        print("✅ Created chat \(chat.id) from \(updated.type.displayName) conversion")
    }

    private func performStreamingConversion(
        conversion: Conversion,
        continuation: AsyncThrowingStream<ConversionStreamEvent, Error>.Continuation
    ) async throws {
        let startTime = Date()
        var accumulatedText = ""
        var userPrompt = ""
        var systemPrompt: String? = nil

        switch conversion.type {
        case .textToText:
            guard let inputText = conversion.inputText, !inputText.isEmpty else {
                throw ConversionError.missingInput
            }
            userPrompt = inputText

        case .fileToText:
            guard let fileId = conversion.inputFileId else {
                throw ConversionError.missingInput
            }

            // Load file
            let fileResult = fileStorage.getFile(id: fileId)
            guard case .ok(let fileOpt) = fileResult, let file = fileOpt else {
                throw ConversionError.fileNotFound
            }

            // Extract text from file
            print("📄 Extracting text from: \(file.name)")
            let extractedText = try fileExtraction.extractText(from: file.absolutePath)
            print("✅ Extracted \(extractedText.count) characters")

            // Prepare summarization prompt
            systemPrompt = "You are a helpful assistant that summarizes documents concisely."
            userPrompt = "Summarize the following document:\n\n\(extractedText)"

        default:
            throw ConversionError.streamingNotSupported(conversion.type)
        }

        // Stream from MLX
        for try await chunk in mlx.promptStream(userPrompt, systemPrompt: systemPrompt) {
            accumulatedText += chunk
            continuation.yield(.textChunk(chunk))
        }

        // Save final result
        let duration = Date().timeIntervalSince(startTime)
        var metadata: [String: String] = [
            "model": "mlx",
            "duration": String(format: "%.2f", duration)
        ]

        // Add extracted length for file conversions
        if conversion.type == .fileToText, let fileId = conversion.inputFileId {
            let fileResult = fileStorage.getFile(id: fileId)
            if case .ok(let fileOpt) = fileResult, let file = fileOpt {
                if let extractedText = try? fileExtraction.extractText(from: file.absolutePath) {
                    metadata["extracted_length"] = String(extractedText.count)
                }
            }
        }

        // Create a chat from this conversion
        var chatId: String? = nil
        let chatTitle: String
        if conversion.type == .fileToText, let fileId = conversion.inputFileId {
            let fileResult = fileStorage.getFile(id: fileId)
            if case .ok(let fileOpt) = fileResult, let file = fileOpt {
                chatTitle = "Summary: \(file.name)"
            } else {
                chatTitle = "File Summary"
            }
        } else if let inputText = conversion.inputText {
            chatTitle = String(inputText.prefix(50))
        } else {
            chatTitle = "Conversion"
        }

        let chatResult = chatStorage.createChat(title: chatTitle)
        if case .ok(let chat) = chatResult {
            chatId = chat.id

            // Add user message
            let userMessage = conversion.type == .fileToText ? "Summarize this document" : (conversion.inputText ?? "")
            _ = chatStorage.createMessage(chatId: chat.id, role: .user, content: userMessage)

            // Add assistant response
            _ = chatStorage.createMessage(chatId: chat.id, role: .assistant, content: accumulatedText)

            print("✅ Created chat \(chat.id) from \(conversion.type) conversion")
        }

        // Update metadata with chat ID
        if let chatId = chatId {
            metadata["chat_id"] = chatId
        }

        try updateConversionStorage(
            id: conversion.id,
            outputText: accumulatedText,
            metadata: metadata
        )

        continuation.yield(.completed(accumulatedText, chatId: chatId))
    }

    // MARK: - Conversion Type Implementations

    private func performTextToText(conversion: Conversion) async throws {
        guard let inputText = conversion.inputText, !inputText.isEmpty else {
            throw ConversionError.missingInput
        }

        let output = try await mlx.prompt(inputText)

        try updateConversionStorage(
            id: conversion.id,
            outputText: output,
            metadata: ["model": "mlx"]
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

        // Load image
        let image: PlatformImage
        #if canImport(UIKit)
        guard let img = UIImage(contentsOfFile: file.absolutePath) else {
            throw ConversionError.fileAccessDenied
        }
        image = img
        #elseif canImport(AppKit)
        guard let img = NSImage(contentsOfFile: file.absolutePath) else {
            throw ConversionError.fileAccessDenied
        }
        image = img
        #endif

        // Analyze image with Qwen VLM
        print("👁️ Analyzing image with Qwen VLM: \(file.name)")
        let description = try await vlm.describeImage(image)

        try updateConversionStorage(
            id: conversion.id,
            outputText: description,
            metadata: ["model": "qwen-vl"]
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

        try updateConversionStorage(
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

        // Store segments as JSON for timestamp display later
        var metadata: [String: String] = ["model": "mlx_whisper"]
        if let segments = response.segments,
           let segmentsData = try? JSONEncoder().encode(segments),
           let segmentsJson = String(data: segmentsData, encoding: .utf8) {
            metadata["segments"] = segmentsJson
        }

        try updateConversionStorage(
            id: conversion.id,
            outputText: response.text,
            metadata: metadata
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

        // Store segments as JSON for timestamp display later
        var metadata: [String: String] = ["model": "mlx_whisper"]
        if let segments = response.segments,
           let segmentsData = try? JSONEncoder().encode(segments),
           let segmentsJson = String(data: segmentsData, encoding: .utf8) {
            metadata["segments"] = segmentsJson
            metadata["input_file_id"] = fileId  // Store file ID so we can link to video playback
        }

        try updateConversionStorage(
            id: conversion.id,
            outputText: response.text,
            metadata: metadata
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

        // Extract text from file (this shows progress in logs)
        print("📄 Extracting text from: \(file.name)")
        let extractedText = try fileExtraction.extractText(from: file.absolutePath)
        print("✅ Extracted \(extractedText.count) characters")

        // Summarize with LLM using streaming for live preview
        let systemPrompt = "You are a helpful assistant that summarizes documents concisely."
        let userPrompt = "Summarize the following document:\n\n\(extractedText)"

        print("🤖 Generating summary...")
        let summary = try await mlx.prompt(userPrompt, systemPrompt: systemPrompt)

        try updateConversionStorage(
            id: conversion.id,
            outputText: summary,
            metadata: ["model": "mlx", "extracted_length": String(extractedText.count)]
        )

        print("✅ Summary complete: \(summary.count) characters")
    }

    // MARK: - Storage Helpers

    private func updateConversionStorage(
        id: String,
        outputText: String? = nil,
        outputFileId: String? = nil,
        metadata: [String: String]? = nil
    ) throws {
        let result = storage.updateConversion(
            id: id,
            outputText: outputText,
            outputFileId: outputFileId,
            metadata: metadata
        )

        if case .err(let error) = result {
            print("❌ Failed to update conversion \(id) in storage: \(error)")
            throw ConversionError.storageFailed(error)
        }

        print("✅ Conversion \(id) updated in storage")
    }

    // MARK: - File Management

    func importFile(url: URL) async throws -> String {
        let filename = url.lastPathComponent

        // Request security-scoped access for files from file picker
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard accessGranted else {
            print("❌ Failed to access security-scoped resource: \(url.path)")
            throw ConversionError.fileAccessDenied
        }

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
        // Write to file_system/storage directory (where FileStorage expects files)
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let storageDir = documentsURL
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("file_system", isDirectory: true)
            .appendingPathComponent("storage", isDirectory: true)
            .appendingPathComponent("conversions", isDirectory: true)

        try FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)

        let fileURL = storageDir.appendingPathComponent(filename)
        try data.write(to: fileURL)

        // Use relative path for FileStorage (relative to storage/)
        let relativePath = "conversions/\(filename)"

        // Create file record with relative path
        let result = fileStorage.createFile(
            name: filename,
            path: relativePath,
            mimeType: mimeType,
            sizeBytes: Int64(data.count)
        )

        switch result {
        case .ok(let file):
            print("✅ Saved file: \(filename) at relative path: \(relativePath)")
            print("   Absolute path: \(file.absolutePath)")
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
        switch result {
        case .ok(let conversions):
            print("✅ ConversionService.getAllConversions: Found \(conversions.count) conversions")
            return conversions
        case .err(let error):
            print("❌ ConversionService.getAllConversions failed: \(error)")
            return []
        }
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
    case completed(String, chatId: String?)
}

enum ConversionError: LocalizedError {
    case missingInput
    case storageFailed(Error)
    case fileNotFound
    case fileAccessDenied
    case imageConversionFailed
    case streamingNotSupported(ConversionType)
    case serviceNotAvailable(String)

    var errorDescription: String? {
        switch self {
        case .missingInput:
            return "Missing required input"
        case .storageFailed(let error):
            return "Storage failed: \(error.localizedDescription)"
        case .fileNotFound:
            return "Input file not found"
        case .serviceNotAvailable(let message):
            return message
        case .fileAccessDenied:
            return "Cannot access the selected file. Please try selecting it again."
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
