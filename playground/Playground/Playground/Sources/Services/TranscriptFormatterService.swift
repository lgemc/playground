import Foundation

/// Service to format plain transcripts into structured markdown with titles and sections
actor TranscriptFormatterService {
    static let shared = TranscriptFormatterService()

    private let autocompletion = AutocompletionService.shared

    private init() {}

    /// Formats a plain transcript into structured markdown with titles and sections
    func formatTranscript(_ text: String) async throws -> String {
        let systemPrompt = """
You are a transcript formatter. Your job is to take a plain text transcript and organize it into a well-structured markdown document.

Add appropriate headings (##, ###) to divide the content into logical sections based on topic changes.
Add **bold** for emphasis on key points.
Use bullet points (-) for lists when appropriate.
Keep all the original content - don't summarize or remove anything.
Make it readable and well-organized.

Output ONLY the formatted markdown. No explanations, no preamble.
"""

        let userPrompt = """
Format this transcript into structured markdown with titles and sections:

\(text)
"""

        let resultBuffer = StringBuffer()

        for try await chunk in autocompletion.promptStream(
            userPrompt,
            systemPrompt: systemPrompt,
            temperature: 0.3,
            maxTokens: 4000
        ) {
            resultBuffer.append(chunk)
        }

        let formatted = resultBuffer.toString().trimmingCharacters(in: .whitespacesAndNewlines)

        // Fallback if formatting failed
        if formatted.isEmpty {
            return text
        }

        return formatted
    }
}

/// Simple string buffer for collecting streaming chunks
private class StringBuffer {
    private var buffer = ""

    func append(_ chunk: String) {
        buffer += chunk
    }

    func toString() -> String {
        return buffer
    }
}
