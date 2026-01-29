import 'package:flutter/material.dart';
import '../../../core/sub_app.dart';
import 'screens/courses_list_screen.dart';

class LmsCreatorApp extends SubApp {
  @override
  String get id => 'lms_creator';

  @override
  String get name => 'Course Creator';

  @override
  IconData get icon => Icons.school;

  @override
  Color get themeColor => Colors.deepPurple;

  @override
  Widget build(BuildContext context) {
    return const CoursesListScreen();
  }
}
