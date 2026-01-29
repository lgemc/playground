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
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    // Load the PDF document
    final bytes = await file.readAsBytes();
    final document = pdf_lib.PdfDocument(inputBytes: bytes);

    try {
      // Extract text from all pages
      final buffer = StringBuffer();

      for (int i = 0; i < document.pages.count; i++) {
        // Extract text line by line from each page
        final textLines = pdf_lib.PdfTextExtractor(document)
            .extractTextLines(startPageIndex: i, endPageIndex: i);

        for (final line in textLines) {
          buffer.writeln(line.text);
        }

        if (i < document.pages.count - 1) {
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
