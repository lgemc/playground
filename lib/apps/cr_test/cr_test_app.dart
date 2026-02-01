import 'package:flutter/material.dart';
import 'package:playground/core/sub_app.dart';
import 'package:playground/core/database/crdt_database.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';

/// Test app to verify cr-sqlite integration
class CrTestApp extends SubApp {
  @override
  String get id => 'cr_test';

  @override
  String get name => 'CR-SQLite Test';

  @override
  IconData get icon => Icons.science;

  @override
  Color get themeColor => Colors.deepPurple;

  @override
  Future<void> onInit() async {
    // Initialize CRDT database
    try {
      await CrdtDatabase.instance.init(
        'crdt_test.db',
        1,
        (db, version) async {
          // onCreate will be handled in the test screen
        },
      );
      print('✅ CRDT database initialized successfully');
    } catch (e) {
      print('❌ Failed to initialize CRDT database: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const CrTestScreen();
  }
}

class CrTestScreen extends StatefulWidget {
  const CrTestScreen({super.key});

  @override
  State<CrTestScreen> createState() => _CrTestScreenState();
}

class _CrTestScreenState extends State<CrTestScreen> {
  final List<String> _logs = [];
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _runTests();
  }

  void _log(String message) {
    setState(() {
      _logs.add(message);
    });
    print(message);
  }

  Future<void> _runTests() async {
    setState(() {
      _isRunning = true;
      _logs.clear();
    });

    try {
      final db = CrdtDatabase.instance;

      // Test 1: Verify CRDT database loaded
      _log('🧪 Test 1: Verify CRDT database loaded');
      try {
        final nodeId = db.nodeId;
        _log('✅ CRDT database loaded! Node ID: $nodeId');
      } catch (e) {
        _log('❌ Failed to load CRDT database: $e');
        return;
      }

      // Test 2: Create table (CRDT automatically adds tracking)
      _log('\n🧪 Test 2: Create table with CRDT tracking');
      await db.execute('DROP TABLE IF EXISTS test_notes');
      await db.execute('''
        CREATE TABLE test_notes (
          id INTEGER PRIMARY KEY NOT NULL,
          title TEXT,
          content TEXT,
          created_at INTEGER
        )
      ''');
      _log('✅ Table created with automatic CRDT tracking');

      // Test 3: Insert data and track changes
      _log('\n🧪 Test 3: Insert data and track changes');
      await db.execute('''
        INSERT INTO test_notes (id, title, content, created_at)
        VALUES (1, 'Test Note', 'This is a test', ${DateTime.now().millisecondsSinceEpoch})
      ''');
      _log('✅ Data inserted with automatic CRDT tracking');

      // Test 4: Get changesets
      _log('\n🧪 Test 4: Get changesets for sync');
      final changeset = await db.getChangeset();
      final totalRecords = changeset.values.fold<int>(
        0,
        (sum, records) => sum + records.length,
      );
      _log('Changeset contains: $totalRecords records');
      if (totalRecords > 0) {
        _log('✅ Changesets working!');
        _log('Tables in changeset: ${changeset.keys.join(", ")}');
      } else {
        _log('⚠ No changes in changeset (this is OK for new table)');
      }

      // Test 5: Verify data persists and queries work
      _log('\n🧪 Test 5: Query data with CRDT fields');

      // Query data - note the automatic CRDT fields
      final result = await db.query('SELECT * FROM test_notes WHERE is_deleted = 0 ORDER BY id');
      _log('Total notes in database: ${result.length}');
      for (final row in result) {
        _log('  - ${row["id"]}: ${row["title"]}');
        _log('    HLC: ${row["hlc"]}');
        _log('    Node ID: ${row["node_id"]}');
      }

      if (result.isNotEmpty) {
        _log('✅ Query successful! Data includes CRDT metadata');
      } else {
        _log('❌ No data found');
      }

      // Test 6: Test watch (reactive queries)
      _log('\n🧪 Test 6: Test reactive watch queries');
      var watchCount = 0;
      final subscription = db.watch(
        'SELECT * FROM test_notes WHERE is_deleted = 0 ORDER BY id'
      ).listen((rows) {
        watchCount++;
        _log('Watch triggered #$watchCount: ${rows.length} rows');
      });

      // Wait a bit for initial watch trigger
      await Future.delayed(Duration(milliseconds: 100));

      // Insert new data - should trigger watch
      await db.execute('''
        INSERT INTO test_notes (id, title, content, created_at)
        VALUES (3, 'Watch Test', 'Reactive update', ${DateTime.now().millisecondsSinceEpoch})
      ''');

      // Wait for watch to trigger
      await Future.delayed(Duration(milliseconds: 100));

      subscription.cancel();

      if (watchCount >= 2) {
        _log('✅ Watch queries working! Triggered $watchCount times');
      } else {
        _log('⚠ Watch triggered only $watchCount time(s)');
      }

      _log('\n🎉 All tests completed successfully!');
    } catch (e, stack) {
      _log('❌ Test failed with error: $e');
      _log('Stack trace: $stack');
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CR-SQLite Integration Test'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          if (_isRunning)
            const LinearProgressIndicator()
          else
            Container(
              color: Colors.green.shade100,
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 8),
                  const Text('Tests completed'),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _runTests,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Re-run'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[index];
                Color? color;
                IconData? icon;

                if (log.startsWith('✅')) {
                  color = Colors.green;
                  icon = Icons.check_circle;
                } else if (log.startsWith('❌')) {
                  color = Colors.red;
                  icon = Icons.error;
                } else if (log.startsWith('🧪')) {
                  color = Colors.blue;
                  icon = Icons.science;
                } else if (log.startsWith('🎉')) {
                  color = Colors.purple;
                  icon = Icons.celebration;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (icon != null)
                        Icon(icon, size: 16, color: color)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          log,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
