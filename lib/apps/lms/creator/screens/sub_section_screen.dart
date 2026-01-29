import 'package:flutter/material.dart';
import '../../shared/lms.dart';
import '../widgets/activity_list_tile.dart';
import 'activity_form_screen.dart';

class SubSectionScreen extends StatefulWidget {
  final String courseId;
  final String moduleId;
  final String subSectionId;

  const SubSectionScreen({
    super.key,
    required this.courseId,
    required this.moduleId,
    required this.subSectionId,
  });

  @override
  State<SubSectionScreen> createState() => _SubSectionScreenState();
}

class _SubSectionScreenState extends State<SubSectionScreen> {
  final _storage = LmsStorageService.instance;
  LessonSubSection? _subSection;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubSection();
  }

  Future<void> _loadSubSection() async {
    setState(() => _isLoading = true);
    final course = await _storage.getCourse(widget.courseId);
    final module = course?.modules.firstWhere((m) => m.id == widget.moduleId);
    final subSection = module?.subSections.firstWhere(
      (s) => s.id == widget.subSectionId,
    );
    setState(() {
      _subSection = subSection;
      _isLoading = false;
    });
  }

  Future<void> _deleteActivity(Activity activity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Activity'),
        content: Text('Are you sure you want to delete "${activity.name}"?'),
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
      await _storage.deleteActivity(
        widget.courseId,
        widget.moduleId,
        widget.subSectionId,
        activity.id,
      );
      _loadSubSection();
    }
  }

  Future<void> _navigateToActivityForm([Activity? activity]) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ActivityFormScreen(
          courseId: widget.courseId,
          moduleId: widget.moduleId,
          subSectionId: widget.subSectionId,
          activity: activity,
        ),
      ),
    );

    if (result == true) {
      _loadSubSection();
    }
  }

  Future<void> _reorderActivities(int oldIndex, int newIndex) async {
    if (_subSection == null) return;

    if (newIndex > oldIndex) newIndex--;

    final activities = List<Activity>.from(_subSection!.activities);
    final activity = activities.removeAt(oldIndex);
    activities.insert(newIndex, activity);

    final activityIds = activities.map((a) => a.id).toList();
    await _storage.reorderActivities(
      widget.courseId,
      widget.moduleId,
      widget.subSectionId,
      activityIds,
    );
    _loadSubSection();
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

    if (_subSection == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Sub-section not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_subSection!.name),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _subSection!.activities.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.attachment, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No activities yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('Tap + to create your first activity'),
                ],
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _subSection!.activities.length,
              onReorder: _reorderActivities,
              itemBuilder: (context, index) {
                final activity = _subSection!.activities[index];
                return ActivityListTile(
                  key: ValueKey(activity.id),
                  activity: activity,
                  onEdit: () => _navigateToActivityForm(activity),
                  onDelete: () => _deleteActivity(activity),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToActivityForm(),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}
