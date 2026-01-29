import 'package:flutter/material.dart';

/// Abstract class that all sub-apps must implement.
/// Each sub-app is a self-contained module with its own UI and logic.
abstract class SubApp {
  /// Unique identifier for the app (used for storage and navigation)
  String get id;

  /// Display name shown in the launcher
  String get name;

  /// Icon displayed in the launcher grid
  IconData get icon;

  /// Primary theme color for the app
  Color get themeColor;

  /// Builds the main widget for this sub-app
  Widget build(BuildContext context);

  /// Called when the app is first initialized
  void onInit() {}

  /// Called when the app is disposed
  void onDispose() {}
}