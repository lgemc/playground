# Auto File Title - Implementation Plan

## Overview
Add AI-powered automatic file naming as a derivative generator in the existing file system derivative infrastructure. The feature will generate accurate, content-based titles for markdown and PDF files.

## Architecture

### Integration Points
- **Derivative System**: Leverage existing `DerivativeService`, `DerivativeQueueConsumer`, and `DerivativeGenerator` infrastructure
- **Queue Management**: Uses existing queue system for async processing
- **Storage**: Uses `FileSystemStorage` for derivative tracking and file operations

### New Components

#### 1. `AutoTitleGenerator` (extends `DerivativeGenerator`)
**Location**: `lib/services/generators/auto_title_generator.dart`

**Responsibilities**:
- Implements `DerivativeGenerator` interface
- Determines file type (markdown vs PDF) and extracts relevant content
- Calls AI service to generate title
- Returns proposed filename (without extension)

**Key Methods**:
```dart
@override
String get type => 'auto_title';

@override
String get displayName => 'Auto-Generate Title';

@override
IconData get icon => Icons.drive_file_rename_outline;

@override
bool canProcess(FileItem file) {
  // Support .md and .pdf files
}

@override
Future<String> generate(FileItem file) {
  // Extract content based on file type
  // Call AutoTitleService to generate title
  // Return title as markdown content
}
```

**Content Extraction**:
- **Markdown**: Read first 40 lines, check for explicit title (# heading)
- **PDF**: Extract first 3 pages, look for title-like content

#### 2. `AutoTitleService`
**Location**: `lib/services/auto_title_service.dart`

**Responsibilities**:
- Singleton service for AI-based title generation
- Handles prompting logic for different file types
- Returns clean filename suggestions

**Key Methods**:
```dart
class AutoTitleService {
  static final instance = AutoTitleService._();

  Future<String> generateTitle({
    required String content,
    required String fileType, // 'markdown' or 'pdf'
    String? currentFilename,
  });
}
```

**AI Prompt Strategy**:
- For markdown: "Analyze this markdown content. If there's an explicit title (# heading), use it literally. Otherwise, generate a concise, descriptive filename based on the content. Return only the filename without extension."
- For PDF: "Analyze the beginning of this document. If there's an explicit title (like in academic papers), extract it literally. Otherwise, generate a concise, descriptive filename. Return only the filename without extension."

#### 3. File Rename Flow
**Location**: Extend `file_system_storage.dart` and handle in derivative completion callback

**Implementation Options**:

**Option A: Derivative with Special Handling**
1. User triggers "Auto-Generate Title" from derivatives menu
2. Creates derivative record (type: 'auto_title', status: 'pending')
3. Queue processes and generates title
4. On completion, UI shows confirmation dialog with proposed name
5. User approves → file is renamed and derivative is marked as applied
6. Derivative content stores: proposed title and rename status

**Option B: Direct Action (Recommended)**
1. Add separate "Rename with AI" action to file menu
2. Still uses derivative infrastructure under the hood
3. Shows loading indicator
4. On completion, automatically shows rename confirmation dialog
5. If approved, renames file immediately
6. Derivative artifact serves as audit trail

### Database Schema Extensions

**No schema changes needed** - existing `derivatives` table supports this:
```sql
-- Existing table is sufficient
derivatives (
  id TEXT PRIMARY KEY,
  file_id TEXT NOT NULL,
  type TEXT NOT NULL,              -- 'auto_title'
  derivative_path TEXT NOT NULL,   -- Path to .md with proposed title
  status TEXT NOT NULL,             -- 'pending', 'processing', 'completed', 'failed'
  created_at TEXT NOT NULL,
  completed_at TEXT,
  error_message TEXT
)
```

### Content Format in Derivative File

The derivative markdown file will contain:
```markdown
# Proposed Title

[Generated Filename]

## Original Filename
[original.pdf]

## Applied
false

## Applied At
null
```

After rename:
```markdown
# Proposed Title

[Generated Filename]

## Original Filename
[original.pdf]

## Applied
true

## Applied At
2026-01-29T10:30:00Z
```

## Implementation Steps

### Phase 1: Core Generator
1. Create `AutoTitleService` with AI prompting logic
2. Create `AutoTitleGenerator` implementing `DerivativeGenerator`
3. Register generator in `main.dart`: `DerivativeService.instance.registerGenerator(AutoTitleGenerator())`
4. Test basic derivative generation (title appears in derivatives list)

### Phase 2: Text Extraction
1. Add markdown reader utility (read first 40 lines)
2. Reuse existing `PdfTextExtractor` with page limit parameter
3. Add title detection heuristics (look for # heading in markdown, title patterns in PDF)

### Phase 3: Rename Flow
1. Add UI to view proposed title from derivative
2. Add "Apply Rename" action in file derivatives screen
3. Implement `FileSystemStorage.renameFile(fileId, newName)`
4. Update derivative status when rename is applied
5. Handle conflicts (file already exists)

### Phase 4: UX Enhancements
1. Add direct "Rename with AI" to file context menu
2. Show inline confirmation dialog with old → new name preview
3. Add undo functionality (store original name in derivative)
4. Add batch rename support (select multiple files)

## File Structure

```
lib/
├── services/
│   ├── auto_title_service.dart          [NEW]
│   ├── generators/
│   │   ├── derivative_generator.dart     [EXISTS]
│   │   ├── summary_generator.dart        [EXISTS]
│   │   └── auto_title_generator.dart     [NEW]
│   ├── derivative_service.dart           [EXISTS]
│   └── derivative_queue_consumer.dart    [EXISTS]
├── apps/
│   └── file_system/
│       ├── screens/
│       │   ├── file_derivatives_screen.dart  [MODIFY - add apply rename action]
│       │   └── derivative_generator_dialog.dart [EXISTS - will show new option]
│       ├── services/
│       │   └── file_system_storage.dart      [MODIFY - add renameFile method]
│       └── widgets/
│           └── file_action_menu.dart         [MODIFY - add "Rename with AI"]
└── main.dart                                 [MODIFY - register AutoTitleGenerator]
```

## Testing Checklist

- [ ] Markdown file with explicit # title → extracts literal title
- [ ] Markdown file without title → generates descriptive title
- [ ] PDF with clear title page → extracts literal title
- [ ] PDF without clear title → generates descriptive title
- [ ] File rename handles conflicts (duplicate names)
- [ ] Derivative status updates correctly
- [ ] Queue processing works async
- [ ] UI shows loading state during generation
- [ ] Confirmation dialog shows old vs new name
- [ ] Cancel rename leaves file unchanged
- [ ] Applied rename updates derivative record

## API Dependencies

**Required**: AI/LLM service for title generation
- Check if existing `SummaryService` can be reused or adapted
- May need to create generic `AIService` for text generation tasks
- Ensure streaming is optional (titles are short, don't need streaming)

## Edge Cases

1. **Very long proposed title**: Truncate to max filename length (255 chars)
2. **Invalid filename characters**: Sanitize (replace `/\:*?"<>|` with `-`)
3. **Empty/whitespace title**: Fallback to "Untitled-[timestamp]"
4. **File locked/in use**: Show error, mark derivative as failed
5. **Same title as current**: Show "No change needed" message
6. **Network failure during generation**: Retry logic via queue system (already handled)

## Future Enhancements

- Support more file types (docx, txt, html)
- Batch rename with preview table
- Smart folder organization based on content
- Auto-apply rename without confirmation (settings toggle)
- Title translation/normalization (remove special chars automatically)