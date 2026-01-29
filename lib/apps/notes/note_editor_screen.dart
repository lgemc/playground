import 'dart:async';

import 'package:flutter/material.dart';

import 'models/note.dart';
import 'services/notes_storage_v2.dart';
import 'widgets/markdown_field.dart';

class NoteEditorScreen extends StatefulWidget {
  final Note note;
  final bool isNew;

  const NoteEditorScreen({
    super.key,
    required this.note,
    this.isNew = false,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late TextEditingController _titleController;
  late String _content;
  bool _hasChanges = false;
  bool _isSaving = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    _content = widget.note.content;
    _titleController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _titleController.removeListener(_onChanged);
    _titleController.dispose();
    if (_hasChanges) {
      _saveNote();
    }
    super.dispose();
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
    _debounceTimer = Timer(const Duration(seconds: 2), _saveNote);
  }

  Future<void> _saveNote() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final title = _titleController.text.trim();
      final displayTitle = title.isEmpty ? _getDefaultTitle() : title;

      final updatedNote = widget.note.copyWith(
        title: displayTitle,
        content: _content,
        updatedAt: DateTime.now(),
      );

      await NotesStorageV2.instance.saveNote(updatedNote);
      _hasChanges = false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving note: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _getDefaultTitle() {
    if (_content.isEmpty) return 'Untitled';

    final firstLine = _content.split('\n').first.trim();
    if (firstLine.isEmpty) return 'Untitled';

    // Remove markdown heading prefix
    final cleanLine = firstLine.replaceFirst(RegExp(r'^#+\s*'), '');
    if (cleanLine.length > 50) {
      return '${cleanLine.substring(0, 47)}...';
    }
    return cleanLine.isEmpty ? 'Untitled' : cleanLine;
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) {
      Navigator.of(context).pop(true);
      return false;
    }

    _debounceTimer?.cancel();
    await _saveNote();
    if (mounted) {
      Navigator.of(context).pop(true);
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
          title: Text(widget.isNew ? 'New Note' : 'Edit Note'),
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
                onPressed: _saveNote,
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
                controller: _titleController,
                decoration: const InputDecoration(
                  hintText: 'Note title',
                  border: InputBorder.none,
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
