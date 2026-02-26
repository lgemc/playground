import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../notes/widgets/markdown_field.dart';
import '../services/file_system_storage.dart';

class MarkdownEditorScreen extends StatefulWidget {
  final String folderPath;

  const MarkdownEditorScreen({
    super.key,
    required this.folderPath,
  });

  @override
  State<MarkdownEditorScreen> createState() => _MarkdownEditorScreenState();
}

class _MarkdownEditorScreenState extends State<MarkdownEditorScreen> {
  late TextEditingController _filenameController;
  late String _content;
  bool _hasChanges = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _filenameController = TextEditingController();
    _content = '';
    _filenameController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _filenameController.removeListener(_onChanged);
    _filenameController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  void _onContentChanged(String value) {
    _content = value;
    _onChanged();
  }

  Future<void> _saveFile() async {
    final filename = _filenameController.text.trim();

    if (filename.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a filename')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Add .md extension if not present
      final fullFilename = filename.endsWith('.md') ? filename : '$filename.md';

      // Create temporary file with content
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fullFilename');
      await tempFile.writeAsString(_content);

      // Add to file system
      await FileSystemStorage.instance.addFile(tempFile, widget.folderPath);

      // Delete temp file
      await tempFile.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created $fullFilename')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating file: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) {
      Navigator.of(context).pop(false);
      return false;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Do you want to discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      Navigator.of(context).pop(false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _onWillPop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _onWillPop,
          ),
          title: const Text('New Markdown File'),
          actions: [
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: _saveFile,
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _filenameController,
                decoration: const InputDecoration(
                  hintText: 'Filename (without .md)',
                  border: InputBorder.none,
                  suffixText: '.md',
                ),
                style: Theme.of(context).textTheme.headlineSmall,
                autofocus: true,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: MarkdownField(
                initialValue: _content,
                onChanged: _onContentChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
