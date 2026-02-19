import 'dart:convert';
import '../core/database/crdt_database.dart';
import '../apps/lms/shared/models/reviewable_item.dart';
import '../apps/lms/shared/models/activity.dart';
import '../apps/lms/shared/models/course.dart';
import '../apps/lms/shared/services/lms_crdt_storage_service.dart';
import '../apps/file_system/services/file_system_storage.dart';
import 'concept_extraction_service.dart';
import 'queue_consumer.dart';
import 'queue_message.dart';
import 'logger.dart';

/// Consumer that processes concept extraction tasks from the queue
/// Listens for events like 'activity.extract_concepts' and 'derivative.completed'
class ConceptExtractionConsumer extends QueueConsumer {
  @override
  String get id => 'concept_extraction_consumer';

  @override
  String get name => 'Concept Extraction Consumer';

  @override
  String get queueId => 'concept-extraction';

  final _extractionService = ConceptExtractionService.instance;
  final _logger = Logger(appId: 'concept_extraction', appName: 'Concept Extraction Service');

  @override
  Future<bool> processMessage(QueueMessage message) async {
    try {
      print('[ConceptExtraction] ===== Processing message =====');
      print('[ConceptExtraction] Event type: ${message.eventType}');
      print('[ConceptExtraction] Payload: ${message.payload}');

      final activityId = message.payload['activity_id'] as String?;
      final courseId = message.payload['course_id'] as String?;
      final moduleId = message.payload['module_id'] as String?;
      final subSectionId = message.payload['subsection_id'] as String?;

      if (activityId == null || courseId == null) {
        _logger.log(
          'Concept extraction missing required fields (activity_id or course_id)',
          severity: LogSeverity.error,
        );
        return false;
      }

      List<ReviewableItem> items = [];

      // Handle different event types
      if (message.eventType == 'activity.extract_concepts') {
        // Direct extraction request from activity
        _logger.log(
          'Extracting concepts from activity: $activityId',
          severity: LogSeverity.info,
        );

        // Try to get content from derivatives first (transcript or summary)
        final fileSystemStorage = FileSystemStorage.instance;

        // Get the activity to find the file
        final lmsStorage = LmsCrdtStorageService.instance;
        final course = await lmsStorage.getCourse(courseId);
        if (course == null) {
          _logger.log('Course not found: $courseId', severity: LogSeverity.error);
          return false;
        }

        final activity = _findActivity(course, activityId);
        if (activity == null) {
          _logger.log('Activity not found: $activityId', severity: LogSeverity.error);
          return false;
        }

        String? content;
        String? contentType;

        // Try to get content from activity file's derivatives
        if (activity is ResourceFileActivity && activity.fileId != null) {
          final fileId = activity.fileId!;

          // Get all derivatives for this file
          final derivatives = await fileSystemStorage.getDerivatives(fileId);

          // Try transcript first
          final transcriptDerivative = derivatives.where((d) => d.type == 'transcript').firstOrNull;
          if (transcriptDerivative != null) {
            try {
              content = await fileSystemStorage.getDerivativeContent(transcriptDerivative.id);
              contentType = 'transcript';
              print('[ConceptExtraction] Using transcript derivative');
            } catch (e) {
              print('[ConceptExtraction] Error reading transcript: $e');
            }
          }

          // Try summary if no transcript
          if (content == null) {
            final summaryDerivative = derivatives.where((d) => d.type == 'summary').firstOrNull;
            if (summaryDerivative != null) {
              try {
                content = await fileSystemStorage.getDerivativeContent(summaryDerivative.id);
                contentType = 'summary';
                print('[ConceptExtraction] Using summary derivative');
              } catch (e) {
                print('[ConceptExtraction] Error reading summary: $e');
              }
            }
          }

          // No derivatives available - skip direct file reading for now
          if (content == null) {
            print('[ConceptExtraction] No suitable derivatives found for file');
          }
        }

        if (content == null || content.isEmpty) {
          _logger.log(
            'No content available for extraction. Activity may not have a file or derivatives.',
            severity: LogSeverity.warning,
          );
          return true; // Not an error, just nothing to extract
        }

        if (contentType == 'transcript') {
          items = await _extractionService.extractFromTranscript(
            activityId: activityId,
            courseId: courseId,
            moduleId: moduleId,
            subSectionId: subSectionId,
            transcript: content,
          );
        } else {
          // Default to document extraction
          items = await _extractionService.extractFromDocument(
            activityId: activityId,
            courseId: courseId,
            moduleId: moduleId,
            subSectionId: subSectionId,
            documentText: content,
          );
        }
      } else if (message.eventType == 'derivative.completed') {
        // Derivative artifact completed (transcript, summary, etc.)
        final derivativeType = message.payload['derivative_type'] as String?;
        final content = message.payload['content'] as String?;

        if (content == null) {
          _logger.log(
            'Derivative completed but no content provided',
            severity: LogSeverity.warning,
          );
          return true; // Not an error, just nothing to do
        }

        _logger.log(
          'Extracting concepts from derivative: $derivativeType',
          severity: LogSeverity.info,
        );

        if (derivativeType == 'transcript') {
          items = await _extractionService.extractFromTranscript(
            activityId: activityId,
            courseId: courseId,
            moduleId: moduleId,
            subSectionId: subSectionId,
            transcript: content,
          );
        } else if (derivativeType == 'summary') {
          items = await _extractionService.extractFromDocument(
            activityId: activityId,
            courseId: courseId,
            moduleId: moduleId,
            subSectionId: subSectionId,
            documentText: content,
          );
        }
      }

      if (items.isEmpty) {
        _logger.log(
          'No concepts extracted from activity: $activityId',
          severity: LogSeverity.warning,
        );
        return true; // Not an error, just no concepts found
      }

      // Save reviewable items to database
      print('[ConceptExtraction] Saving ${items.length} concepts to database...');
      for (final item in items) {
        await _saveReviewableItem(item);
      }

      _logger.log(
        'Extracted and saved ${items.length} concepts from activity: $activityId',
        severity: LogSeverity.info,
      );

      print('[ConceptExtraction] ===== Completed successfully =====');
      return true;
    } catch (e, stackTrace) {
      print('[ConceptExtraction] ===== ERROR =====');
      print('[ConceptExtraction] Exception: $e');
      print('[ConceptExtraction] StackTrace: $stackTrace');

      _logger.log(
        'Error extracting concepts: $e\n$stackTrace',
        severity: LogSeverity.error,
      );

      return false;
    }
  }

  Future<void> _saveReviewableItem(ReviewableItem item) async {
    final data = item.toDbRow();

    // Check if item already exists
    final existing = await CrdtDatabase.instance.query(
      'SELECT id FROM reviewable_items WHERE id = ?',
      [item.id],
    );

    if (existing.isEmpty) {
      // Insert new item
      await CrdtDatabase.instance.execute(
        '''INSERT INTO reviewable_items
           (id, activity_id, course_id, module_id, subsection_id, type,
            content, answer, distractors, metadata, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          data['id'],
          data['activity_id'],
          data['course_id'],
          data['module_id'],
          data['subsection_id'],
          data['type'],
          data['content'],
          data['answer'],
          data['distractors'],
          data['metadata'],
          data['created_at'],
          data['updated_at'],
        ],
      );
      print('[ConceptExtraction] Inserted concept: ${item.content.substring(0, 50)}...');
    } else {
      // Update existing item
      await CrdtDatabase.instance.execute(
        '''UPDATE reviewable_items
           SET content = ?, answer = ?, distractors = ?, metadata = ?, updated_at = ?
           WHERE id = ?''',
        [
          data['content'],
          data['answer'],
          data['distractors'],
          data['metadata'],
          data['updated_at'],
          data['id'],
        ],
      );
      print('[ConceptExtraction] Updated concept: ${item.content.substring(0, 50)}...');
    }
  }

  /// Helper to find activity in course structure
  Activity? _findActivity(Course course, String activityId) {
    for (final module in course.modules) {
      for (final subSection in module.subSections) {
        for (final activity in subSection.activities) {
          if (activity.id == activityId) {
            return activity;
          }
        }
      }
    }
    return null;
  }
}
