import 'package:flutter/material.dart';
import '../../core/sub_app.dart';
import 'services/file_system_storage.dart';
import 'screens/file_browser_screen.dart';

class FileSystemApp extends SubApp {
  @override
  String get id => 'file_system';

  @override
  String get name => 'File System';

  @override
  IconData get icon => Icons.folder;

  @override
  Color get themeColor => Colors.blue;

  @override
  void onInit() {
    super.onInit();
    FileSystemStorage.instance.init();
  }

  @override
  void onDispose() {
    super.onDispose();
    FileSystemStorage.instance.close();
  }

  @override
  Widget build(BuildContext context) {
    return FileBrowserScreen();
  }
}
