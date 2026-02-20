import 'package:flutter/material.dart';
import '../../shared/lms.dart';
import '../../creator/widgets/learning_progress_card.dart';
import '../../creator/screens/quiz_list_screen.dart';
import 'viewer_module_detail_screen.dart';

class ViewerCourseDetailScreen extends StatefulWidget {
  final String courseId;

  const ViewerCourseDetailScreen({super.key, required this.courseId});

  @override
  State<ViewerCourseDetailScreen> createState() => _ViewerCourseDetailScreenState();
}

class _ViewerCourseDetailScreenState extends State<ViewerCourseDetailScreen> {
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

  Future<void> _navigateToModuleDetail(LessonModule module) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewerModuleDetailScreen(
          courseId: widget.courseId,
          moduleId: module.id,
        ),
      ),
    );
  }

  void _navigateToQuizzes() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuizListScreen(
          courseId: widget.courseId,
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

    if (_course == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Course not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_course!.name),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.quiz),
            tooltip: 'Quizzes',
            onPressed: _navigateToQuizzes,
          ),
        ],
      ),
      body: Column(
        children: [
          // Learning Progress Card - for spaced repetition
          LearningProgressCard(courseId: widget.courseId),

          if (_course!.description != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.blue.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About this course',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(_course!.description!),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.folder,
                    label: 'Modules',
                    value: '${_course!.totalModules}',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.list,
                    label: 'Sections',
                    value: '${_course!.totalSubSections}',
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.assignment,
                    label: 'Activities',
                    value: '${_course!.totalActivities}',
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _course!.modules.isEmpty
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
                        const Text('This course has no modules'),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _course!.modules.length,
                    itemBuilder: (context, index) {
                      final module = _course!.modules[index];
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
                            module.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${module.subSections.length} sections',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _navigateToModuleDetail(module),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
