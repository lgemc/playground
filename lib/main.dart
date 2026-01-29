import 'package:flutter/material.dart';
import 'core/app_registry.dart';
import 'services/config_service.dart';
import 'services/autocompletion_service.dart';
import 'services/queue_service.dart';
import 'core/logs_storage.dart';
import 'core/sub_app.dart';
import 'apps/launcher/launcher_app.dart';
import 'apps/launcher/launcher_screen.dart';
import 'apps/logs/logs_app.dart';
import 'apps/notes/notes_app.dart';
import 'apps/queues/queues_app.dart';
import 'apps/settings/settings_app.dart';
import 'apps/vocabulary/vocabulary_app.dart';
import 'apps/vocabulary/services/vocabulary_definition_service.dart';
import 'apps/chat/chat_app.dart';
import 'apps/chat/services/chat_title_service.dart';
import 'apps/file_system/file_system_app.dart';
import 'apps/summaries/summaries_app.dart';
import 'services/summarizer_service.dart';
import 'core/app_bus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ConfigService.instance.initialize();
  AutocompletionService.initializeDefaults();
  await LogsStorage.instance.init();
  await AppBus.instance.init();
  await QueueService.instance.init();
  await VocabularyDefinitionService.instance.init();
  await SummarizerService.instance.init();
  _registerApps();
  await _registerEventHandlers();
  runApp(const PlaygroundApp());
}

void _registerApps() {
  final registry = AppRegistry.instance;

  // Register the launcher itself (for testing/display purposes)
  registry.register(LauncherApp());

  // Register apps
  registry.register(SettingsApp());
  registry.register(NotesApp());
  registry.register(VocabularyApp());
  registry.register(ChatApp());
  registry.register(LogsApp());
  registry.register(QueuesApp());
  registry.register(FileSystemApp());
  registry.register(SummariesApp());

  registry.register(_DemoApp(
    id: 'calculator',
    name: 'Calculator',
    icon: Icons.calculate,
    themeColor: Colors.teal,
  ));
}

Future<void> _registerEventHandlers() async {
  final chatApp = AppRegistry.instance.getApp('chat') as ChatApp;
  await chatApp.onInit();
  await ChatTitleService.instance.init(
    storage: chatApp.storage,
  );
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
