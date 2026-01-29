import 'package:flutter/material.dart';
import '../../shared/lms.dart';

class SubSectionFormScreen extends StatefulWidget {
  final String courseId;
  final String moduleId;
  final LessonSubSection? subSection;

  const SubSectionFormScreen({
    super.key,
    required this.courseId,
    required this.moduleId,
    this.subSection,
  });

  @override
  State<SubSectionFormScreen> createState() => _SubSectionFormScreenState();
}

class _SubSectionFormScreenState extends State<SubSectionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _storage = LmsStorageService.instance;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.subSection != null) {
      _nameController.text = widget.subSection!.name;
      _descriptionController.text = widget.subSection!.description ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final course = await _storage.getCourse(widget.courseId);
      if (course == null) return;

      final module = course.modules.firstWhere((m) => m.id == widget.moduleId);

      final subSection = widget.subSection != null
          ? widget.subSection!.copyWith(
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
            )
          : LessonSubSection.create(
              moduleId: widget.moduleId,
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
              order: module.subSections.length,
            );

      await _storage.saveSubSection(
        widget.courseId,
        widget.moduleId,
        subSection,
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
    final isEdit = widget.subSection != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Sub-Section' : 'New Sub-Section'),
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
                labelText: 'Sub-Section Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a sub-section name';
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
                  : Text(isEdit ? 'Save Changes' : 'Create Sub-Section'),
            ),
          ],
        ),
      ),
    );
  }
}
