import 'dart:convert';
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
    // Support PDF files
    if (file.mimeType?.contains('pdf') == true ||
        file.name.toLowerCase().endsWith('.pdf')) {
      return true;
    }

    // Support video/audio files (transcript check happens in dialog)
    return file.isVideo || file.isAudio;
  }

  @override
  Future<String> generate(FileItem file) async {
    String text;

    // Check if file has a transcript derivative
    final derivatives =
        await FileSystemStorage.instance.getDerivatives(file.id);
    final transcriptDerivative = derivatives
        .where((d) => d.type == 'transcript' && d.status == 'completed')
        .firstOrNull;

    if (transcriptDerivative != null) {
      // Read transcript from derivative file
      text = await _readTranscript(transcriptDerivative.derivativePath);
    } else if (file.isVideo || file.isAudio) {
      // Video/audio without transcript
      throw Exception(
          'No completed transcript found. Generate a transcript first.');
    } else {
      // Fallback to extracting text from the file itself (PDF)
      final filePath = FileSystemStorage.instance.getAbsolutePath(file);
      text = await _extractText(filePath, file.name);
    }

    if (text.isEmpty) {
      throw Exception('Failed to extract text from file');
    }

    // Generate summary using streaming
    final buffer = StringBuffer();
    await for (final chunk in _summaryService.summarizeStream(text)) {
      buffer.write(chunk);
    }

    final rawSummary = buffer.toString();
    print('[SummaryGenerator] Raw summary length: ${rawSummary.length}');

    // Extract summary from structured response
    final summary = _extractSummary(rawSummary);
    print('[SummaryGenerator] Extracted summary length: ${summary.length}');

    return summary;
  }

  /// Read transcript text from derivative file
  Future<String> _readTranscript(String derivativePath) async {
    print('[SummaryGenerator] Reading transcript from: $derivativePath');
    final file = File(derivativePath);
    if (!await file.exists()) {
      throw FileSystemException('Transcript file not found', derivativePath);
    }

    final content = await file.readAsString();
    print('[SummaryGenerator] Transcript content length: ${content.length}');

    // Transcript is stored as JSON with segments
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      print('[SummaryGenerator] JSON keys: ${json.keys.toList()}');

      // Extract text from segments
      final segments = json['segments'] as List<dynamic>?;
      if (segments == null || segments.isEmpty) {
        throw StateError('Transcript has no segments');
      }

      // Concatenate all segment texts
      final text = segments
          .map((seg) => (seg as Map<String, dynamic>)['text'] as String?)
          .where((text) => text != null && text.isNotEmpty)
          .join(' ')
          .trim();

      print('[SummaryGenerator] Extracted text length: ${text.length}');
      return text;
    } catch (e) {
      print(
          '[SummaryGenerator] Failed to parse JSON, treating as plain text: $e');
      // If not JSON, treat as plain text
      return content;
    }
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

  /// Extract summary from structured response
  String _extractSummary(String response) {
    // Extract content after "SUMMARY:" marker
    final summaryMatch =
        RegExp(r'SUMMARY:\s*(.+)', dotAll: true).firstMatch(response);

    if (summaryMatch != null) {
      return summaryMatch.group(1)?.trim() ?? response.trim();
    }

    // Fallback: return the whole response if no marker found
    return response.trim();
  }
}
