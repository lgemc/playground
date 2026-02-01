import 'package:flutter/material.dart';
import '../../shared/lms.dart';
import '../widgets/file_picker_dialog.dart';

class ActivityFormScreen extends StatefulWidget {
  final String courseId;
  final String moduleId;
  final String subSectionId;
  final Activity? activity;

  const ActivityFormScreen({
    super.key,
    required this.courseId,
    required this.moduleId,
    required this.subSectionId,
    this.activity,
  });

  @override
  State<ActivityFormScreen> createState() => _ActivityFormScreenState();
}

class _ActivityFormScreenState extends State<ActivityFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _storage = LmsCrdtStorageService.instance;

  String? _fileId;
  String? _fileName;
  ResourceType _resourceType = ResourceType.document;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.activity != null && widget.activity is ResourceFileActivity) {
      final activity = widget.activity as ResourceFileActivity;
      _nameController.text = activity.name;
      _descriptionController.text = activity.description ?? '';
      _fileId = activity.fileId;
      _resourceType = activity.resourceType;
      _loadFileName();
    }
  }

  Future<void> _loadFileName() async {
    if (_fileId != null) {
      final file = await FileSystemBridge.instance.getFileById(_fileId!);
      if (file != null && mounted) {
        setState(() => _fileName = file.name);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectFile() async {
    String? mimeFilter;
    switch (_resourceType) {
      case ResourceType.audio:
        mimeFilter = 'audio/';
        break;
      case ResourceType.video:
        mimeFilter = 'video/';
        break;
      case ResourceType.document:
        mimeFilter = null;
        break;
      case ResourceType.lecture:
      case ResourceType.other:
        mimeFilter = null;
        break;
    }

    final fileId = await showDialog<String>(
      context: context,
      builder: (context) => FilePickerDialog(
        title: 'Select Resource File',
        mimeTypeFilter: mimeFilter,
      ),
    );

    if (fileId != null && mounted) {
      final file = await FileSystemBridge.instance.getFileById(fileId);
      setState(() {
        _fileId = fileId;
        _fileName = file?.name;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final course = await _storage.getCourse(widget.courseId);
      if (course == null) return;

      final module = course.modules.firstWhere((m) => m.id == widget.moduleId);
      final subSection = module.subSections.firstWhere(
        (s) => s.id == widget.subSectionId,
      );

      final activity = widget.activity != null &&
              widget.activity is ResourceFileActivity
          ? (widget.activity as ResourceFileActivity).copyWith(
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
              fileId: _fileId,
              resourceType: _resourceType,
            )
          : ResourceFileActivity.create(
              subSectionId: widget.subSectionId,
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
              order: subSection.activities.length,
              fileId: _fileId,
              resourceType: _resourceType,
            );

      await _storage.saveActivity(
        widget.courseId,
        widget.moduleId,
        widget.subSectionId,
        activity,
      );

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
    final isEdit = widget.activity != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Activity' : 'New Activity'),
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
                labelText: 'Activity Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter an activity name';
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
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ResourceType>(
              initialValue: _resourceType,
              decoration: const InputDecoration(
                labelText: 'Resource Type',
                border: OutlineInputBorder(),
              ),
              items: ResourceType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(_getResourceTypeName(type)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _resourceType = value;
                    // Clear file selection when type changes
                    if (_fileId != null) {
                      _fileId = null;
                      _fileName = null;
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _selectFile,
              icon: const Icon(Icons.attach_file),
              label: Text(
                _fileName != null
                    ? 'File: $_fileName'
                    : 'Select Resource File',
              ),
            ),
            if (_fileId != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _fileId = null;
                    _fileName = null;
                  });
                },
                child: const Text('Remove File'),
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
                  : Text(isEdit ? 'Save Changes' : 'Create Activity'),
            ),
          ],
        ),
      ),
    );
  }

  String _getResourceTypeName(ResourceType type) {
    switch (type) {
      case ResourceType.lecture:
        return 'Lecture';
      case ResourceType.audio:
        return 'Audio';
      case ResourceType.video:
        return 'Video';
      case ResourceType.document:
        return 'Document';
      case ResourceType.other:
        return 'Other';
    }
  }
}
