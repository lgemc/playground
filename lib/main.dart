import 'package:flutter/material.dart';
import 'core/app_registry.dart';
import 'core/sub_app.dart';
import 'apps/launcher/launcher_app.dart';
import 'apps/launcher/launcher_screen.dart';

void main() {
  _registerApps();
  runApp(const PlaygroundApp());
}

void _registerApps() {
  final registry = AppRegistry.instance;

  // Register the launcher itself (for testing/display purposes)
  registry.register(LauncherApp());

  // Register demo apps for testing
  registry.register(_DemoApp(
    id: 'settings',
    name: 'Settings',
    icon: Icons.settings,
    themeColor: Colors.grey,
  ));

  registry.register(_DemoApp(
    id: 'notes',
    name: 'Notes',
    icon: Icons.note,
    themeColor: Colors.amber,
  ));

  registry.register(_DemoApp(
    id: 'calculator',
    name: 'Calculator',
    icon: Icons.calculate,
    themeColor: Colors.teal,
  ));
}

class PlaygroundApp extends StatelessWidget {
  const PlaygroundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Playground',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      navigatorKey: AppRegistry.instance.navigatorKey,
      home: const LauncherScreen(),
    );
  }
}

/// Demo app for testing the launcher navigation
class _DemoApp extends SubApp {
  @override
  final String id;
  @override
  final String name;
  @override
  final IconData icon;
  @override
  final Color themeColor;

  _DemoApp({
    required this.id,
    required this.name,
    required this.icon,
    required this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: themeColor),
            const SizedBox(height: 16),
            Text(
              name,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Demo sub-app',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
