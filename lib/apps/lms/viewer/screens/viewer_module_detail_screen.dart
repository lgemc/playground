import 'package:flutter/material.dart';
import '../../shared/lms.dart';
import 'viewer_sub_section_screen.dart';

class ViewerModuleDetailScreen extends StatefulWidget {
  final String courseId;
  final String moduleId;

  const ViewerModuleDetailScreen({
    super.key,
    required this.courseId,
    required this.moduleId,
  });

  @override
  State<ViewerModuleDetailScreen> createState() => _ViewerModuleDetailScreenState();
}

class _ViewerModuleDetailScreenState extends State<ViewerModuleDetailScreen> {
  final _storage = LmsCrdtStorageService.instance;
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

  Future<void> _navigateToSubSection(LessonSubSection subSection) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewerSubSectionScreen(
          courseId: widget.courseId,
          moduleId: widget.moduleId,
          subSectionId: subSection.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_module == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Module not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_module!.name),
        backgroundColor: Colors.blue,
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
                    'No sections yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('This module has no sections'),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _module!.subSections.length,
              itemBuilder: (context, index) {
                final subSection = _module!.subSections[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade100,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    title: Text(
                      subSection.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${subSection.activities.length} activities',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _navigateToSubSection(subSection),
                  ),
                );
              },
            ),
    );
  }
}
