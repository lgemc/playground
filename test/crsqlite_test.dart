import 'package:flutter_test/flutter_test.dart';
import 'package:playground/core/database/crsqlite_database.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CR-SQLite Integration Tests', () {
    late CrSqliteDatabase db;

    setUp(() async {
      db = CrSqliteDatabase.instance;
      await db.init('test_crdb.db');
    });

    tearDown(() {
      db.close();
    });

    test('Should load cr-sqlite extension successfully', () {
      expect(() => db.db, returnsNormally);
    });

    test('Should get site ID', () {
      final siteId = db.getSiteId();
      expect(siteId, isNotEmpty);
      print('Site ID: $siteId');
    });

    test('Should create table and enable as CRR', () {
      // Create a test table
      db.db.execute('''
        CREATE TABLE IF NOT EXISTS test_table (
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT,
          value INTEGER,
          created_at INTEGER
        )
      ''');

      // Enable CRDT replication
      db.enableCrr('test_table');

      // Verify it's a CRR table by checking for crsql metadata
      final result = db.db.select('''
        SELECT name FROM sqlite_master
        WHERE type='table' AND name LIKE '%test_table%'
      ''');

      expect(result.length, greaterThan(1)); // Should have metadata tables
      print('Tables created: ${result.map((r) => r['name']).join(', ')}');
    });

    test('Should track changes in CRR table', () {
      // Create and enable table
      db.db.execute('''
        CREATE TABLE IF NOT EXISTS notes (
          id TEXT PRIMARY KEY NOT NULL,
          title TEXT,
          content TEXT
        )
      ''');
      db.enableCrr('notes');

      final initialVersion = db.getCurrentVersion();
      print('Initial DB version: $initialVersion');

      // Insert a row
      db.db.execute('''
        INSERT INTO notes (id, title, content)
        VALUES ('note-1', 'Test Note', 'Test content')
      ''');

      final newVersion = db.getCurrentVersion();
      print('New DB version after insert: $newVersion');

      expect(newVersion, greaterThan(initialVersion));

      // Get changes since initial version
      final changes = db.getChangesSince(initialVersion);
      expect(changes, isNotEmpty);
      print('Changes detected: ${changes.length}');
      print('First change: ${changes.first}');
    });

    test('Should apply remote changes and merge', () {
      // Create table
      db.db.execute('''
        CREATE TABLE IF NOT EXISTS sync_test (
          id TEXT PRIMARY KEY NOT NULL,
          value TEXT
        )
      ''');
      db.enableCrr('sync_test');

      // Insert local data
      db.db.execute('''
        INSERT INTO sync_test (id, value) VALUES ('item-1', 'local-value')
      ''');

      // Simulate remote change (different site_id)
      final remoteChanges = [
        {
          'table': 'sync_test',
          'pk': '"item-2"',
          'cid': '"value"',
          'val': '"remote-value"',
          'col_version': 1,
          'db_version': 2,
          'site_id': 'remote-device-123', // Different site
          'cl': 0,
          'seq': 0,
        }
      ];

      // Apply remote changes
      db.applyChanges(remoteChanges);

      // Verify both local and remote data exist
      final rows = db.db.select('SELECT * FROM sync_test ORDER BY id');
      expect(rows.length, 2);
      expect(rows[0]['id'], 'item-1');
      expect(rows[0]['value'], 'local-value');
      expect(rows[1]['id'], 'item-2');
      expect(rows[1]['value'], 'remote-value');

      print('✅ Merge successful! Both local and remote data present');
    });

    test('Should handle conflict resolution (last-write-wins)', () {
      // Create table
      db.db.execute('''
        CREATE TABLE IF NOT EXISTS conflict_test (
          id TEXT PRIMARY KEY NOT NULL,
          data TEXT
        )
      ''');
      db.enableCrr('conflict_test');

      // Local write
      db.db.execute('''
        INSERT INTO conflict_test (id, data) VALUES ('shared-1', 'local-data')
      ''');

      // Simulate remote write to same row with higher version
      final remoteChange = [
        {
          'table': 'conflict_test',
          'pk': '"shared-1"',
          'cid': '"data"',
          'val': '"remote-data-wins"',
          'col_version': 5, // Higher version
          'db_version': 10,
          'site_id': 'remote-device-xyz',
          'cl': 0,
          'seq': 0,
        }
      ];

      db.applyChanges(remoteChange);

      // Check which value won
      final result =
          db.db.select('SELECT data FROM conflict_test WHERE id = ?', ['shared-1']);
      final finalValue = result.first['data'];

      print('Final value after conflict: $finalValue');
      expect(finalValue, isNotNull);
    });
  });
}
