import 'package:flutter/material.dart';
import '../../apps/file_system/models/file_item.dart';
import '../../apps/file_system/services/file_system_storage.dart';
import '../auto_title_service.dart';
import '../text_extractors/markdown_text_extractor.dart';
import '../text_extractors/pdf_text_extractor.dart';
import 'derivative_generator.dart';

class AutoTitleGenerator extends DerivativeGenerator {
  final _autoTitleService = AutoTitleService.instance;
  final _markdownExtractor = MarkdownTextExtractor();
  final _pdfExtractor = PdfTextExtractor();

  @override
  String get type => 'auto_title';

  @override
  String get displayName => 'Auto-Generate Title';

  @override
  IconData get icon => Icons.drive_file_rename_outline;

  @override
  bool canProcess(FileItem file) {
    // Support .md and .pdf files
    return _markdownExtractor.canHandle(file.name, file.mimeType) ||
        _pdfExtractor.canHandle(file.name, file.mimeType);
  }

  @override
  Future<String> generate(FileItem file) async {
    // Get full file path
    final filePath = FileSystemStorage.instance.getAbsolutePath(file);

    // Determine file type and extract content
    String content;
    String fileType;

    if (_markdownExtractor.canHandle(file.name, file.mimeType)) {
      fileType = 'markdown';
      // Extract first 40 lines for markdown
      content = await _markdownExtractor.extractWithLimit(filePath, 40);
    } else if (_pdfExtractor.canHandle(file.name, file.mimeType)) {
      fileType = 'pdf';
      // Extract first 3 pages for PDF
      content = await _pdfExtractor.extractWithLimit(filePath, 3);
    } else {
      throw UnsupportedError('Unsupported file type: ${file.name}');
    }

    if (content.isEmpty) {
      throw Exception('Failed to extract content from file');
    }

    // Get original filename without extension
    final originalName = file.name.contains('.')
        ? file.name.substring(0, file.name.lastIndexOf('.'))
        : file.name;

    // Generate title using AI service
    final proposedTitle = await _autoTitleService.generateTitle(
      content: content,
      fileType: fileType,
      currentFilename: originalName,
    );

    // Format derivative content as markdown
    return '''# Proposed Title

$proposedTitle

## Original Filename
$originalName

## Applied
false

## Applied At
null
''';
  }
}
