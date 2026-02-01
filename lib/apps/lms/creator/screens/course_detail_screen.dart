import 'package:flutter/material.dart';
import '../../shared/lms.dart';
import '../widgets/module_list_tile.dart';
import 'module_form_screen.dart';
import 'module_detail_screen.dart';

class CourseDetailScreen extends StatefulWidget {
  final String courseId;

  const CourseDetailScreen({super.key, required this.courseId});

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  final _storage = LmsCrdtStorageService.instance;
  Course? _course;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCourse();
  }

  Future<void> _loadCourse() async {
    setState(() => _isLoading = true);
    final course = await _storage.getCourse(widget.courseId);
    setState(() {
      _course = course;
      _isLoading = false;
    });
  }

  Future<void> _deleteModule(LessonModule module) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Module'),
        content: Text('Are you sure you want to delete "${module.name}"?'),
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
      await _storage.deleteModule(widget.courseId, module.id);
      _loadCourse();
    }
  }

  Future<void> _navigateToModuleForm([LessonModule? module]) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ModuleFormScreen(
          courseId: widget.courseId,
          module: module,
        ),
      ),
    );

    if (result == true) {
      _loadCourse();
    }
  }

  Future<void> _navigateToModuleDetail(LessonModule module) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ModuleDetailScreen(
          courseId: widget.courseId,
          moduleId: module.id,
        ),
      ),
    );
    _loadCourse();
  }

  Future<void> _reorderModules(int oldIndex, int newIndex) async {
    if (_course == null) return;

    if (newIndex > oldIndex) newIndex--;

    final modules = List<LessonModule>.from(_course!.modules);
    final module = modules.removeAt(oldIndex);
    modules.insert(newIndex, module);

    final moduleIds = modules.map((m) => m.id).toList();
    await _storage.reorderModules(widget.courseId, moduleIds);
    _loadCourse();
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

    if (_course == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Course not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_course!.name),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _course!.modules.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No modules yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('Tap + to create your first module'),
                ],
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _course!.modules.length,
              onReorder: _reorderModules,
              itemBuilder: (context, index) {
                final module = _course!.modules[index];
                return ModuleListTile(
                  key: ValueKey(module.id),
                  module: module,
                  onTap: () => _navigateToModuleDetail(module),
                  onEdit: () => _navigateToModuleForm(module),
                  onDelete: () => _deleteModule(module),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToModuleForm(),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}
