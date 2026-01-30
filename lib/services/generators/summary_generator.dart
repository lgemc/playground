import 'dart:io';
import 'package:flutter/material.dart';
import '../../apps/file_system/models/file_item.dart';
import '../../apps/file_system/services/file_system_storage.dart';
import '../summary_service.dart';
import '../text_extractors/pdf_text_extractor.dart';
import '../text_extractors/text_extractor.dart';
import 'derivative_generator.dart';

class SummaryGenerator extends DerivativeGenerator {
  final _summaryService = SummaryService.instance;

  // Registry of text extractors
  final List<TextExtractor> _extractors = [
    PdfTextExtractor(),
  ];

  @override
  String get type => 'summary';

  @override
  String get displayName => 'Summary';

  @override
  IconData get icon => Icons.summarize;

  @override
  bool canProcess(FileItem file) {
    // Only support PDF files for now
    return file.mimeType?.contains('pdf') == true ||
        file.name.toLowerCase().endsWith('.pdf');
  }

  @override
  Future<String> generate(FileItem file) async {
    // Get full file path
    final filePath = FileSystemStorage.instance.getAbsolutePath(file);

    // Extract text from the file
    final text = await _extractText(filePath, file.name);
    if (text.isEmpty) {
      throw Exception('Failed to extract text from file');
    }

    // Generate summary using streaming
    final buffer = StringBuffer();
    await for (final chunk in _summaryService.summarizeStream(text)) {
      buffer.write(chunk);
    }

    return buffer.toString();
  }

  /// Extract text from a file using the appropriate extractor
  Future<String> _extractText(String filePath, String fileName) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    // Find a suitable extractor
    for (final extractor in _extractors) {
      if (extractor.canHandle(filePath, null)) {
        return await extractor.extractText(filePath);
      }
    }

    throw UnsupportedError('No text extractor available for: $fileName');
  }
}
