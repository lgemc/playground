import SwiftUI

/// Lightweight custom markdown renderer optimized for chat messages
/// Supports: **bold**, *italic*, `inline code`, ```code blocks```, [links](url), and lists
struct MarkdownText: View {
    let content: String
    let textColor: Color

    // Cache parsed blocks to avoid re-parsing on every render
    private let blocks: [AnyView]

    init(content: String, textColor: Color) {
        self.content = content
        self.textColor = textColor
        self.blocks = Self.parseBlocks(content: content, textColor: textColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                block
            }
        }
    }

    // MARK: - Block Level Parsing

    private static func parseBlocks(content: String, textColor: Color) -> [AnyView] {
        var blocks: [AnyView] = []
        var currentText = ""
        var inCodeBlock = false
        var codeBlockContent = ""
        var codeBlockLanguage = ""

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Code block detection
            if trimmedLine.hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    if !currentText.isEmpty {
                        blocks.append(AnyView(renderInlineMarkdown(currentText, textColor: textColor)))
                        currentText = ""
                    }
                    blocks.append(AnyView(renderCodeBlock(codeBlockContent, language: codeBlockLanguage)))
                    codeBlockContent = ""
                    codeBlockLanguage = ""
                    inCodeBlock = false
                } else {
                    // Start code block
                    if !currentText.isEmpty {
                        blocks.append(AnyView(renderInlineMarkdown(currentText, textColor: textColor)))
                        currentText = ""
                    }
                    codeBlockLanguage = String(trimmedLine.dropFirst(3))
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                if !codeBlockContent.isEmpty {
                    codeBlockContent += "\n"
                }
                codeBlockContent += line
            } else {
                // Regular text
                if !currentText.isEmpty {
                    currentText += "\n"
                }
                currentText += line
            }
        }

        // Add any remaining text
        if !currentText.isEmpty {
            blocks.append(AnyView(renderInlineMarkdown(currentText, textColor: textColor)))
        }

        // Handle unclosed code block
        if inCodeBlock && !codeBlockContent.isEmpty {
            blocks.append(AnyView(renderCodeBlock(codeBlockContent, language: codeBlockLanguage)))
        }

        return blocks
    }

    // MARK: - Inline Rendering

    private static func renderInlineMarkdown(_ text: String, textColor: Color) -> some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)

                // Headings: # H1, ## H2, ### H3, etc.
                if trimmedLine.hasPrefix("#") {
                    if let headingData = parseHeading(String(line)) {
                        parseInlineText(headingData.text, textColor: textColor)
                            .font(headingData.font)
                            .bold()
                            .padding(.top, headingData.level == 1 ? 8 : 4)
                            .padding(.bottom, 2)
                    } else {
                        parseInlineText(String(line), textColor: textColor)
                    }
                } else if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") || trimmedLine.hasPrefix("+ ") {
                    // Bullet list
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundColor(textColor)
                        parseInlineText(String(line.dropFirst(2)), textColor: textColor)
                    }
                } else if let numberMatch = trimmedLine.firstMatch(of: /^(\d+)\.\s+(.*)/) {
                    // Numbered list
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(numberMatch.1).")
                            .foregroundColor(textColor)
                        parseInlineText(String(numberMatch.2), textColor: textColor)
                    }
                } else {
                    parseInlineText(String(line), textColor: textColor)
                }
            }
        }
    }

    private static func parseInlineText(_ text: String, textColor: Color) -> Text {
        var result = Text("")
        var currentText = ""
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]

            // Check for markdown patterns
            if char == "*" || char == "_" {
                let remaining = String(text[index...])

                // Bold: **text** or __text__
                if remaining.hasPrefix("**") || remaining.hasPrefix("__") {
                    if let endRange = findClosingPattern(in: remaining, pattern: String(repeating: String(char), count: 2), startOffset: 2) {
                        if !currentText.isEmpty {
                            result = result + Text(currentText).foregroundColor(textColor)
                            currentText = ""
                        }
                        let boldText = String(remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange])
                        result = result + Text(boldText).bold().foregroundColor(textColor)
                        index = text.index(index, offsetBy: boldText.count + 4)
                        continue
                    }
                }
                // Italic: *text* or _text_
                else if let endRange = findClosingPattern(in: remaining, pattern: String(char), startOffset: 1) {
                    if !currentText.isEmpty {
                        result = result + Text(currentText).foregroundColor(textColor)
                        currentText = ""
                    }
                    let italicText = String(remaining[remaining.index(remaining.startIndex, offsetBy: 1)..<endRange])
                    result = result + Text(italicText).italic().foregroundColor(textColor)
                    index = text.index(index, offsetBy: italicText.count + 2)
                    continue
                }
            }
            // Inline code: `text`
            else if char == "`" {
                let remaining = String(text[index...])
                if let endRange = findClosingPattern(in: remaining, pattern: "`", startOffset: 1) {
                    if !currentText.isEmpty {
                        result = result + Text(currentText).foregroundColor(textColor)
                        currentText = ""
                    }
                    let codeText = String(remaining[remaining.index(remaining.startIndex, offsetBy: 1)..<endRange])
                    result = result + Text(codeText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                    index = text.index(index, offsetBy: codeText.count + 2)
                    continue
                }
            }
            // Links: [text](url)
            else if char == "[" {
                if let linkData = parseLink(from: String(text[index...])) {
                    if !currentText.isEmpty {
                        result = result + Text(currentText).foregroundColor(textColor)
                        currentText = ""
                    }
                    result = result + Text(linkData.text)
                        .foregroundColor(.blue)
                        .underline()
                    index = text.index(index, offsetBy: linkData.totalLength)
                    continue
                }
            }

            currentText.append(char)
            index = text.index(after: index)
        }

        if !currentText.isEmpty {
            result = result + Text(currentText).foregroundColor(textColor)
        }

        return result
    }

    // MARK: - Code Block Rendering

    private static func renderCodeBlock(_ code: String, language: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !language.isEmpty {
                Text(language)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(12)
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }

    // MARK: - Helper Functions

    private static func findClosingPattern(in text: String, pattern: String, startOffset: Int) -> String.Index? {
        guard startOffset < text.count else { return nil }

        let searchStart = text.index(text.startIndex, offsetBy: startOffset)
        guard let range = text[searchStart...].range(of: pattern) else { return nil }

        return range.lowerBound
    }

    private static func parseLink(from text: String) -> (text: String, url: String, totalLength: Int)? {
        // Match [text](url)
        guard let match = text.firstMatch(of: /\[([^\]]+)\]\(([^\)]+)\)/) else { return nil }

        let linkText = String(match.1)
        let url = String(match.2)
        let totalLength = match.0.count

        return (linkText, url, totalLength)
    }

    private static func parseHeading(_ text: String) -> (level: Int, text: String, font: Font)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        var level = 0

        // Count leading # symbols
        for char in trimmed {
            if char == "#" {
                level += 1
            } else {
                break
            }
        }

        // Must have at least one # and a space after
        guard level > 0, level <= 6 else { return nil }

        let afterHashes = trimmed.dropFirst(level)
        guard afterHashes.first == " " else { return nil }

        let headingText = afterHashes.trimmingCharacters(in: .whitespaces)

        // Font sizes based on heading level
        let font: Font
        switch level {
        case 1: font = .title
        case 2: font = .title2
        case 3: font = .title3
        case 4: font = .headline
        case 5: font = .subheadline
        default: font = .body
        }

        return (level, headingText, font)
    }
}
