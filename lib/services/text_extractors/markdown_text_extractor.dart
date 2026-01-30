import 'dart:io';
import 'text_extractor.dart';

/// Extract text from Markdown files with optional line limit
class MarkdownTextExtractor implements TextExtractor {
  @override
  bool canHandle(String filePath, String? mimeType) {
    return filePath.toLowerCase().endsWith('.md') ||
        mimeType?.contains('markdown') == true ||
        mimeType?.contains('text/markdown') == true;
  }

  @override
  Future<String> extractText(String filePath) async {
    return extractWithLimit(filePath, null);
  }

  /// Extract text with optional line limit
  Future<String> extractWithLimit(String filePath, int? maxLines) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    final lines = await file.readAsLines();
    final limitedLines = maxLines != null && lines.length > maxLines
        ? lines.sublist(0, maxLines)
        : lines;

    return limitedLines.join('\n').trim();
  }

  /// Detect if markdown has an explicit title (# heading at the start)
  static String? detectExplicitTitle(String content) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Check for # heading (level 1 heading)
      if (trimmed.startsWith('# ')) {
        return trimmed.substring(2).trim();
      }

      // If we hit non-empty content that's not a heading, stop looking
      if (!trimmed.startsWith('#')) {
        break;
      }
    }
    return null;
  }
}