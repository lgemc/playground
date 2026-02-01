import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/open.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

/// Wrapper for cr-sqlite database with CRDT sync support
class CrSqliteDatabase {
  static CrSqliteDatabase? _instance;
  Database? _db;

  CrSqliteDatabase._();

  static CrSqliteDatabase get instance {
    _instance ??= CrSqliteDatabase._();
    return _instance!;
  }

  /// Initialize the database and load cr-sqlite extension
  Future<void> init(String dbName) async {
    if (_db != null) return;

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = path.join(docsDir.path, 'data', dbName);

    // Ensure directory exists
    final dbDir = Directory(path.dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    // Determine library path based on platform
    String libraryPath;
    if (Platform.isLinux) {
      // Linux desktop: cr-sqlite via FFI is complex due to sqlite3 handle incompatibility
      // Fall back to CrdtDatabase instead (sqlite_crdt package)
      throw UnsupportedError('CR-SQLite not supported on Linux - use CrdtDatabase instead');
    } else if (Platform.isAndroid) {
      libraryPath = 'libcrsqlite.so';
    } else if (Platform.isIOS || Platform.isMacOS) {
      libraryPath = './crsqlite.dylib';
    } else {
      throw UnsupportedError('Platform not supported for cr-sqlite');
    }

    try {
      print('🔧 Loading cr-sqlite from: $libraryPath');

      // Open database with extension loading enabled
      _db = sqlite3.open(dbPath, mode: OpenMode.readWriteCreate);
      print('✓ Opened main database at: $dbPath');

      // Enable extension loading (required to load cr-sqlite)
      // This is platform-specific but safe in a controlled environment
      _db!.execute('PRAGMA trusted_schema = ON');

      // Manually load the cr-sqlite extension via FFI
      final crSqliteLib = DynamicLibrary.open(libraryPath);

      // Get the init function from the library
      final initFunction = crSqliteLib.lookup<NativeFunction<Int32 Function(Pointer, Pointer<Pointer<Utf8>>, Pointer)>>('sqlite3_crsqlite_init');

      // Get the database handle from the Dart sqlite3 object
      // The sqlite3 package exposes the raw handle
      final dbHandle = _db!.handle;

      // Call the init function
      final pzErrMsg = calloc<Pointer<Utf8>>();
      pzErrMsg.value = nullptr;

      final cInitFunc = initFunction.asFunction<int Function(Pointer, Pointer<Pointer<Utf8>>, Pointer)>();
      final rc = cInitFunc(Pointer.fromAddress(dbHandle.address), pzErrMsg, nullptr);

      if (rc != 0) {
        final errMsg = pzErrMsg.value == nullptr ? 'Unknown error' : pzErrMsg.value.toDartString();
        calloc.free(pzErrMsg);
        throw Exception('Failed to initialize cr-sqlite: $errMsg (code: $rc)');
      }
      calloc.free(pzErrMsg);

      print('✓ Extension loaded successfully via FFI');

      // Enable foreign keys
      _db!.execute('PRAGMA foreign_keys = ON');

      // Verify extension loaded
      print('🧪 Testing cr-sqlite function...');
      final result = _db!.select("SELECT crsql_version()");
      final version = result.first.values.first;
      print('✅ CR-SQLite loaded successfully! Version: $version');
    } catch (e, stackTrace) {
      print('❌ Failed to load cr-sqlite extension: $e');
      print('   Stack trace: $stackTrace');
      print('   Library path attempted: $libraryPath');
      print('   Make sure the library is bundled with the app');
      rethrow;
    }
  }

  /// Get the database instance (must call init() first)
  Database get db {
    if (_db == null) {
      throw StateError('Database not initialized. Call init() first.');
    }
    return _db!;
  }

  /// Enable CRDT replication on a table
  void enableCrr(String tableName) {
    db.execute("SELECT crsql_as_crr('$tableName')");
    print('✅ Table "$tableName" enabled as CRR (Conflict-free Replicated Relation)');
  }

  /// Get this device's site ID (unique identifier for CRDT sync)
  String getSiteId() {
    final result = db.select("SELECT crsql_site_id()");
    return result.first.values.first as String;
  }

  /// Get local changes since a specific version
  /// Returns changes ready to sync to other devices
  List<Map<String, dynamic>> getChangesSince(int dbVersion) {
    final result = db.select('''
      SELECT
        "table", "pk", "cid", "val", "col_version",
        "db_version", "site_id", cl, seq
      FROM crsql_changes
      WHERE db_version > ? AND site_id = crsql_site_id()
    ''', [dbVersion]);

    return result.map((row) => row).toList();
  }

  /// Apply changes from another device
  /// CR-SQLite automatically handles conflict resolution
  void applyChanges(List<Map<String, dynamic>> changes) {
    for (final change in changes) {
      db.execute(
        '''
        INSERT INTO crsql_changes
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
        [
          change['table'],
          change['pk'],
          change['cid'],
          change['val'],
          change['col_version'],
          change['db_version'],
          change['site_id'],
          change['cl'],
          change['seq'],
        ],
      );
    }
  }

  /// Get current database version (increments with each change)
  int getCurrentVersion() {
    final result = db.select("SELECT crsql_db_version()");
    return result.first.values.first as int;
  }

  /// Close the database
  void close() {
    _db?.dispose();
    _db = null;
  }
}
