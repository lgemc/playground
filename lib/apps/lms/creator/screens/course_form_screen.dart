import 'package:flutter/material.dart';
import '../../shared/lms.dart';
import '../widgets/file_picker_dialog.dart';

class CourseFormScreen extends StatefulWidget {
  final Course? course;

  const CourseFormScreen({super.key, this.course});

  @override
  State<CourseFormScreen> createState() => _CourseFormScreenState();
}

class _CourseFormScreenState extends State<CourseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _storage = LmsStorageService.instance;

  String? _thumbnailFileId;
  String? _thumbnailFileName;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.course != null) {
      _nameController.text = widget.course!.name;
      _descriptionController.text = widget.course!.description ?? '';
      _thumbnailFileId = widget.course!.thumbnailFileId;
      _loadThumbnailFileName();
    }
  }

  Future<void> _loadThumbnailFileName() async {
    if (_thumbnailFileId != null) {
      final file = await FileSystemBridge.instance.getFileById(_thumbnailFileId!);
      if (file != null && mounted) {
        setState(() => _thumbnailFileName = file.name);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectThumbnail() async {
    final fileId = await showDialog<String>(
      context: context,
      builder: (context) => const FilePickerDialog(
        title: 'Select Thumbnail',
        mimeTypeFilter: 'image/',
      ),
    );

    if (fileId != null && mounted) {
      final file = await FileSystemBridge.instance.getFileById(fileId);
      setState(() {
        _thumbnailFileId = fileId;
        _thumbnailFileName = file?.name;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final course = widget.course != null
          ? widget.course!.copyWith(
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
              thumbnailFileId: _thumbnailFileId,
            )
          : Course.create(
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
              thumbnailFileId: _thumbnailFileId,
            );

      await _storage.saveCourse(course);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.course != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Course' : 'New Course'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Course Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a course name';
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _selectThumbnail,
              icon: const Icon(Icons.image),
              label: Text(
                _thumbnailFileName != null
                    ? 'Thumbnail: $_thumbnailFileName'
                    : 'Select Thumbnail (optional)',
              ),
            ),
            if (_thumbnailFileId != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _thumbnailFileId = null;
                    _thumbnailFileName = null;
                  });
                },
                child: const Text('Remove Thumbnail'),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isLoading ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEdit ? 'Save Changes' : 'Create Course'),
            ),
          ],
        ),
      ),
    );
  }
}
