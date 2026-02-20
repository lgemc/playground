import 'package:flutter/material.dart';
import '../../../core/database/crdt_database.dart';
import '../../../services/spaced_repetition_service.dart';

class DatabaseMigrationScreen extends StatefulWidget {
  const DatabaseMigrationScreen({super.key});

  @override
  State<DatabaseMigrationScreen> createState() => _DatabaseMigrationScreenState();
}

class _DatabaseMigrationScreenState extends State<DatabaseMigrationScreen> {
  String _status = 'Ready to migrate';
  bool _isMigrating = false;

  Future<void> _createSchedulesForExistingConcepts() async {
    setState(() {
      _isMigrating = true;
      _status = 'Finding existing concepts...';
    });

    try {
      // Get all reviewable items
      final items = await CrdtDatabase.instance.query(
        'SELECT id FROM reviewable_items',
      );

      if (items.isEmpty) {
        setState(() {
          _status = '⚠️ No concepts found. Generate concepts first.';
          _isMigrating = false;
        });
        return;
      }

      setState(() {
        _status = 'Creating schedules for ${items.length} concepts...';
      });

      final itemIds = items.map((row) => row['id'] as String).toList();
      await SpacedRepetitionService.instance.createSchedulesForItems(itemIds);

      // Force all new schedules to be due now (for first review)
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final itemId in itemIds) {
        await CrdtDatabase.instance.execute(
          'UPDATE review_schedules SET next_review_date = ? WHERE reviewable_item_id = ?',
          [now, itemId],
        );
      }

      setState(() {
        _status = '✅ Created schedules for ${items.length} concepts!\n\nGo to any course to see your review progress.';
        _isMigrating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created schedules for ${items.length} concepts!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _status = '❌ Error: $e';
        _isMigrating = false;
      });
    }
  }

  Future<void> _addReviewSchedulesTable() async {
    setState(() {
      _isMigrating = true;
      _status = 'Adding review_schedules table...';
    });

    try {
      // Check if table already exists
      final existing = await CrdtDatabase.instance.query(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='review_schedules'",
      );

      if (existing.isNotEmpty) {
        setState(() {
          _status = '✅ Table already exists!';
          _isMigrating = false;
        });
        return;
      }

      // Create the table
      await CrdtDatabase.instance.execute('''
        CREATE TABLE IF NOT EXISTS review_schedules (
          id TEXT PRIMARY KEY NOT NULL,
          reviewable_item_id TEXT NOT NULL,
          user_id TEXT NOT NULL DEFAULT 'default',
          repetitions INTEGER NOT NULL DEFAULT 0,
          ease_factor REAL NOT NULL DEFAULT 2.5,
          interval_days INTEGER NOT NULL DEFAULT 0,
          next_review_date INTEGER NOT NULL,
          correct_count INTEGER NOT NULL DEFAULT 0,
          incorrect_count INTEGER NOT NULL DEFAULT 0,
          retention_rate REAL NOT NULL DEFAULT 0.0,
          last_reviewed INTEGER,
          last_quality INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          FOREIGN KEY (reviewable_item_id) REFERENCES reviewable_items(id) ON DELETE CASCADE
        )
      ''');

      await CrdtDatabase.instance.execute('''
        CREATE INDEX IF NOT EXISTS idx_schedule_item ON review_schedules(reviewable_item_id)
      ''');

      await CrdtDatabase.instance.execute('''
        CREATE INDEX IF NOT EXISTS idx_schedule_user ON review_schedules(user_id)
      ''');

      await CrdtDatabase.instance.execute('''
        CREATE INDEX IF NOT EXISTS idx_schedule_due ON review_schedules(next_review_date, user_id)
      ''');

      await CrdtDatabase.instance.execute('''
        CREATE INDEX IF NOT EXISTS idx_schedule_last_reviewed ON review_schedules(last_reviewed)
      ''');

      await CrdtDatabase.instance.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_schedule_user_item ON review_schedules(reviewable_item_id, user_id)
      ''');

      setState(() {
        _status = '✅ Successfully added review_schedules table!\n\nYou can now use spaced repetition.';
        _isMigrating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Migration complete! Spaced repetition is ready.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _status = '❌ Error: $e';
        _isMigrating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Migration'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Spaced Repetition Setup',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This will add the review_schedules table needed for spaced repetition without deleting any existing data.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _status,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isMigrating ? null : _addReviewSchedulesTable,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
              child: _isMigrating
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Migrating...'),
                      ],
                    )
                  : const Text('Add Review Schedules Table'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isMigrating ? null : _createSchedulesForExistingConcepts,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: _isMigrating
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                        SizedBox(width: 12),
                        Text('Processing...'),
                      ],
                    )
                  : const Text('Create Schedules for Existing Concepts'),
            ),
          ],
        ),
      ),
    );
  }
}
