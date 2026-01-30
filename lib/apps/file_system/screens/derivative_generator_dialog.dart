import 'package:flutter/material.dart';
import '../models/file_item.dart';
import '../../../services/derivative_service.dart';

class DerivativeGeneratorDialog extends StatelessWidget {
  final FileItem file;

  const DerivativeGeneratorDialog({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    final derivativeService = DerivativeService.instance;
    final availableGenerators = derivativeService.getAllGenerators(file);

    return AlertDialog(
      title: const Text('Generate Derivative'),
      content: availableGenerators.isEmpty
          ? const Text('No derivative generators available for this file type.')
          : SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: availableGenerators.length,
                itemBuilder: (context, index) {
                  final generator = availableGenerators[index];
                  return ListTile(
                    leading: Icon(generator.icon),
                    title: Text(generator.displayName),
                    subtitle: Text('Generate ${generator.type} from file'),
                    onTap: () async {
                      Navigator.pop(context);
                      await derivativeService.generateDerivative(
                        file.id,
                        generator.type,
                      );
                      if (context.mounted) {
                        Navigator.pop(context, true);
                      }
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
