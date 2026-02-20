import 'package:flutter/material.dart';
import '../models/file_item.dart';
import '../services/file_system_storage.dart';
import '../../../services/derivative_service.dart';
import '../../../services/generators/derivative_generator.dart';

class DerivativeGeneratorDialog extends StatefulWidget {
  final FileItem file;

  const DerivativeGeneratorDialog({super.key, required this.file});

  @override
  State<DerivativeGeneratorDialog> createState() =>
      _DerivativeGeneratorDialogState();
}

class _DerivativeGeneratorDialogState extends State<DerivativeGeneratorDialog> {
  List<DerivativeGenerator> _availableGenerators = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAvailableGenerators();
  }

  Future<void> _loadAvailableGenerators() async {
    final derivativeService = DerivativeService.instance;
    final allGenerators = derivativeService.getAllGenerators(widget.file);

    // For summary generator, check if transcript exists
    final derivatives =
        await FileSystemStorage.instance.getDerivatives(widget.file.id);
    final hasCompletedTranscript = derivatives.any(
      (d) => d.type == 'transcript' && d.status == 'completed',
    );

    final filtered = allGenerators.where((generator) {
      // Filter out summary generator if no transcript exists for video/audio
      if (generator.type == 'summary' &&
          (widget.file.isVideo || widget.file.isAudio)) {
        return hasCompletedTranscript;
      }
      return true;
    }).toList();

    if (mounted) {
      setState(() {
        _availableGenerators = filtered;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final derivativeService = DerivativeService.instance;

    return AlertDialog(
      title: const Text('Generate Derivative'),
      content: _isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          : _availableGenerators.isEmpty
              ? const Text(
                  'No derivative generators available for this file type.')
              : SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _availableGenerators.length,
                    itemBuilder: (context, index) {
                      final generator = _availableGenerators[index];
                      return ListTile(
                        leading: Icon(generator.icon),
                        title: Text(generator.displayName),
                        subtitle: Text('Generate ${generator.type} from file'),
                        onTap: () async {
                          // Close dialog and return true to trigger refresh
                          Navigator.pop(context, true);

                          // Start derivative generation (happens in background via queue)
                          await derivativeService.generateDerivative(
                            widget.file.id,
                            generator.type,
                          );
                        },
                      );
                    },
                  ),
                ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
