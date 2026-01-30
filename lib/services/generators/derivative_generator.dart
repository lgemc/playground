import 'package:flutter/material.dart';
import '../../apps/file_system/models/file_item.dart';

abstract class DerivativeGenerator {
  String get type;
  String get displayName;
  IconData get icon;
  bool canProcess(FileItem file);
  Future<String> generate(FileItem file);
}
