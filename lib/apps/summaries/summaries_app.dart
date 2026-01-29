import 'package:flutter/material.dart';
import '../../core/app_bus.dart';
import '../../core/app_event.dart';
import '../../core/sub_app.dart';
import '../../services/queue_service.dart';
import '../../services/share_content.dart';
import 'screens/summaries_screen.dart';
import 'services/summary_storage.dart';

class SummariesApp extends SubApp {
  @override
  String get id => 'summaries';

  @override
  String get name => 'Summaries';

  @override
  IconData get icon => Icons.summarize;

  @override
  Color get themeColor => Colors.deepPurple;

  @override
  void onInit() {
    // Initialize storage
    SummaryStorage.instance.init();
  }

  @override
  Widget build(BuildContext context) {
    return const SummariesScreen();
  }

  @override
  List<ShareContentType> get acceptedShareTypes => [
    ShareContentType.file,
  ];

  @override
  Future<void> onReceiveShare(ShareContent content) async {
    if (content.type != ShareContentType.file) return;

    final fileId = content.data['fileId'] as String?;
    final fileName = content.data['name'] as String? ?? 'Unknown';
    final filePath = content.data['path'] as String? ?? '';
    final mimeType = content.data['mimeType'] as String?;

    if (fileId == null || fileId.isEmpty) {
      throw ArgumentError('File ID is required for summary creation');
    }

    // Only support PDF files for now
    if (mimeType?.contains('pdf') != true && !fileName.toLowerCase().endsWith('.pdf')) {
      throw UnsupportedError('Only PDF files are supported for summarization');
    }

    // Create a pending summary
    final summary = await SummaryStorage.instance.create(
      fileId: fileId,
      fileName: fileName,
      filePath: filePath,
    );

    // Enqueue the summary task
    await QueueService.instance.enqueue(
      queueId: 'summary-processor',
      eventType: 'summary.create',
      appId: id,
      payload: {
        'summaryId': summary.id,
        'fileId': fileId,
        'fileName': fileName,
        'filePath': filePath,
      },
    );

    // Emit event
    await AppBus.instance.emit(AppEvent.create(
      type: 'summary.created',
      appId: id,
      metadata: {
        'summaryId': summary.id,
        'fileId': fileId,
      },
    ));
  }
}
