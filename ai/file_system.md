# File System App

A minimal file storage app for managing videos, audio, documents, and other files with folder navigation, search, and favorites.

## Overview

**Goal**: Google Drive-like experience with minimal features but fully usable.

**Core Features**:
- Browse files and folders
- Navigate with breadcrumb trail
- Create folders and subfolders
- Mark files as favorites
- Search files by name
- Export/share files
- Import files from device

## Architecture

### Hybrid Storage Approach

**Real filesystem directories** + **SQLite for metadata**

This gives us:
- Fast search via database queries
- Easy favorites with boolean column
- Simple export (just copy the folder)
- Files accessible outside the app

### Directory Structure

```
data/file_system/
├── file_system.db          # SQLite database
└── storage/                # Actual files
    ├── documents/
    │   └── work/
    │       └── report.pdf
    ├── photos/
    │   └── vacation/
    │       └── beach.jpg
    └── music/
        └── song.mp3
```

## Database Schema

Single table approach - folders exist only on disk.

```sql
CREATE TABLE files (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  relative_path TEXT NOT NULL UNIQUE,  -- "documents/work/report.pdf"
  folder_path TEXT NOT NULL,            -- "documents/work/"
  mime_type TEXT,
  size INTEGER,
  is_favorite INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Indexes for performance
CREATE INDEX idx_files_folder ON files(folder_path);
CREATE INDEX idx_files_favorite ON files(is_favorite);
CREATE INDEX idx_files_name ON files(name COLLATE NOCASE);
```

### Why No Folders Table?

- Folders are real directories on disk
- Listing folders = `Directory.list()` filtering for directories
- Less complexity, fewer sync issues
- Empty folders still exist (filesystem handles it)

## File Structure

```
lib/apps/file_system/
├── file_system_app.dart        # SubApp implementation
├── models/
│   ├── file_item.dart          # File metadata model
│   └── folder_item.dart        # Simple folder model (name, path)
├── services/
│   └── file_system_storage.dart # DB + filesystem operations
├── screens/
│   ├── file_browser_screen.dart # Main browsing screen
│   ├── favorites_screen.dart    # Starred files view
│   └── search_screen.dart       # Search interface
└── widgets/
    ├── file_grid.dart           # Grid layout of files/folders
    ├── file_tile.dart           # Single file/folder tile
    ├── folder_breadcrumb.dart   # Navigation breadcrumb
    └── add_menu.dart            # FAB menu (add file, folder)
```

## Models

### FileItem

```dart
class FileItem {
  final String id;
  final String name;
  final String relativePath;
  final String folderPath;
  final String? mimeType;
  final int size;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get extension => name.contains('.') ? name.split('.').last : '';

  bool get isImage => mimeType?.startsWith('image/') ?? false;
  bool get isVideo => mimeType?.startsWith('video/') ?? false;
  bool get isAudio => mimeType?.startsWith('audio/') ?? false;
}
```

### FolderItem

```dart
class FolderItem {
  final String name;
  final String path;  // "documents/work/"

  String get parentPath {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) return '';
    return '${parts.sublist(0, parts.length - 1).join('/')}/';
  }
}
```

## Service Layer

### FileSystemStorage

```dart
class FileSystemStorage {
  // Singleton
  static final instance = FileSystemStorage._();

  late Database _db;
  late Directory _storageDir;

  // === Initialization ===
  Future<void> init() async;

  // === File Operations ===
  Future<FileItem> addFile(File sourceFile, String targetFolderPath) async;
  Future<void> deleteFile(String id) async;
  Future<void> renameFile(String id, String newName) async;
  Future<void> moveFile(String id, String newFolderPath) async;
  Future<void> toggleFavorite(String id) async;

  // === Folder Operations ===
  Future<void> createFolder(String name, String parentPath) async;
  Future<void> deleteFolder(String path) async;  // Must be empty
  Future<void> renameFolder(String oldPath, String newName) async;

  // === Queries ===
  Future<List<FileItem>> getFilesInFolder(String folderPath) async;
  Future<List<FolderItem>> getFoldersInPath(String folderPath) async;
  Future<List<FileItem>> getFavorites() async;
  Future<List<FileItem>> search(String query) async;

  // === Export ===
  Future<File> getFileForExport(String id) async;
  String getAbsolutePath(FileItem file);
}
```

### Key Implementation Details

**Adding a file**:
1. Copy file to `storage/{folderPath}/{filename}`
2. Handle name conflicts (append number)
3. Detect MIME type
4. Insert record in database

**Deleting a file**:
1. Delete from filesystem
2. Delete from database

**Creating a folder**:
1. Create directory on disk
2. No database entry needed

**Search**:
```sql
SELECT * FROM files
WHERE name LIKE '%query%' COLLATE NOCASE
ORDER BY name
LIMIT 50;
```

## UI Design

### Main Screen Layout

```
┌─────────────────────────────────────┐
│ ☰  File System           🔍    ⋮   │  ← AppBar
├─────────────────────────────────────┤
│ 🏠 > Documents > Work               │  ← Breadcrumb (tappable)
├─────────────────────────────────────┤
│                                     │
│  ┌────────┐  ┌────────┐  ┌────────┐│
│  │  📁    │  │  📁    │  │  📄    ││
│  │        │  │        │  │     ⭐ ││  ← Grid view
│  │ Photos │  │ Music  │  │ Report ││
│  └────────┘  └────────┘  └────────┘│
│                                     │
│  ┌────────┐  ┌────────┐            │
│  │  🎵    │  │  🎬    │            │
│  │        │  │        │            │
│  │ Song   │  │ Video  │            │
│  └────────┘  └────────┘            │
│                                     │
│                              (＋)   │  ← FAB
├─────────────────────────────────────┤
│   🏠        ⭐        📁           │  ← Bottom nav
│  Home    Favorites   Browse        │
└─────────────────────────────────────┘
```

### Bottom Navigation

| Tab | Icon | Description |
|-----|------|-------------|
| Home | 🏠 | Root folder view |
| Favorites | ⭐ | All starred files |
| Browse | 📁 | Current folder (remembers location) |

### FAB Menu (Add)

Long press or tap FAB to show options:
- 📁 New Folder
- 📄 Add File (file picker)
- 📷 Take Photo (camera)

### File Tile

```
┌──────────────────┐
│                  │
│     [Icon]       │  ← Type-based icon or thumbnail
│                  │
│  filename.pdf  ⭐│  ← Name + favorite indicator
│  2.4 MB          │  ← Size (optional)
└──────────────────┘
```

**Icons by type**:
- 📁 Folder
- 📄 Document (pdf, doc, txt)
- 🖼️ Image (jpg, png, gif)
- 🎵 Audio (mp3, wav)
- 🎬 Video (mp4, mov)
- 📦 Archive (zip, tar)
- 📎 Other

### Context Menu (Long Press)

- ⭐ Add to Favorites / Remove from Favorites
- ✏️ Rename
- 📤 Export / Share
- 🗑️ Delete
- 📁 Move to... (future enhancement)

### Search Screen

```
┌─────────────────────────────────────┐
│ ←  [Search files...          ]  ✕  │
├─────────────────────────────────────┤
│                                     │
│ Results for "report"                │
│                                     │
│  📄 report.pdf                      │
│     documents/work/                 │
│                                     │
│  📄 annual-report.xlsx              │
│     documents/                      │
│                                     │
└─────────────────────────────────────┘
```

### Favorites Screen

Same grid layout as browser, but:
- No folders shown
- Shows folder path under file name
- Tap navigates to file location

## State Management

Use `StatefulWidget` with `setState` for simplicity, or a simple `ChangeNotifier`:

```dart
class FileBrowserState extends ChangeNotifier {
  String currentPath = '';
  List<FolderItem> folders = [];
  List<FileItem> files = [];
  bool isLoading = false;

  Future<void> navigateTo(String path) async;
  Future<void> refresh() async;
  void goUp();  // Navigate to parent
}
```

## Implementation Phases

### Phase 1: Core Infrastructure
- [ ] Create `file_system_app.dart` (SubApp)
- [ ] Create `FileItem` and `FolderItem` models
- [ ] Implement `FileSystemStorage` service
  - [ ] Database initialization
  - [ ] Basic CRUD operations
- [ ] Register app in `main.dart`

### Phase 2: Basic UI
- [ ] Create `file_browser_screen.dart`
- [ ] Implement `file_grid.dart` widget
- [ ] Implement `file_tile.dart` widget
- [ ] Add folder navigation
- [ ] Implement `folder_breadcrumb.dart`

### Phase 3: File Operations
- [ ] Add file import (file picker)
- [ ] Create folder dialog
- [ ] Delete file/folder
- [ ] Rename file/folder
- [ ] Toggle favorite

### Phase 4: Search & Favorites
- [ ] Implement `search_screen.dart`
- [ ] Implement `favorites_screen.dart`
- [ ] Add bottom navigation

### Phase 5: Export & Polish
- [ ] Share/export functionality
- [ ] File type icons
- [ ] Image thumbnails (optional)
- [ ] Empty state UI
- [ ] Error handling

## Dependencies

```yaml
dependencies:
  sqflite: ^2.3.0        # Already in project
  path_provider: ^2.1.0  # Already in project
  file_picker: ^6.1.1    # For importing files
  share_plus: ^7.2.1     # For exporting/sharing
  mime: ^1.0.4           # MIME type detection
```

## Export Strategy

**Single file export**:
```dart
Future<void> exportFile(FileItem file) async {
  final absolutePath = storage.getAbsolutePath(file);
  await Share.shareXFiles([XFile(absolutePath)]);
}
```

**Bulk export** (future):
- Select multiple files
- Copy to Downloads folder or share as zip

## Edge Cases

| Case | Handling |
|------|----------|
| File name conflict | Append number: `file (1).pdf` |
| Delete non-empty folder | Show error, must delete contents first |
| File deleted outside app | Handle gracefully, remove from DB on next access |
| Very long file names | Truncate with ellipsis in UI |
| Unsupported file type | Store anyway, show generic icon |

## Future Enhancements (Out of Scope)

- [ ] Move files between folders
- [ ] Multi-select operations
- [ ] Sort options (name, date, size)
- [ ] List view toggle
- [ ] File preview
- [ ] Cloud sync
- [ ] Tags/labels
- [ ] Recent files
