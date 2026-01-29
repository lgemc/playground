import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
import 'apps/lms/creator/lms_creator_app.dart';
import 'apps/lms/viewer/lms_viewer_app.dart';
import 'core/sync/services/device_sync_service.dart';
import 'core/sync/services/device_id_service.dart';
import 'core/sync/database/sync_database.dart';
import 'apps/vocabulary/services/vocabulary_storage_v2.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite_ffi for desktop platforms
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await ConfigService.instance.initialize();
  AutocompletionService.initializeDefaults();
  await LogsStorage.instance.init();
  await AppBus.instance.init();
  await QueueService.instance.init();
  await VocabularyDefinitionService.instance.init();
  await SummarizerService.instance.init();
  await _initSyncService();
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
  registry.register(LmsCreatorApp());
  registry.register(LmsViewerApp());

  registry.register(_DemoApp(
    id: 'calculator',
    name: 'Calculator',
    icon: Icons.calculate,
    themeColor: Colors.teal,
  ));
}

/// Global sync service singleton
class SyncServiceProvider {
  static DeviceSyncService? _instance;

  static DeviceSyncService? get instance => _instance;

  static void setInstance(DeviceSyncService service) {
    _instance = service;
  }
}

Future<void> _initSyncService() async {
  final deviceIdService = DeviceIdService.instance;
  final syncDatabase = SyncDatabase();

  final syncService = DeviceSyncService(
    deviceIdService: deviceIdService,
    syncDatabase: syncDatabase,
  );

  // Register callbacks for vocabulary app
  syncService.setGetChangesCallback((appId, since) async {
    if (appId == 'vocabulary') {
      return await VocabularyStorageV2.instance.getChangesForSync(since);
    }
    return [];
  });

  syncService.setApplyChangesCallback((appId, entities) async {
    if (appId == 'vocabulary') {
      await VocabularyStorageV2.instance.applyChangesFromSync(entities);
    }
  });

  // Start the sync service (discovery and listening for connections)
  await syncService.start();

  // Make it available globally
  SyncServiceProvider.setInstance(syncService);
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
