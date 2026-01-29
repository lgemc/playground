# Summaries Feature Implementation Plan

## Overview

When navigating the file system app and finding a text file (PDF or markdown), users can share it with a summary app that processes the file, extracts text, generates a summary using the completions API, and stores the result.

## Requirements

1. Process file types and extract raw text (starting with PDF support)
2. Call completions API with raw text and prompt to get summary
3. Store summary with file reference (by ID, not path)
4. Open source file in its folder and select it when tapped
5. Store summary as markdown file in file system
6. Handle summary task asynchronously via queue system
7. Implement summarizer service that listens to queue and processes summaries

## Implementation Plan

### 1. Text Extraction Library (`lib/services/text_extractors/`)
- Create base `TextExtractor` interface
- Implement `PdfTextExtractor` using a PDF library (e.g., `pdf_text` or `syncfusion_flutter_pdf`)
- Extensible for future file types (markdown, txt, etc.)

### 2. Summary Service (`lib/services/summary_service.dart`)
- Integrate with existing completions API
- Accept raw text + prompt, return summary
- Handle API errors and retries

### 3. Data Model (`lib/apps/summaries/models/summary.dart`)
- `Summary` class with:
  - `id`: unique identifier
  - `fileId`: reference to source file (not path)
  - `summaryText`: markdown content
  - `createdAt`: timestamp
  - `status`: pending/completed/failed

### 4. Storage Layer (`lib/apps/summaries/services/summary_storage.dart`)
- Store summaries as markdown files in file system
- Metadata stored separately (JSON or SQLite)
- Use `FileSystemService` for file operations

### 5. Queue System (`lib/services/queue_service.dart`)
- Generic queue service for async tasks
- Support task types (summary, future tasks)
- Persist queue to handle app restarts
- Event-driven task processing

### 6. Summarizer Service (`lib/services/summarizer_service.dart`)
- Listen to queue for summary tasks
- Extract text → call API → save summary
- Update task status in queue

### 7. File System App Integration
- Add "Share for Summary" action on PDF/text files
- Implement file selection by ID navigation
- Handle file path/name changes gracefully

### 8. Summaries Sub-App (`lib/apps/summaries/`)
- List view of all summaries
- Tap summary to view content
- Tap file reference to open source in File System app
- Show status (pending/completed/failed)

### 9. Integration Flow
```
FileSystem share → Create queue task → Summarizer processes → Store summary → UI updates
```

### 10. Testing
- Unit tests for text extraction, queue, summary service
- Integration test for complete workflow
- UI tests for summaries app

## Architecture Notes

### Data Directory Structure
```
data/
  summaries/
    settings.json
    metadata.json (summary metadata)
    summaries/
      {summary_id}.md (actual summary content)
```

### Dependencies
- PDF extraction library (e.g., `pdf_text`, `syncfusion_flutter_pdf`)
- Existing completions API service
- File system service (already implemented)
- Queue service (to be implemented)

### File Reference Strategy
- Use file ID from file system service
- File system service must support lookup by ID
- Handle cases where source file is deleted or moved

# About real time streaming

Similar to vocabulary, it must show in real time the streamed response of the summary to improve ux.