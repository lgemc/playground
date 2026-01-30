import '../apps/file_system/models/file_item.dart';
import '../apps/file_system/models/derivative_artifact.dart';
import '../apps/file_system/services/file_system_storage.dart';
import '../core/app_bus.dart';
import '../core/app_event.dart';
import 'generators/derivative_generator.dart';

class DerivativeService {
  static final instance = DerivativeService._();
  DerivativeService._();

  final Map<String, DerivativeGenerator> _generators = {};

  void registerGenerator(DerivativeGenerator generator) {
    _generators[generator.type] = generator;
  }

  List<String> getAvailableTypes(FileItem file) {
    return _generators.entries
        .where((entry) => entry.value.canProcess(file))
        .map((entry) => entry.key)
        .toList();
  }

  DerivativeGenerator? getGenerator(String type) {
    return _generators[type];
  }

  List<DerivativeGenerator> getAllGenerators(FileItem file) {
    return _generators.values
        .where((generator) => generator.canProcess(file))
        .toList();
  }

  Future<DerivativeArtifact> generateDerivative(
    String fileId,
    String type,
  ) async {
    // Create derivative record
    final derivative =
        await FileSystemStorage.instance.createDerivative(fileId, type);

    // Emit event for queue processing
    await AppBus.instance.emit(AppEvent.create(
      type: 'derivative.create',
      appId: 'file_system',
      metadata: {
        'derivative_id': derivative.id,
        'file_id': fileId,
        'type': type,
      },
    ));

    return derivative;
  }
}
