import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sql_crdt/sql_crdt.dart';
import 'core/app_registry.dart';
import 'core/database/crsqlite_database.dart';
import 'core/database/crdt_database.dart';
import 'services/config_service.dart';
import 'services/autocompletion_service.dart';
import 'services/queue_service.dart';
import 'core/logs_storage.dart';
import 'core/sub_app.dart';
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
import 'apps/file_system/services/file_system_storage.dart';
import 'services/derivative_service.dart';
import 'services/derivative_queue_consumer.dart';
import 'services/generators/summary_generator.dart';
import 'services/generators/auto_title_generator.dart';
import 'services/generators/transcript_generator.dart';
import 'services/whisper_service.dart';
import 'core/app_bus.dart';
import 'apps/lms/creator/lms_creator_app.dart';
import 'apps/lms/viewer/lms_viewer_app.dart';
import 'core/sync/services/device_sync_service.dart';
import 'core/sync/services/device_id_service.dart';
import 'core/sync/database/sync_database.dart';

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

  // Initialize CRDT database (platform-specific)
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    // Desktop: Try CrSqliteDatabase first, fall back to CrdtDatabase
    try {
      await CrSqliteDatabase.instance.init('crdt_main.db');
      print('🔧 [Desktop] CR-SQLite database initialized: ${CrSqliteDatabase.instance.getSiteId()}');

      // Create a test table to enable cr-sqlite tracking
      // This ensures crsql_changes table exists
      CrSqliteDatabase.instance.db.execute('''
        CREATE TABLE IF NOT EXISTS _crdt_metadata (
          id TEXT PRIMARY KEY NOT NULL,
          key TEXT NOT NULL,
          value TEXT,
          updated_at INTEGER
        )
      ''');
      CrSqliteDatabase.instance.enableCrr('_crdt_metadata');
      print('✅ CR-SQLite CRDT tracking enabled');
    } catch (e) {
      print('⚠️  CR-SQLite initialization failed: $e');
      print('   Falling back to CrdtDatabase...');

      // Fall back to CrdtDatabase
      try {
        await CrdtDatabase.instance.init(
          'crdt_test.db',
          5, // Bumped version to 5 for LMS tables
          (db, version) async {
            // Create a metadata table for CRDT
            await db.execute('''
              CREATE TABLE IF NOT EXISTS _crdt_metadata (
                id TEXT PRIMARY KEY NOT NULL,
                key TEXT NOT NULL,
                value TEXT,
                updated_at INTEGER
              )
            ''');

            // Create notes table for CRDT sync
            await db.execute('''
              CREATE TABLE IF NOT EXISTS notes (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');

            // Create chats table for CRDT sync
            await db.execute('''
              CREATE TABLE IF NOT EXISTS chats (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                is_title_generating INTEGER NOT NULL DEFAULT 0,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');

            // Create messages table for CRDT sync
            await db.execute('''
              CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY NOT NULL,
                chat_id TEXT NOT NULL,
                content TEXT NOT NULL,
                is_user INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');

            await db.execute('''
              CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id)
            ''');

            // Create vocabulary_words table for CRDT sync
            await db.execute('''
              CREATE TABLE IF NOT EXISTS vocabulary_words (
                id TEXT PRIMARY KEY NOT NULL,
                word TEXT NOT NULL,
                meaning TEXT NOT NULL DEFAULT '',
                sample_phrases TEXT NOT NULL DEFAULT '[]',
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');

            // Create LMS courses table for CRDT sync
            await db.execute('''
              CREATE TABLE IF NOT EXISTS lms_courses (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                description TEXT,
                thumbnail_file_id TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');

            // Create LMS modules table for CRDT sync
            await db.execute('''
              CREATE TABLE IF NOT EXISTS lms_modules (
                id TEXT PRIMARY KEY NOT NULL,
                course_id TEXT NOT NULL,
                name TEXT NOT NULL,
                description TEXT,
                "order" INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');

            await db.execute('''
              CREATE INDEX IF NOT EXISTS idx_lms_modules_course_id ON lms_modules(course_id)
            ''');

            // Create LMS subsections table for CRDT sync
            await db.execute('''
              CREATE TABLE IF NOT EXISTS lms_subsections (
                id TEXT PRIMARY KEY NOT NULL,
                module_id TEXT NOT NULL,
                name TEXT NOT NULL,
                description TEXT,
                "order" INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');

            await db.execute('''
              CREATE INDEX IF NOT EXISTS idx_lms_subsections_module_id ON lms_subsections(module_id)
            ''');

            // Create LMS activities table for CRDT sync
            await db.execute('''
              CREATE TABLE IF NOT EXISTS lms_activities (
                id TEXT PRIMARY KEY NOT NULL,
                subsection_id TEXT NOT NULL,
                name TEXT NOT NULL,
                description TEXT,
                type TEXT NOT NULL,
                "order" INTEGER NOT NULL,
                file_id TEXT,
                resource_type TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');

            await db.execute('''
              CREATE INDEX IF NOT EXISTS idx_lms_activities_subsection_id ON lms_activities(subsection_id)
            ''');
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            // Migration from version 1 to 2: Add notes table
            if (oldVersion < 2) {
              await db.execute('''
                CREATE TABLE IF NOT EXISTS notes (
                  id TEXT PRIMARY KEY NOT NULL,
                  title TEXT NOT NULL,
                  content TEXT NOT NULL,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL,
                  deleted_at INTEGER,
                  device_id TEXT NOT NULL,
                  sync_version INTEGER NOT NULL DEFAULT 1
                )
              ''');
            }

            // Migration from version 2 to 3: Add chat tables
            if (oldVersion < 3) {
              await db.execute('''
                CREATE TABLE IF NOT EXISTS chats (
                  id TEXT PRIMARY KEY NOT NULL,
                  title TEXT NOT NULL,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL,
                  is_title_generating INTEGER NOT NULL DEFAULT 0,
                  deleted_at INTEGER,
                  device_id TEXT NOT NULL,
                  sync_version INTEGER NOT NULL DEFAULT 1
                )
              ''');

              await db.execute('''
                CREATE TABLE IF NOT EXISTS messages (
                  id TEXT PRIMARY KEY NOT NULL,
                  chat_id TEXT NOT NULL,
                  content TEXT NOT NULL,
                  is_user INTEGER NOT NULL,
                  created_at INTEGER NOT NULL,
                  deleted_at INTEGER,
                  device_id TEXT NOT NULL,
                  sync_version INTEGER NOT NULL DEFAULT 1
                )
              ''');

              await db.execute('''
                CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id)
              ''');
            }

            // Migration from version 3 to 4: Add vocabulary_words table
            if (oldVersion < 4) {
              await db.execute('''
                CREATE TABLE IF NOT EXISTS vocabulary_words (
                  id TEXT PRIMARY KEY NOT NULL,
                  word TEXT NOT NULL,
                  meaning TEXT NOT NULL DEFAULT '',
                  sample_phrases TEXT NOT NULL DEFAULT '[]',
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL,
                  deleted_at INTEGER,
                  device_id TEXT NOT NULL,
                  sync_version INTEGER NOT NULL DEFAULT 1
                )
              ''');
            }

            // Migration from version 4 to 5: Add LMS tables
            if (oldVersion < 5) {
              await db.execute('''
                CREATE TABLE IF NOT EXISTS lms_courses (
                  id TEXT PRIMARY KEY NOT NULL,
                  name TEXT NOT NULL,
                  description TEXT,
                  thumbnail_file_id TEXT,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL,
                  deleted_at INTEGER,
                  device_id TEXT NOT NULL,
                  sync_version INTEGER NOT NULL DEFAULT 1
                )
              ''');

              await db.execute('''
                CREATE TABLE IF NOT EXISTS lms_modules (
                  id TEXT PRIMARY KEY NOT NULL,
                  course_id TEXT NOT NULL,
                  name TEXT NOT NULL,
                  description TEXT,
                  "order" INTEGER NOT NULL,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL,
                  deleted_at INTEGER,
                  device_id TEXT NOT NULL,
                  sync_version INTEGER NOT NULL DEFAULT 1
                )
              ''');

              await db.execute('''
                CREATE INDEX IF NOT EXISTS idx_lms_modules_course_id ON lms_modules(course_id)
              ''');

              await db.execute('''
                CREATE TABLE IF NOT EXISTS lms_subsections (
                  id TEXT PRIMARY KEY NOT NULL,
                  module_id TEXT NOT NULL,
                  name TEXT NOT NULL,
                  description TEXT,
                  "order" INTEGER NOT NULL,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL,
                  deleted_at INTEGER,
                  device_id TEXT NOT NULL,
                  sync_version INTEGER NOT NULL DEFAULT 1
                )
              ''');

              await db.execute('''
                CREATE INDEX IF NOT EXISTS idx_lms_subsections_module_id ON lms_subsections(module_id)
              ''');

              await db.execute('''
                CREATE TABLE IF NOT EXISTS lms_activities (
                  id TEXT PRIMARY KEY NOT NULL,
                  subsection_id TEXT NOT NULL,
                  name TEXT NOT NULL,
                  description TEXT,
                  type TEXT NOT NULL,
                  "order" INTEGER NOT NULL,
                  file_id TEXT,
                  resource_type TEXT,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL,
                  deleted_at INTEGER,
                  device_id TEXT NOT NULL,
                  sync_version INTEGER NOT NULL DEFAULT 1
                )
              ''');

              await db.execute('''
                CREATE INDEX IF NOT EXISTS idx_lms_activities_subsection_id ON lms_activities(subsection_id)
              ''');
            }
          },
        );
        print('✅ CRDT database initialized successfully!');
        print('   Node ID: ${CrdtDatabase.instance.nodeId}');
      } catch (e2) {
        print('❌ CRDT database initialization also failed: $e2');
        print('   Sync will not be available');
      }
    }
  } else {
    // Mobile: Use CrdtDatabase (sqlite_crdt package)
    try {
      await CrdtDatabase.instance.init(
        'crdt_main.db',
        5, // Bumped version to 5 for LMS tables
        (db, version) async {
          // Create a metadata table for CRDT
          await db.execute('''
            CREATE TABLE IF NOT EXISTS _crdt_metadata (
              id TEXT PRIMARY KEY NOT NULL,
              key TEXT NOT NULL,
              value TEXT,
              updated_at INTEGER
            )
          ''');

          // Create notes table for CRDT sync
          await db.execute('''
            CREATE TABLE IF NOT EXISTS notes (
              id TEXT PRIMARY KEY NOT NULL,
              title TEXT NOT NULL,
              content TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER,
              device_id TEXT NOT NULL,
              sync_version INTEGER NOT NULL DEFAULT 1
            )
          ''');

          // Create chats table for CRDT sync
          await db.execute('''
            CREATE TABLE IF NOT EXISTS chats (
              id TEXT PRIMARY KEY NOT NULL,
              title TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              is_title_generating INTEGER NOT NULL DEFAULT 0,
              deleted_at INTEGER,
              device_id TEXT NOT NULL,
              sync_version INTEGER NOT NULL DEFAULT 1
            )
          ''');

          // Create messages table for CRDT sync
          await db.execute('''
            CREATE TABLE IF NOT EXISTS messages (
              id TEXT PRIMARY KEY NOT NULL,
              chat_id TEXT NOT NULL,
              content TEXT NOT NULL,
              is_user INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              deleted_at INTEGER,
              device_id TEXT NOT NULL,
              sync_version INTEGER NOT NULL DEFAULT 1
            )
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id)
          ''');

          // Create vocabulary_words table for CRDT sync
          await db.execute('''
            CREATE TABLE IF NOT EXISTS vocabulary_words (
              id TEXT PRIMARY KEY NOT NULL,
              word TEXT NOT NULL,
              meaning TEXT NOT NULL DEFAULT '',
              sample_phrases TEXT NOT NULL DEFAULT '[]',
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER,
              device_id TEXT NOT NULL,
              sync_version INTEGER NOT NULL DEFAULT 1
            )
          ''');

          // Create LMS courses table for CRDT sync
          await db.execute('''
            CREATE TABLE IF NOT EXISTS lms_courses (
              id TEXT PRIMARY KEY NOT NULL,
              name TEXT NOT NULL,
              description TEXT,
              thumbnail_file_id TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER,
              device_id TEXT NOT NULL,
              sync_version INTEGER NOT NULL DEFAULT 1
            )
          ''');

          // Create LMS modules table for CRDT sync
          await db.execute('''
            CREATE TABLE IF NOT EXISTS lms_modules (
              id TEXT PRIMARY KEY NOT NULL,
              course_id TEXT NOT NULL,
              name TEXT NOT NULL,
              description TEXT,
              "order" INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER,
              device_id TEXT NOT NULL,
              sync_version INTEGER NOT NULL DEFAULT 1
            )
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_lms_modules_course_id ON lms_modules(course_id)
          ''');

          // Create LMS subsections table for CRDT sync
          await db.execute('''
            CREATE TABLE IF NOT EXISTS lms_subsections (
              id TEXT PRIMARY KEY NOT NULL,
              module_id TEXT NOT NULL,
              name TEXT NOT NULL,
              description TEXT,
              "order" INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER,
              device_id TEXT NOT NULL,
              sync_version INTEGER NOT NULL DEFAULT 1
            )
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_lms_subsections_module_id ON lms_subsections(module_id)
          ''');

          // Create LMS activities table for CRDT sync
          await db.execute('''
            CREATE TABLE IF NOT EXISTS lms_activities (
              id TEXT PRIMARY KEY NOT NULL,
              subsection_id TEXT NOT NULL,
              name TEXT NOT NULL,
              description TEXT,
              type TEXT NOT NULL,
              "order" INTEGER NOT NULL,
              file_id TEXT,
              resource_type TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted_at INTEGER,
              device_id TEXT NOT NULL,
              sync_version INTEGER NOT NULL DEFAULT 1
            )
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_lms_activities_subsection_id ON lms_activities(subsection_id)
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // Migration from version 1 to 2: Add notes table
          if (oldVersion < 2) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS notes (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');
          }

          // Migration from version 2 to 3: Add chat tables
          if (oldVersion < 3) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS chats (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                is_title_generating INTEGER NOT NULL DEFAULT 0,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');

            await db.execute('''
              CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY NOT NULL,
                chat_id TEXT NOT NULL,
                content TEXT NOT NULL,
                is_user INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');

            await db.execute('''
              CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id)
            ''');
          }

          // Migration from version 3 to 4: Add vocabulary_words table
          if (oldVersion < 4) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS vocabulary_words (
                id TEXT PRIMARY KEY NOT NULL,
                word TEXT NOT NULL,
                meaning TEXT NOT NULL DEFAULT '',
                sample_phrases TEXT NOT NULL DEFAULT '[]',
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');
          }

          // Migration from version 4 to 5: Add LMS tables
          if (oldVersion < 5) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS lms_courses (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                description TEXT,
                thumbnail_file_id TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');

            await db.execute('''
              CREATE TABLE IF NOT EXISTS lms_modules (
                id TEXT PRIMARY KEY NOT NULL,
                course_id TEXT NOT NULL,
                name TEXT NOT NULL,
                description TEXT,
                "order" INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');

            await db.execute('''
              CREATE INDEX IF NOT EXISTS idx_lms_modules_course_id ON lms_modules(course_id)
            ''');

            await db.execute('''
              CREATE TABLE IF NOT EXISTS lms_subsections (
                id TEXT PRIMARY KEY NOT NULL,
                module_id TEXT NOT NULL,
                name TEXT NOT NULL,
                description TEXT,
                "order" INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');

            await db.execute('''
              CREATE INDEX IF NOT EXISTS idx_lms_subsections_module_id ON lms_subsections(module_id)
            ''');

            await db.execute('''
              CREATE TABLE IF NOT EXISTS lms_activities (
                id TEXT PRIMARY KEY NOT NULL,
                subsection_id TEXT NOT NULL,
                name TEXT NOT NULL,
                description TEXT,
                type TEXT NOT NULL,
                "order" INTEGER NOT NULL,
                file_id TEXT,
                resource_type TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER,
                device_id TEXT NOT NULL,
                sync_version INTEGER NOT NULL DEFAULT 1
              )
            ''');

            await db.execute('''
              CREATE INDEX IF NOT EXISTS idx_lms_activities_subsection_id ON lms_activities(subsection_id)
            ''');
          }
        },
      );
      print('🔧 [Mobile] CRDT database initialized: ${CrdtDatabase.instance.nodeId}');
    } catch (e) {
      print('⚠️  CRDT database initialization failed: $e');
      print('   Sync will not be available');
    }
  }

  // Initialize File System storage early (needed for sync)
  await FileSystemStorage.instance.init();

  VocabularyDefinitionService.instance.start();
  _initDerivativeService();
  _registerApps();
  await _initSyncService(); // Initialize after apps are registered
  await _registerEventHandlers();
  runApp(const PlaygroundApp());
}

void _initDerivativeService() {
  // Initialize Whisper config defaults
  WhisperService.initializeDefaults();

  // Register generators
  DerivativeService.instance.registerGenerator(SummaryGenerator());
  DerivativeService.instance.registerGenerator(AutoTitleGenerator());
  DerivativeService.instance.registerGenerator(TranscriptGenerator());

  // Start the consumer
  final consumer = DerivativeQueueConsumer();
  consumer.start();
}

void _registerApps() {
  final registry = AppRegistry.instance;

  // Register apps
  registry.register(SettingsApp());
  registry.register(NotesApp());
  registry.register(VocabularyApp());
  registry.register(ChatApp());
  registry.register(LogsApp());
  registry.register(QueuesApp());
  registry.register(FileSystemApp());
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

  syncService.setGetChangesCallback((_, since) async {
    try {
      print('[Sync] getChanges called with since: $since');

      // Use CrdtDatabase (works on all platforms as fallback)
      // Use modifiedAfter parameter to filter changes at the database level
      final Hlc? modifiedAfter = since != null
          ? Hlc.fromDate(since, CrdtDatabase.instance.nodeId)
          : null;

      print('[Sync] Calling getChangeset with modifiedAfter: $modifiedAfter');

      final changeset = await CrdtDatabase.instance.db.getChangeset(
        modifiedAfter: modifiedAfter,
      );

      print('[Sync] Raw changeset has ${changeset.length} tables');
      changeset.forEach((table, records) {
        print('[Sync]   Table $table: ${records.length} records');
      });

      // Convert changeset to flat list for protocol compatibility
      final changes = <Map<String, dynamic>>[];
      changeset.forEach((table, records) {
        for (final record in records) {
          changes.add({
            'table': table,
            'data': record,
          });
        }
      });
      print('[Sync] Returning ${changes.length} changes');
      return changes;
    } catch (e, stackTrace) {
      print('[Sync] Error getting changes: $e');
      print('[Sync] Stack trace: $stackTrace');
      return [];
    }
  });

  syncService.setApplyChangesCallback((_, entities) async {
    try {
      // Use CrdtDatabase (works on all platforms as fallback)
      final changeset = <String, List<Map<String, dynamic>>>{};
      for (final entity in entities) {
        final table = entity['table'] as String;
        final data = Map<String, dynamic>.from(entity['data'] as Map<String, dynamic>);

        // Convert HLC strings back to Hlc objects if present
        if (data['hlc'] is String) {
          data['hlc'] = Hlc.parse(data['hlc'] as String);
        }
        if (data['modified'] is String) {
          data['modified'] = Hlc.parse(data['modified'] as String);
        }

        changeset.putIfAbsent(table, () => []).add(data);
      }

      print('[Sync] About to merge changeset:');
      changeset.forEach((table, records) {
        print('  Table: $table, Records: ${records.length}');
        for (final record in records) {
          print('    Record: ${record.keys.join(", ")}');
          if (table == 'notes') {
            print('      id: ${record['id']}, title: ${record['title']}');
          }
        }
      });

      await CrdtDatabase.instance.merge(changeset);
      print('[Sync] Merged ${entities.length} changes');

      // Debug: Query the database to verify the merge
      final notes = await CrdtDatabase.instance.query('SELECT id, title FROM notes WHERE deleted_at IS NULL');
      print('[Sync] Notes in database after merge: ${notes.length}');
      for (final note in notes) {
        print('  - ${note['id']}: ${note['title']}');
      }
    } catch (e) {
      print('[Sync] Error applying changes: $e');
      rethrow;
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
  await ChatTitleService.instance.init();
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
