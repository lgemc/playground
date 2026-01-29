import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playground/core/app_registry.dart';
import 'package:playground/core/sub_app.dart';
import 'package:playground/apps/launcher/launcher_app.dart';
import 'package:playground/main.dart';

void main() {
  setUp(() {
    // Register apps before each test
    final registry = AppRegistry.instance;
    registry.register(LauncherApp());
    registry.register(_TestApp(id: 'settings', name: 'Settings'));
    registry.register(_TestApp(id: 'notes', name: 'Notes'));
    registry.register(_TestApp(id: 'calculator', name: 'Calculator'));
  });

  testWidgets('Launcher displays registered apps', (WidgetTester tester) async {
    await tester.pumpWidget(const PlaygroundApp());

    // Verify launcher shows the registered apps
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Calculator'), findsOneWidget);
  });
}

class _TestApp extends SubApp {
  @override
  final String id;
  @override
  final String name;

  _TestApp({required this.id, required this.name});

  @override
  IconData get icon => Icons.apps;

  @override
  Color get themeColor => Colors.blue;

  @override
  Widget build(BuildContext context) => const Scaffold();
}
