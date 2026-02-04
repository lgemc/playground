import 'package:flutter/material.dart';
import '../../core/sub_app.dart';
import 'screens/video_player_screen.dart';

class VideoViewerApp extends SubApp {
  @override
  String get id => 'video_viewer';

  @override
  String get name => 'Video Viewer';

  @override
  IconData get icon => Icons.play_circle;

  @override
  Color get themeColor => Colors.deepPurple;

  @override
  Widget build(BuildContext context) {
    return const VideoPlayerScreen();
  }
}
