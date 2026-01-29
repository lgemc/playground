import 'package:flutter/material.dart';
import '../../shared/lms.dart';
import '../widgets/sub_section_list_tile.dart';
import 'sub_section_form_screen.dart';
import 'sub_section_screen.dart';

class ModuleDetailScreen extends StatefulWidget {
  final String courseId;
  final String moduleId;

  const ModuleDetailScreen({
    super.key,
    required this.courseId,
    required this.moduleId,
  });

  @override
  State<ModuleDetailScreen> createState() => _ModuleDetailScreenState();
}

class _ModuleDetailScreenState extends State<ModuleDetailScreen> {
  final _storage = LmsStorageService.instance;
  LessonModule? _module;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadModule();
  }

  Future<void> _loadModule() async {
    setState(() => _isLoading = true);
    final course = await _storage.getCourse(widget.courseId);
    final module = course?.modules.firstWhere((m) => m.id == widget.moduleId);
    setState(() {
      _module = module;
      _isLoading = false;
    });
  }

  Future<void> _deleteSubSection(LessonSubSection subSection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sub-Section'),
        content: Text('Are you sure you want to delete "${subSection.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _storage.deleteSubSection(
        widget.courseId,
        widget.moduleId,
        subSection.id,
      );
      _loadModule();
    }
  }

  Future<void> _navigateToSubSectionForm([LessonSubSection? subSection]) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => SubSectionFormScreen(
          courseId: widget.courseId,
          moduleId: widget.moduleId,
          subSection: subSection,
        ),
      ),
    );

    if (result == true) {
      _loadModule();
    }
  }

  Future<void> _navigateToSubSection(LessonSubSection subSection) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SubSectionScreen(
          courseId: widget.courseId,
          moduleId: widget.moduleId,
          subSectionId: subSection.id,
        ),
      ),
    );
    _loadModule();
  }

  Future<void> _reorderSubSections(int oldIndex, int newIndex) async {
    if (_module == null) return;

    if (newIndex > oldIndex) newIndex--;

    final subSections = List<LessonSubSection>.from(_module!.subSections);
    final subSection = subSections.removeAt(oldIndex);
    subSections.insert(newIndex, subSection);

    final subSectionIds = subSections.map((s) => s.id).toList();
    await _storage.reorderSubSections(
      widget.courseId,
      widget.moduleId,
      subSectionIds,
    );
    _loadModule();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_module == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Module not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_module!.name),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _module!.subSections.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.list, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No sub-sections yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('Tap + to create your first sub-section'),
                ],
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _module!.subSections.length,
              onReorder: _reorderSubSections,
              itemBuilder: (context, index) {
                final subSection = _module!.subSections[index];
                return SubSectionListTile(
                  key: ValueKey(subSection.id),
                  subSection: subSection,
                  onTap: () => _navigateToSubSection(subSection),
                  onEdit: () => _navigateToSubSectionForm(subSection),
                  onDelete: () => _deleteSubSection(subSection),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToSubSectionForm(),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}
