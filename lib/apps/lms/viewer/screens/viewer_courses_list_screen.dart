import 'package:flutter/material.dart';
import '../../shared/lms.dart';
import 'viewer_course_detail_screen.dart';

class ViewerCoursesListScreen extends StatefulWidget {
  const ViewerCoursesListScreen({super.key});

  @override
  State<ViewerCoursesListScreen> createState() => _ViewerCoursesListScreenState();
}

class _ViewerCoursesListScreenState extends State<ViewerCoursesListScreen> {
  final _storage = LmsStorageService.instance;
  List<Course> _courses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() => _isLoading = true);
    final courses = await _storage.loadCourses();
    setState(() {
      _courses = courses;
      _isLoading = false;
    });
  }

  Future<void> _navigateToCourseDetail(Course course) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewerCourseDetailScreen(courseId: course.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Courses'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _courses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.school, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No courses available',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text('Courses will appear here once created'),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _courses.length,
                  itemBuilder: (context, index) {
                    final course = _courses[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: const Icon(Icons.school, color: Colors.blue),
                        ),
                        title: Text(
                          course.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (course.description != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                course.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.folder, size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text('${course.totalModules} modules'),
                                const SizedBox(width: 16),
                                Icon(Icons.list, size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text('${course.totalSubSections} sections'),
                              ],
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _navigateToCourseDetail(course),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
