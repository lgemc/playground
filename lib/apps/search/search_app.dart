import 'package:flutter/material.dart';
import '../../core/sub_app.dart';
import 'screens/search_screen.dart';

class SearchApp extends SubApp {
  @override
  String get id => 'search';

  @override
  String get name => 'Search';

  @override
  IconData get icon => Icons.search;

  @override
  Color get themeColor => Colors.purple;

  @override
  Widget build(BuildContext context) {
    return const SearchScreen();
  }
}
