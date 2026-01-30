import 'package:flutter/material.dart';
import '../models/file_item.dart';
import '../models/derivative_artifact.dart';
import '../services/file_system_storage.dart';
import '../widgets/derivative_tile.dart';
import 'derivative_generator_dialog.dart';
import 'dart:async';

class FileDerivativesScreen extends StatefulWidget {
  final FileItem file;

  const FileDerivativesScreen({super.key, required this.file});

  @override
  State<FileDerivativesScreen> createState() => _FileDerivativesScreenState();
}

class _FileDerivativesScreenState extends State<FileDerivativesScreen> {
  final _storage = FileSystemStorage.instance;
  List<DerivativeArtifact> _derivatives = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadDerivatives();
    // Auto-refresh to show processing status updates
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _loadDerivatives(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDerivatives() async {
    final derivatives = await _storage.getDerivatives(widget.file.id);
    if (mounted) {
      setState(() {
        _derivatives = derivatives;
        _isLoading = false;
      });
    }
  }

  Future<void> _showGeneratorDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => DerivativeGeneratorDialog(file: widget.file),
    );

    if (result == true) {
      await _loadDerivatives();
    }
  }

  Future<void> _deleteDerivative(DerivativeArtifact derivative) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Derivative'),
        content: Text(
          'Are you sure you want to delete this ${derivative.type}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storage.deleteDerivative(derivative.id);
      await _loadDerivatives();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Original file card
                Card(
                  margin: const EdgeInsets.all(16),
                  child: ListTile(
                    leading: const Icon(Icons.insert_drive_file),
                    title: Text(widget.file.name),
                    subtitle: Text(
                      '${(widget.file.size / 1024).toStringAsFixed(2)} KB',
                    ),
                    trailing: const Chip(
                      label: Text('Original'),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Derivatives',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Derivatives list
                Expanded(
                  child: _derivatives.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No derivatives yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap + to create one',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _derivatives.length,
                          itemBuilder: (context, index) {
                            final derivative = _derivatives[index];
                            return DerivativeTile(
                              derivative: derivative,
                              onDelete: () => _deleteDerivative(derivative),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showGeneratorDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
