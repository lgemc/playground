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
      final derivativeId = message.payload['derivative_id'] as String?;
      final fileId = message.payload['file_id'] as String?;
      final type = message.payload['type'] as String?;

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
      final derivative = await _storage.getDerivative(derivativeId);
      if (derivative == null) {
        _logger.log(
          'Derivative not found: $derivativeId',
          severity: LogSeverity.error,
        );
        return false;
      }

      // Update status to processing
      await _storage.updateDerivative(derivativeId, status: 'processing');

      // Get the file
      final files = await _storage.getFilesInFolder('');
      FileItem? file;

      // Search for file in all folders
      for (final folder in await _getAllFolders()) {
        final folderFiles = await _storage.getFilesInFolder(folder);
        file = folderFiles.where((f) => f.id == fileId).firstOrNull;
        if (file != null) break;
      }

      // Try current folder
      file ??= files.where((f) => f.id == fileId).firstOrNull;

      if (file == null) {
        final errorMsg = 'File not found: $fileId';
        _logger.log(errorMsg, severity: LogSeverity.error);
        await _storage.updateDerivative(
          derivativeId,
          status: 'failed',
          errorMessage: errorMsg,
        );
        return false;
      }

      // Get the generator for this type
      final generator = _derivativeService.getGenerator(type);
      if (generator == null) {
        final errorMsg = 'No generator found for type: $type';
        _logger.log(errorMsg, severity: LogSeverity.error);
        await _storage.updateDerivative(
          derivativeId,
          status: 'failed',
          errorMessage: errorMsg,
        );
        return false;
      }

      // Generate the derivative content
      final content = await generator.generate(file);

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

  Future<List<String>> _getAllFolders() async {
    final folders = <String>[];
    final rootFolders = await _storage.getFoldersInPath('');

    for (final folder in rootFolders) {
      folders.add(folder.path);
      // Could recursively get subfolders here if needed
    }

    return folders;
  }
}
