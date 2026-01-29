/// Base interface for text extraction from files
abstract class TextExtractor {
  /// Extract text from a file at the given path
  Future<String> extractText(String filePath);

  /// Check if this extractor can handle the given file type
  bool canHandle(String filePath, String? mimeType);
}
