import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../notes/widgets/markdown_field.dart';
import '../models/file_item.dart';
import '../services/file_system_storage.dart';

class MarkdownFileEditorScreen extends StatefulWidget {
  final FileItem file;

  const MarkdownFileEditorScreen({
    super.key,
    required this.file,
  });

  @override
  State<MarkdownFileEditorScreen> createState() => _MarkdownFileEditorScreenState();
}

class _MarkdownFileEditorScreenState extends State<MarkdownFileEditorScreen> {
  late TextEditingController _filenameController;
  late String _content;
  bool _hasChanges = false;
  bool _isSaving = false;
  bool _isLoading = true;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    // Initialize with filename without extension
    final nameWithoutExt = widget.file.name.replaceAll(RegExp(r'\.md$'), '');
    _filenameController = TextEditingController(text: nameWithoutExt);
    _content = '';
    _filenameController.addListener(_onChanged);
    _loadContent();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _filenameController.removeListener(_onChanged);
    _filenameController.dispose();
    if (_hasChanges) {
      _saveFile();
    }
    super.dispose();
  }

  Future<void> _loadContent() async {
    try {
      final filePath = FileSystemStorage.instance.getAbsolutePath(widget.file);
      final file = File(filePath);

      if (await file.exists()) {
        final content = await file.readAsString();
        setState(() {
          _content = content;
          _isLoading = false;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File not found')),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading file: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  void _onChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
    _scheduleSave();
  }

  void _onContentChanged(String value) {
    _content = value;
    _onChanged();
  }

  void _scheduleSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), _saveFile);
  }

  Future<void> _saveFile() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      // Update content
      final filePath = FileSystemStorage.instance.getAbsolutePath(widget.file);
      final file = File(filePath);
      await file.writeAsString(_content);

      // Update filename if changed
      final newFilename = _filenameController.text.trim();
      final fullFilename = newFilename.endsWith('.md') ? newFilename : '$newFilename.md';

      if (fullFilename != widget.file.name) {
        await FileSystemStorage.instance.renameFile(widget.file.id, fullFilename);
      }

      _hasChanges = false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving file: $e')),
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
      Navigator.of(context).pop(true);
      return false;
    }

    _debounceTimer?.cancel();
    await _saveFile();
    if (mounted) {
      Navigator.of(context).pop(true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Loading...'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

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
          title: const Text('Edit Markdown'),
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
            else if (_hasChanges)
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _saveFile,
              )
            else
              const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(Icons.check, color: Colors.green),
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
