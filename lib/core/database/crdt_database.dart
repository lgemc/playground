import 'package:sqlite_crdt/sqlite_crdt.dart';
import 'package:sql_crdt/sql_crdt.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

/// Wrapper for CRDT database with automatic conflict resolution
class CrdtDatabase {
  static CrdtDatabase? _instance;
  SqliteCrdt? _db;

  CrdtDatabase._();

  static CrdtDatabase get instance {
    _instance ??= CrdtDatabase._();
    return _instance!;
  }

  /// Initialize the CRDT database
  Future<void> init(
    String dbName,
    int version,
    Future<void> Function(CrdtTableExecutor, int)? onCreate, {
    Future<void> Function(CrdtTableExecutor, int, int)? onUpgrade,
  }) async {
    if (_db != null) return;

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'data', dbName);

    // Ensure directory exists
    final dbDir = Directory(p.dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    print('🔧 Initializing CRDT database at: $dbPath');

    _db = await SqliteCrdt.open(
      dbPath,
      version: version,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    );

    print('✅ CRDT database initialized successfully!');
    print('   Node ID: ${_db!.nodeId}');
  }

  /// Get the database instance (must call init() first)
  SqliteCrdt get db {
    if (_db == null) {
      throw StateError('Database not initialized. Call init() first.');
    }
    return _db!;
  }

  /// Get this node's unique ID (for CRDT conflict resolution)
  String get nodeId => db.nodeId.toString();

  /// Get changeset for syncing to other devices
  /// Returns changes since a specific timestamp
  Future<Map<String, List<Map<String, dynamic>>>> getChangeset() async {
    return db.getChangeset();
  }

  /// Merge changes from another device
  /// Automatically resolves conflicts using CRDT logic
  Future<void> merge(Map<String, List<Map<String, dynamic>>> changeset) async {
    await db.merge(changeset);
    print('✅ Merged changeset from remote device');

    // Note: The sql_crdt package's watch() should automatically emit after merge
    // If it doesn't, we may need to manually trigger a notification
  }

  /// Execute a SQL statement
  Future<void> execute(String sql, [List<Object?>? args]) async {
    await db.execute(sql, args);
  }

  /// Query the database
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?>? args]) async {
    return db.query(sql, args);
  }

  /// Watch a query for changes (reactive)
  /// Returns a stream that emits whenever the query results change
  Stream<List<Map<String, Object?>>> watch(String sql, [List<Object?>? args]) {
    if (args != null) {
      return db.watch(sql, () => args);
    }
    return db.watch(sql);
  }

  /// Execute a transaction
  Future<void> transaction(Future<void> Function(CrdtExecutor txn) action) async {
    await db.transaction(action);
  }

  /// Close the database
  void close() {
    _db?.close();
    _db = null;
  }
}
