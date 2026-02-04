import 'package:flutter/material.dart';
import '../models/file_item.dart';
import '../models/derivative_artifact.dart';
import '../services/file_system_storage.dart';
import '../widgets/derivative_tile.dart';
import 'derivative_generator_dialog.dart';
import 'pdf_reader_screen.dart';
import '../../video_viewer/screens/video_player_screen.dart';
import '../../../services/share_service.dart';
import '../../../services/share_content.dart';
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
  final Set<String> _deletedIds = {}; // Track deleted IDs to prevent re-appearing

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
        // Filter out any derivatives that were deleted
        _derivatives = derivatives.where((d) => !_deletedIds.contains(d.id)).toList();
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

  void _openFile() {
    final ext = widget.file.extension.toLowerCase();
    final filePath = _storage.getAbsolutePath(widget.file);

    if (ext == 'pdf') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PdfReaderScreen(
            filePath: filePath,
            fileName: widget.file.name,
          ),
        ),
      );
    } else if (ext == 'mp4' || ext == 'mkv' || ext == 'avi' ||
               ext == 'mov' || ext == 'webm' || ext == 'flv' ||
               ext == 'm4v' || ext == '3gp') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            filePath: filePath,
            fileName: widget.file.name,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot open ${widget.file.extension} files yet'),
        ),
      );
    }
  }

  Future<void> _shareFile() async {
    final content = ShareContent.file(
      sourceAppId: 'file_system',
      path: widget.file.relativePath,
      name: widget.file.name,
      mimeType: widget.file.mimeType,
    );
    content.data['fileId'] = widget.file.id;
    await ShareService.instance.share(context, content);
  }

  Future<void> _deleteDerivative(DerivativeArtifact derivative) async {
    // Track deleted ID to prevent it from reappearing during auto-refresh
    _deletedIds.add(derivative.id);

    // Immediately remove from local list to avoid rebuild issues with Dismissible
    setState(() {
      _derivatives.removeWhere((d) => d.id == derivative.id);
    });

    // Delete the derivative (confirmation already shown by Dismissible)
    try {
      await _storage.deleteDerivative(derivative.id);
    } catch (e) {
      // Remove from deleted set if deletion failed
      _deletedIds.remove(derivative.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
        // Reload to restore the item if deletion failed
        _loadDerivatives();
      }
    }
  }

  Future<void> _applyRename(DerivativeArtifact derivative) async {
    // Get the derivative content to extract proposed title
    final content = await _storage.getDerivativeContent(derivative.id);
    final lines = content.split('\n');
    String? proposedTitle;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line == '# Proposed Title' && i + 2 < lines.length) {
        proposedTitle = lines[i + 2].trim();
        break;
      }
    }

    if (proposedTitle == null || proposedTitle.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to extract title')),
        );
      }
      return;
    }

    try {
      // Get file extension
      final extension = widget.file.extension;
      final newName = extension.isNotEmpty
          ? '$proposedTitle.$extension'
          : proposedTitle;

      // Rename the file
      await _storage.renameFile(widget.file.id, newName);

      // Update derivative to mark as applied
      final updatedContent = content.replaceFirst(
        '## Applied\nfalse',
        '## Applied\ntrue',
      ).replaceFirst(
        '## Applied At\nnull',
        '## Applied At\n${DateTime.now().toIso8601String()}',
      );
      await _storage.setDerivativeContent(derivative.id, updatedContent);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File renamed to $newName')),
        );
        // Go back since the file has been renamed
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to rename file: $e')),
        );
      }
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Chip(label: Text('Original')),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) {
                            switch (value) {
                              case 'open':
                                _openFile();
                                break;
                              case 'share':
                                _shareFile();
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'open',
                              child: ListTile(
                                leading: Icon(Icons.open_in_new),
                                title: Text('Open'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'share',
                              child: ListTile(
                                leading: Icon(Icons.share),
                                title: Text('Share'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    onTap: _openFile,
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
                              onApplyRename: derivative.type == 'auto_title'
                                  ? () => _applyRename(derivative)
                                  : null,
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
