import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../apps/summaries/models/summary.dart';
import '../apps/summaries/services/summary_storage.dart';
import '../services/logger.dart';
import '../services/queue_message.dart';
import '../services/queue_service.dart';
import '../services/summary_service.dart';
import '../services/text_extractors/pdf_text_extractor.dart';
import '../services/text_extractors/text_extractor.dart';

/// Service that listens to the summary queue and processes summary tasks
class SummarizerService {
  static SummarizerService? _instance;
  static SummarizerService get instance => _instance ??= SummarizerService._();

  SummarizerService._();

  final _queueService = QueueService.instance;
  final _summaryService = SummaryService.instance;
  final _storage = SummaryStorage.instance;
  final _logger = Logger(appId: 'summarizer', appName: 'Summarizer Service');

  String? _subscriptionId;

  // Registry of text extractors
  final List<TextExtractor> _extractors = [
    PdfTextExtractor(),
    // Future extractors: MarkdownTextExtractor(), TxtTextExtractor(), etc.
  ];

  /// Initialize and start listening to the summary queue
  Future<void> init() async {
    if (_subscriptionId != null) return;

    await _storage.init();
    await _queueService.init();

    // Subscribe to the summary queue
    _subscriptionId = _queueService.subscribe(
      id: 'summarizer_service',
      queueId: 'summary-processor',
      callback: _processSummaryTask,
      name: 'Summarizer Service',
    );

    _logger.log('Summarizer service initialized', severity: LogSeverity.info);
  }

  /// Process a summary task from the queue
  Future<bool> _processSummaryTask(QueueMessage message) async {
    try {
      final summaryId = message.payload['summaryId'] as String?;
      if (summaryId == null) {
        _logger.log('Summary task missing summaryId', severity: LogSeverity.error);
        return false;
      }

      _logger.log('Processing summary task: $summaryId', severity: LogSeverity.info);

      // Load the summary from storage
      final summary = await _storage.get(summaryId);
      if (summary == null) {
        _logger.log('Summary not found: $summaryId', severity: LogSeverity.error);
        return false;
      }

      // Update status to processing
      await _storage.update(summary.copyWith(
        status: SummaryStatus.processing,
      ));

      // Extract text from the file
      final appDir = await getApplicationDocumentsDirectory();
      final fullPath = '${appDir.path}/data/file_system/storage/${summary.filePath}';

      _logger.log('Extracting text from: $fullPath', severity: LogSeverity.info);

      final text = await _extractText(fullPath, summary.fileName);
      if (text.isEmpty) {
        await _storage.update(summary.copyWith(
          status: SummaryStatus.failed,
          errorMessage: 'Failed to extract text from file',
        ));
        _logger.log('No text extracted from file', severity: LogSeverity.error);
        return false;
      }

      _logger.log('Extracted ${text.length} characters', severity: LogSeverity.info);

      // Generate summary using streaming
      final buffer = StringBuffer();
      await for (final chunk in _summaryService.summarizeStream(text)) {
        buffer.write(chunk);

        // Update the summary in storage with streaming content
        await _storage.update(summary.copyWith(
          summaryText: buffer.toString(),
          status: SummaryStatus.processing,
        ));
      }

      final summaryText = buffer.toString();

      // Update status to completed
      await _storage.update(summary.copyWith(
        summaryText: summaryText,
        status: SummaryStatus.completed,
        completedAt: DateTime.now(),
      ));

      _logger.log('Summary completed: $summaryId', severity: LogSeverity.info);
      return true;
    } catch (e, stackTrace) {
      _logger.log('Error processing summary: $e\n$stackTrace',
          severity: LogSeverity.error);

      // Try to update summary with error
      try {
        final summaryId = message.payload['summaryId'] as String?;
        if (summaryId != null) {
          final summary = await _storage.get(summaryId);
          if (summary != null) {
            await _storage.update(summary.copyWith(
              status: SummaryStatus.failed,
              errorMessage: e.toString(),
            ));
          }
        }
      } catch (_) {
        // Ignore errors when updating error state
      }

      return false;
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

  /// Stop listening to the queue
  Future<void> dispose() async {
    if (_subscriptionId != null) {
      _queueService.unsubscribe(_subscriptionId!);
      _subscriptionId = null;
    }
    _logger.log('Summarizer service disposed', severity: LogSeverity.info);
  }

  /// Reset for testing
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }
}
