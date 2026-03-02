import Foundation

/// Service for generating vocabulary definitions using LLM
class VocabularyDefinitionService {
    static let shared = VocabularyDefinitionService()

    private init() {}

    // MARK: - Definition Generation

    /// Generate definition and examples for a word
    /// - Parameters:
    ///   - word: The word to define
    ///   - sourceLanguage: Source language (optional)
    ///   - targetLanguage: Target language (optional)
    ///   - exampleCount: Number of example sentences to generate
    /// - Returns: Tuple of (meaning, examples)
    func generateDefinition(
        word: String,
        sourceLanguage: String? = nil,
        targetLanguage: String? = nil,
        exampleCount: Int = 5
    ) async throws -> (meaning: String, examples: [String]) {
        let systemPrompt = buildSystemPrompt(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            exampleCount: exampleCount
        )

        // Use MLX for local on-device inference
        let messages = [
            AutocompletionService.ChatMessage(role: "system", content: systemPrompt),
            AutocompletionService.ChatMessage(role: "user", content: "Define the word: \"\(word)\"")
        ]

        // Use streaming to collect the full response
        var fullResponse = ""
        for try await chunk in MLXChatService.shared.completeStream(
            messages: messages,
            temperature: 0.3,
            maxTokens: 500
        ) {
            fullResponse += chunk
        }

        // Parse the response
        return try parseDefinitionResponse(fullResponse)
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt(
        sourceLanguage: String?,
        targetLanguage: String?,
        exampleCount: Int
    ) -> String {
        var prompt = """
        You are a dictionary assistant that provides clear definitions and example sentences.

        Use this EXACT format (no other text):

        MEANING: <your definition here>

        EXAMPLES:
        """

        // Add numbered example placeholders
        for i in 1...exampleCount {
            prompt += "\n\(i). <example sentence \(i)>"
        }

        // Add language context if provided
        if let source = sourceLanguage, let target = targetLanguage {
            prompt += """


            Provide the meaning in \(target) for a \(source) word.
            Examples should demonstrate usage in \(source).
            """
        }

        prompt += """


        Rules:
        - Keep the definition concise (1-2 sentences)
        - Make examples practical and varied
        - Use simple, clear language
        - DO NOT include any text outside the MEANING and EXAMPLES sections
        """

        return prompt
    }

    // MARK: - Response Parsing

    private func parseDefinitionResponse(_ response: String) throws -> (meaning: String, examples: [String]) {
        // Extract meaning using regex
        let meaningPattern = #"MEANING:\s*(.+?)(?=\n\nEXAMPLES:|\n\n|$)"#
        guard let meaningRegex = try? NSRegularExpression(pattern: meaningPattern, options: [.dotMatchesLineSeparators]),
              let meaningMatch = meaningRegex.firstMatch(
                in: response,
                range: NSRange(response.startIndex..., in: response)
              ),
              let meaningRange = Range(meaningMatch.range(at: 1), in: response) else {
            // Fallback: try to extract from end of response
            return (meaning: extractMeaningFallback(response), examples: extractExamplesFallback(response))
        }

        let meaning = String(response[meaningRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract examples using regex
        let examplesPattern = #"(\d+)\.\s*(.+?)(?=\n\d+\.|\n*$)"#
        let examplesRegex = try NSRegularExpression(pattern: examplesPattern, options: [.dotMatchesLineSeparators])
        let examplesMatches = examplesRegex.matches(
            in: response,
            range: NSRange(response.startIndex..., in: response)
        )

        var examples: [String] = []
        for match in examplesMatches {
            if let exampleRange = Range(match.range(at: 2), in: response) {
                let example = String(response[exampleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !example.isEmpty {
                    examples.append(example)
                }
            }
        }

        // If no examples found, try fallback
        if examples.isEmpty {
            examples = extractExamplesFallback(response)
        }

        return (meaning: meaning, examples: examples)
    }

    // MARK: - Fallback Extraction

    /// Fallback extraction for reasoning models that output differently
    private func extractMeaningFallback(_ response: String) -> String {
        let lines = response.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        // Look for lines after "MEANING:"
        if let meaningIndex = lines.firstIndex(where: { $0.starts(with: "MEANING:") }) {
            let meaningLine = lines[meaningIndex]
            if let colonIndex = meaningLine.firstIndex(of: ":") {
                let meaning = String(meaningLine[meaningLine.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !meaning.isEmpty {
                    return meaning
                }
            }

            // Check next line
            if meaningIndex + 1 < lines.count {
                let nextLine = lines[meaningIndex + 1]
                if !nextLine.starts(with: "EXAMPLES:") && !nextLine.isEmpty {
                    return nextLine
                }
            }
        }

        // Last resort: work backwards from end, skip reasoning artifacts
        for line in lines.reversed() {
            if line.isEmpty || line.hasSuffix("?") || line.lowercased().contains("let's") || line.count < 10 {
                continue
            }
            if !line.starts(with: "MEANING:") && !line.starts(with: "EXAMPLES:") && !line.starts(with: #/\d+\./#) {
                return line
            }
        }

        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractExamplesFallback(_ response: String) -> [String] {
        let lines = response.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var examples: [String] = []
        var inExamplesSection = false

        for line in lines {
            if line.starts(with: "EXAMPLES:") {
                inExamplesSection = true
                continue
            }

            if inExamplesSection && !line.isEmpty {
                // Remove number prefix if present
                let cleaned = line.replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
                if !cleaned.isEmpty && cleaned != line.lowercased() {
                    examples.append(cleaned)
                }
            }
        }

        return examples
    }

    // MARK: - Streaming Generation

    /// Generate definition with streaming updates
    /// - Parameters:
    ///   - word: The word to define
    ///   - onUpdate: Callback with partial response
    /// - Returns: Final (meaning, examples)
    func generateDefinitionStreaming(
        word: String,
        sourceLanguage: String? = nil,
        targetLanguage: String? = nil,
        exampleCount: Int = 5,
        onUpdate: @escaping (String) -> Void
    ) async throws -> (meaning: String, examples: [String]) {
        let systemPrompt = buildSystemPrompt(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            exampleCount: exampleCount
        )

        // Use MLX for local on-device inference
        let messages = [
            AutocompletionService.ChatMessage(role: "system", content: systemPrompt),
            AutocompletionService.ChatMessage(role: "user", content: "Define the word: \"\(word)\"")
        ]

        var fullResponse = ""
        for try await chunk in MLXChatService.shared.completeStream(
            messages: messages,
            temperature: 0.3,
            maxTokens: 500
        ) {
            fullResponse += chunk
            onUpdate(fullResponse)
        }

        return try parseDefinitionResponse(fullResponse)
    }
}

// MARK: - Errors

enum VocabularyDefinitionError: Error, LocalizedError {
    case notConfigured
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "LLM service is not configured. Please set llm.base_url in settings."
        case .invalidResponse:
            return "Failed to parse definition response"
        }
    }
}
