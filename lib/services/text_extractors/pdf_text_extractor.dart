import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdf_lib;
import 'text_extractor.dart';

/// Extract text from PDF files using Syncfusion PDF library
class PdfTextExtractor implements TextExtractor {
  @override
  bool canHandle(String filePath, String? mimeType) {
    return filePath.toLowerCase().endsWith('.pdf') ||
        mimeType?.contains('pdf') == true;
  }

  @override
  Future<String> extractText(String filePath) async {
    return extractWithLimit(filePath, null);
  }

  /// Extract text with optional page limit
  Future<String> extractWithLimit(String filePath, int? maxPages) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    // Load the PDF document
    final bytes = await file.readAsBytes();
    final document = pdf_lib.PdfDocument(inputBytes: bytes);

    try {
      // Extract text from pages (limited if maxPages specified)
      final buffer = StringBuffer();
      final pageCount = maxPages != null
          ? (maxPages < document.pages.count ? maxPages : document.pages.count)
          : document.pages.count;

      // Extract text from specified pages with layout preservation
      final extractor = pdf_lib.PdfTextExtractor(document);

      for (int i = 0; i < pageCount; i++) {
        // Extract text with layout enabled to preserve word spacing
        final pageText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
          layoutText: true,
        );

        buffer.writeln(pageText);

        if (i < pageCount - 1) {
          buffer.writeln();
        }
      }

      return buffer.toString().trim();
    } finally {
      // Always dispose the document
      document.dispose();
    }
  }

}
