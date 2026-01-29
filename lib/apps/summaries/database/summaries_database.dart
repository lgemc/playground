import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/sync/database/syncable_table.dart';

part 'summaries_database.g.dart';

/// Summary status enum converter for Drift
class SummaryStatusConverter extends TypeConverter<String, String> {
  const SummaryStatusConverter();

  @override
  String fromSql(String fromDb) => fromDb;

  @override
  String toSql(String value) => value;
}

/// Summaries table with sync support
class Summaries extends Table with SyncableTable {
  /// Reference to file in file system
  TextColumn get fileId => text()();

  /// Cached file name for display
  TextColumn get fileName => text()();

  /// Cached file path
  TextColumn get filePath => text()();

  /// Markdown content of the summary
  TextColumn get summaryText => text().withDefault(const Constant(''))();

  /// Status: pending, processing, completed, failed
  TextColumn get status => text().map(const SummaryStatusConverter())();

  /// When the summary was completed
  DateTimeColumn get completedAt => dateTime().nullable()();

  /// Error message if failed
  TextColumn get errorMessage => text().nullable()();
}

@DriftDatabase(tables: [Summaries])
class SummariesDatabase extends _$SummariesDatabase {
  SummariesDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // Queries
  Future<List<Summary>> getAllSummaries({String? status}) {
    final query = select(summaries)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);

    if (status != null) {
      query.where((t) => t.status.equals(status));
    }

    return query.get();
  }

  Future<Summary?> getSummary(String id) {
    return (select(summaries)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<List<Summary>> getSummariesByFileId(String fileId) {
    return (select(summaries)
          ..where((t) => t.fileId.equals(fileId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<int> insertSummary(SummariesCompanion summary) {
    return into(summaries).insert(summary);
  }

  Future<bool> updateSummary(String id, SummariesCompanion summary) async {
    final count = await (update(summaries)..where((t) => t.id.equals(id)))
        .write(summary);
    return count > 0;
  }

  Future<void> softDeleteSummary(String id, String deviceId) async {
    final now = DateTime.now();
    final summary = await getSummary(id);
    if (summary == null) return;

    await (update(summaries)..where((t) => t.id.equals(id))).write(
      SummariesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        deviceId: Value(deviceId),
        syncVersion: Value(summary.syncVersion + 1),
      ),
    );
  }

  Future<int> getCount({String? status}) async {
    final query = selectOnly(summaries)
      ..addColumns([summaries.id.count()])
      ..where(summaries.deletedAt.isNull());

    if (status != null) {
      query.where(summaries.status.equals(status));
    }

    final result = await query.getSingle();
    return result.read(summaries.id.count()) ?? 0;
  }

  // Sync queries
  Future<List<Summary>> getSummariesSince(DateTime since) {
    return (select(summaries)
          ..where((t) => t.updatedAt.isBiggerOrEqualValue(since))
          ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)]))
        .get();
  }

  Future<List<Summary>> getAllSummariesIncludingDeleted() {
    return (select(summaries)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'data', 'summaries', 'summaries.db'));

    // Ensure directory exists
    await file.parent.create(recursive: true);

    return NativeDatabase(file);
  });
}
