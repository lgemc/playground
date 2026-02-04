import '../apps/file_system/models/file_item.dart';
import '../apps/file_system/services/file_system_storage.dart';
import 'derivative_service.dart';
import 'logger.dart';
import 'queue_consumer.dart';
import 'queue_message.dart';

class DerivativeQueueConsumer extends QueueConsumer {
  @override
  String get id => 'derivative_consumer';

  @override
  String get name => 'Derivative Queue Consumer';

  @override
  String get queueId => 'derivative-processor';

  final _storage = FileSystemStorage.instance;
  final _derivativeService = DerivativeService.instance;
  final _logger = Logger(appId: 'derivative', appName: 'Derivative Service');

  @override
  Future<bool> processMessage(QueueMessage message) async {
    try {
      print('[DerivativeConsumer] ===== Processing message =====');
      print('[DerivativeConsumer] Payload: ${message.payload}');

      final derivativeId = message.payload['derivative_id'] as String?;
      final fileId = message.payload['file_id'] as String?;
      final type = message.payload['type'] as String?;

      print('[DerivativeConsumer] derivativeId: $derivativeId');
      print('[DerivativeConsumer] fileId: $fileId');
      print('[DerivativeConsumer] type: $type');

      if (derivativeId == null || fileId == null || type == null) {
        _logger.log(
          'Derivative task missing required fields',
          severity: LogSeverity.error,
        );
        return false;
      }

      _logger.log(
        'Processing derivative task: $derivativeId',
        severity: LogSeverity.info,
      );

      // Load the derivative from storage
      print('[DerivativeConsumer] Loading derivative from storage...');
      final derivative = await _storage.getDerivative(derivativeId);
      if (derivative == null) {
        print('[DerivativeConsumer] ERROR: Derivative not found');
        _logger.log(
          'Derivative not found: $derivativeId',
          severity: LogSeverity.error,
        );
        return false;
      }
      print('[DerivativeConsumer] Derivative loaded: ${derivative.type}');

      // Update status to processing
      print('[DerivativeConsumer] Updating status to processing...');
      await _storage.updateDerivative(derivativeId, status: 'processing');

      // Get the file directly by ID
      print('[DerivativeConsumer] Getting file by ID: $fileId');
      final file = await _storage.getFileById(fileId);

      if (file == null) {
        final errorMsg = 'File not found in database: $fileId';
        print('[DerivativeConsumer] ERROR: $errorMsg');
        _logger.log(errorMsg, severity: LogSeverity.error);
        await _storage.updateDerivative(
          derivativeId,
          status: 'failed',
          errorMessage: errorMsg,
        );
        return false;
      }

      print('[DerivativeConsumer] Found file: ${file.name}');
      _logger.log(
        'Found file: ${file.name} (id: ${file.id}, path: ${file.relativePath})',
        severity: LogSeverity.info,
      );

      // Get the generator for this type
      print('[DerivativeConsumer] Getting generator for type: $type');
      final generator = _derivativeService.getGenerator(type);
      if (generator == null) {
        final errorMsg = 'No generator found for type: $type';
        print('[DerivativeConsumer] ERROR: $errorMsg');
        _logger.log(errorMsg, severity: LogSeverity.error);
        await _storage.updateDerivative(
          derivativeId,
          status: 'failed',
          errorMessage: errorMsg,
        );
        return false;
      }

      print('[DerivativeConsumer] Generator found: ${generator.displayName}');
      print('[DerivativeConsumer] Starting generation...');
      // Generate the derivative content
      final content = await generator.generate(file);
      print('[DerivativeConsumer] Generation complete, content length: ${content.length}');

      // Save the content
      await _storage.setDerivativeContent(derivativeId, content);

      // Update status to completed
      await _storage.updateDerivative(derivativeId, status: 'completed');

      _logger.log(
        'Derivative completed: $derivativeId',
        severity: LogSeverity.info,
      );
      return true;
    } catch (e, stackTrace) {
      print('[DerivativeConsumer] ===== ERROR =====');
      print('[DerivativeConsumer] Exception: $e');
      print('[DerivativeConsumer] StackTrace: $stackTrace');

      _logger.log(
        'Error processing derivative: $e\n$stackTrace',
        severity: LogSeverity.error,
      );

      // Try to update derivative with error
      try {
        final derivativeId = message.payload['derivative_id'] as String?;
        if (derivativeId != null) {
          await _storage.updateDerivative(
            derivativeId,
            status: 'failed',
            errorMessage: e.toString(),
          );
        }
      } catch (_) {
        // Ignore errors when updating error state
      }

      return false;
    }
  }
}
