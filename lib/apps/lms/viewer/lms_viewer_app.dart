import 'package:flutter/material.dart';
import '../../../core/sub_app.dart';
import 'screens/viewer_courses_list_screen.dart';

class LmsViewerApp extends SubApp {
  @override
  String get id => 'lms_viewer';

  @override
  String get name => 'Course Viewer';

  @override
  IconData get icon => Icons.play_circle_outline;

  @override
  Color get themeColor => Colors.blue;

  @override
  Widget build(BuildContext context) {
    return const ViewerCoursesListScreen();
  }
}
