import 'package:flutter/material.dart';
import '../../core/sub_app.dart';
import '../../core/search_result.dart';
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

  @override
  bool get supportsSearch => true;

  @override
  Future<List<SearchResult>> search(String query) async {
    final files = await FileSystemStorage.instance.search(query);
    return files.map((file) {
      return SearchResult(
        id: file.id,
        type: SearchResultType.file,
        appId: id,
        title: file.name,
        subtitle: file.folderPath,
        preview: null,
        navigationData: {'fileId': file.id, 'folderPath': file.folderPath},
        timestamp: file.updatedAt,
      );
    }).toList();
  }

  @override
  void navigateToSearchResult(BuildContext context, SearchResult result) {
    // Navigate to the folder containing the file
    final folderPath = result.navigationData['folderPath'] as String? ?? '';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FileBrowserScreen(initialPath: folderPath),
      ),
    );
  }
}
