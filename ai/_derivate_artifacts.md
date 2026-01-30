# Derivate Artifacts - Implementation Plan

## Overview

Transform the file system app to support derivative artifacts (summaries, transcripts, etc.) and remove the standalone summaries app. Files can have 0 or more derivatives, each with a type and stored as markdown files.

## Requirements

1. Continue listing files normally
2. When a file is tapped:
   - If it has derivatives → treat like a folder, show the file + all derivatives
   - If no derivatives → open file directly (short tap) OR show derivative generation options (long tap/option button)
3. Each derivative is a markdown file (for now)
4. Different derivative types have different implementations
5. Queue-based generation service for all derivatives
6. Model: File → 0..n Derivatives (each with type and proper file reference)

## Architecture Changes

### 1. Data Model

**New model: `DerivativeArtifact`** (`lib/apps/file_system/models/derivative_artifact.dart`)
```dart
class DerivativeArtifact {
  final String id;
  final String fileId;           // Parent file ID
  final String type;             // 'summary', 'transcript', 'translation', etc.
  final String derivativePath;   // Path to .md file
  final String status;           // 'pending', 'processing', 'completed', 'failed'
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? errorMessage;
}
```

**Database changes** (`lib/apps/file_system/services/file_system_storage.dart`)
- Add `derivatives` table with columns matching DerivativeArtifact
- Index on `file_id` for fast lookups
- Index on `status` for queue processing

### 2. File System Storage Updates

**New methods in `FileSystemStorage`:**
- `Future<List<DerivativeArtifact>> getDerivatives(String fileId)`
- `Future<DerivativeArtifact> createDerivative(String fileId, String type)`
- `Future<void> updateDerivative(String id, {String? status, String? content, String? error})`
- `Future<void> deleteDerivative(String id)`
- `Future<bool> hasDerivatives(String fileId)`

**Storage structure:**
- Derivatives stored in: `data/file_system/derivatives/{derivative_id}.md`

### 3. UI Changes

**File Browser Screen** (`lib/apps/file_system/screens/file_browser_screen.dart`)

Modify `_openFile()` method:
```dart
void _openFile(FileItem file) async {
  final hasDerivatives = await FileSystemStorage.instance.hasDerivatives(file.id);

  if (hasDerivatives) {
    // Navigate to derivatives view
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FileDerivativesScreen(file: file),
      ),
    );
  } else {
    // Open file directly (existing behavior)
    _openFileDirect(file);
  }
}
```

**File Tile Widget** (`lib/apps/file_system/widgets/file_tile.dart`)

Update to show derivative indicator:
- Add visual badge/icon if file has derivatives
- Change long press to show derivative generation menu (if no derivatives)

**New Screen: `FileDerivativesScreen`** (`lib/apps/file_system/screens/file_derivatives_screen.dart`)
- Show original file at top
- List all derivatives below
- Tap derivative → open in markdown viewer
- FAB to add new derivative
- Show status badges (pending, processing, completed, failed)

**New Screen: `DerivativeGeneratorDialog`** (`lib/apps/file_system/screens/derivative_generator_dialog.dart`)
- Modal dialog showing available derivative types
- Each type with description and icon
- "Generate" button enqueues the task

### 4. Derivative Generation Service

**New Service: `DerivativeService`** (`lib/services/derivative_service.dart`)

Singleton service managing derivative generation:
```dart
class DerivativeService {
  static final instance = DerivativeService._();

  // Registry of derivative generators
  Map<String, DerivativeGenerator> _generators = {};

  void registerGenerator(String type, DerivativeGenerator generator);
  Future<void> generateDerivative(String fileId, String type);
  List<String> getAvailableTypes(FileItem file);
}
```

**Abstract Generator Interface:**
```dart
abstract class DerivativeGenerator {
  String get type;
  String get displayName;
  IconData get icon;
  bool canProcess(FileItem file);
  Future<String> generate(FileItem file);
}
```

**Concrete Generators:**
- `SummaryGenerator` - PDF summarization (migrate from summaries app)
- `TranscriptGenerator` - Video/audio transcription (future)
- `TranslationGenerator` - Text translation (future)

### 5. Queue Integration

**Queue Configuration** (`lib/services/queue_config.dart`)

Add new queue:
```dart
'derivative-processor': QueueConfig(
  id: 'derivative-processor',
  maxRetries: 3,
  retryDelay: Duration(seconds: 5),
  consumers: [
    DerivativeQueueConsumer(),
  ],
)
```

**New Consumer: `DerivativeQueueConsumer`** (`lib/services/derivative_queue_consumer.dart`)
- Listen for `derivative.create` events
- Load derivative from database
- Find appropriate generator by type
- Generate content
- Update derivative status and save content
- Handle errors with retry logic

### 6. Migration from Summaries App

**Steps:**
1. Create derivative generators registry
2. Migrate `SummaryGenerator` from summaries app logic
3. Create migration script to convert existing summaries to derivatives
4. Remove summaries app registration from `main.dart`
5. Delete `lib/apps/summaries/` directory

**Migration Script:**
```dart
// One-time migration in file_system_storage.dart init()
Future<void> _migrateSummariesToDerivatives() async {
  // Read summaries from old database
  // For each summary, create a derivative record
  // Copy summary markdown files
  // Mark migration as complete in config
}
```

## Implementation Order

### Phase 1: Core Data Layer
1. ✅ Create `DerivativeArtifact` model
2. ✅ Update `FileSystemStorage` with derivatives table
3. ✅ Implement CRUD methods for derivatives

### Phase 2: Service Layer
4. ✅ Create `DerivativeService` and generator interface
5. ✅ Create `SummaryGenerator` (migrate from summaries app)
6. ✅ Create `DerivativeQueueConsumer`
7. ✅ Register queue in config

### Phase 3: UI Layer
8. ✅ Create `FileDerivativesScreen`
9. ✅ Create `DerivativeGeneratorDialog`
10. ✅ Update `FileTile` with derivative indicator
11. ✅ Update `file_browser_screen.dart` tap handling

### Phase 4: Migration & Cleanup
12. ✅ Implement summaries migration
13. ✅ Test migration with existing data
14. ✅ Remove summaries app
15. ✅ Update launcher and app registry

## File Structure

```
lib/
├── apps/
│   └── file_system/
│       ├── models/
│       │   ├── derivative_artifact.dart       [NEW]
│       │   ├── file_item.dart
│       │   └── folder_item.dart
│       ├── screens/
│       │   ├── file_derivatives_screen.dart   [NEW]
│       │   ├── derivative_generator_dialog.dart [NEW]
│       │   └── file_browser_screen.dart       [MODIFY]
│       ├── widgets/
│       │   ├── file_tile.dart                 [MODIFY]
│       │   └── derivative_tile.dart           [NEW]
│       └── services/
│           └── file_system_storage.dart       [MODIFY]
├── services/
│   ├── derivative_service.dart                [NEW]
│   ├── generators/
│   │   ├── derivative_generator.dart          [NEW - interface]
│   │   ├── summary_generator.dart             [NEW - migrate from summaries]
│   │   └── transcript_generator.dart          [FUTURE]
│   └── derivative_queue_consumer.dart         [NEW]
```

## Testing Strategy

1. Unit tests for `DerivativeArtifact` model
2. Integration tests for `FileSystemStorage` derivative methods
3. Unit tests for `SummaryGenerator`
4. E2E tests for file tap behavior with/without derivatives
5. Migration test with sample summaries data

## Future Enhancements

- Video transcript generation
- Audio transcript generation
- Text translation derivatives
- Custom derivative types via plugins
- Derivative versioning (multiple versions of same derivative)
- Derivative sharing between files (e.g., shared transcripts)
