import '../core/search_result.dart';
import '../core/app_registry.dart';

/// Service for searching across all apps
class GlobalSearchService {
  static final GlobalSearchService instance = GlobalSearchService._();
  GlobalSearchService._();

  /// Search across all apps that support search
  Future<List<SearchResult>> search(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final allResults = <SearchResult>[];
    final apps = AppRegistry.instance.getAllApps();

    // Search in parallel across all apps
    await Future.wait(
      apps
          .where((app) => app.supportsSearch)
          .map((app) async {
        try {
          final results = await app.search(query);
          allResults.addAll(results);
        } catch (e) {
          // Ignore errors from individual apps
          print('Error searching in ${app.id}: $e');
        }
      }),
    );

    // Sort by timestamp (most recent first)
    allResults.sort((a, b) {
      if (a.timestamp == null && b.timestamp == null) return 0;
      if (a.timestamp == null) return 1;
      if (b.timestamp == null) return -1;
      return b.timestamp!.compareTo(a.timestamp!);
    });

    return allResults;
  }

  /// Search within a specific app
  Future<List<SearchResult>> searchInApp(String appId, String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final app = AppRegistry.instance.getAllApps().firstWhere(
          (app) => app.id == appId,
          orElse: () => throw Exception('App not found: $appId'),
        );

    if (!app.supportsSearch) {
      return [];
    }

    return await app.search(query);
  }
}
