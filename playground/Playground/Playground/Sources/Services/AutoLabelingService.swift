import Foundation

/// Service that automatically assigns labels to conversions using LLM
@MainActor
class AutoLabelingService {
    static let shared = AutoLabelingService()

    private let mlx = MLXService.shared
    private let storage = ConversionStorage.shared

    private init() {}

    /// Automatically assign a label to a conversion based on its content
    func autoLabel(conversion: Conversion) async {
        print("🏷️ Auto-labeling conversion: \(conversion.type.displayName)")

        // Get all existing labels
        let existingLabels: [String]
        switch storage.getAllLabels() {
        case .ok(let labels):
            existingLabels = labels
        case .err:
            existingLabels = []
        }

        // If no existing labels, don't auto-label
        guard !existingLabels.isEmpty else {
            print("⚠️ No existing labels to choose from, skipping auto-label")
            return
        }

        // Build context about the conversion with intelligent detection
        var context = ""
        var conversionHint = ""

        // Detect vocabulary-related queries
        if let inputText = conversion.inputText, !inputText.isEmpty {
            let lowerInput = inputText.lowercased()

            // Check for vocabulary indicators
            if lowerInput.contains("meaning") ||
               lowerInput.contains("define") ||
               lowerInput.contains("definition") ||
               lowerInput.contains("what is") ||
               lowerInput.contains("what does") ||
               lowerInput.contains("translate") ||
               (lowerInput.split(separator: " ").count <= 3 && conversion.type == .textToText) {
                conversionHint = "🔍 This appears to be a vocabulary/word definition query\n"
            }

            let preview = String(inputText.prefix(200))
            context += "User Question: \(preview)\n"
        }

        context += "Conversion Type: \(conversion.type.displayName)\n"

        if let outputText = conversion.outputText, !outputText.isEmpty {
            let preview = String(outputText.prefix(200))
            context += "Answer Preview: \(preview)\n"
        }

        // Create numbered list of labels for the LLM to choose from
        var labelsList = ""
        for (index, label) in existingLabels.enumerated() {
            labelsList += "\(index + 1). \(label)\n"
        }

        let prompt = """
        You are selecting the BEST category label for a user's conversion.

        LABELING RULES:
        - If user asks for word meanings, definitions, or translations → choose "Vocabulary" label if available
        - If user is asking about a specific word or short phrase meaning → choose "Vocabulary" label if available
        - If user is working with code or programming → choose "Code" label if available
        - If user is taking notes or summarizing meetings → choose "Work" or "Meeting Notes" if available
        - If user is doing personal journaling or notes → choose "Personal" label if available

        Available labels:
        \(labelsList)
        \(conversionHint)
        Conversion details:
        \(context)

        Select the BEST matching label by outputting ONLY its number.
        Output just the number:
        """

        do {
            // Use MLX to select label
            var responseBuffer = ""
            let stream = mlx.promptStream(prompt)

            for try await chunk in stream {
                responseBuffer += chunk
            }

            // Extract the number
            let cleaned = responseBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

            // Try to parse the number
            if let selectedIndex = Int(cleaned), selectedIndex > 0, selectedIndex <= existingLabels.count {
                let selectedLabel = existingLabels[selectedIndex - 1]

                let result = storage.updateLabel(id: conversion.id, label: selectedLabel)
                if case .ok = result {
                    print("✅ Auto-labeled conversion as: \(selectedLabel) (option \(selectedIndex))")
                } else {
                    print("❌ Failed to save auto-label")
                }
            } else {
                print("⚠️ LLM returned invalid selection: '\(cleaned)'")
            }

        } catch {
            print("❌ Auto-labeling failed: \(error)")
        }
    }
}
