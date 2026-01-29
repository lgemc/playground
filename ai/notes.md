# Notes App Implementation Plan

A simple markdown notes app following the SubApp pattern, with Obsidian-like inline editing behavior.

## Requirements Summary

- Note listing, creating, and editing in markdown
- Live preview: renders markdown when cursor leaves, enters edit mode on tap
- Single folder storage (keep it simple)

---

## Architecture

### File Structure

```
lib/apps/notes/
├── notes_app.dart           # SubApp implementation
├── notes_screen.dart        # Main list view
├── note_editor_screen.dart  # Editor with live preview
├── models/
│   └── note.dart            # Note data model
├── services/
│   └── notes_storage.dart   # File-based persistence
└── widgets/
    ├── note_list_tile.dart  # List item widget
    └── markdown_field.dart  # Inline edit/preview widget
```

### Data Storage

```
data/notes/
├── metadata.json            # List of {id, title, updatedAt}
└── {note_id}.md             # Individual note content
```

---

## Implementation Steps

### Phase 1: Core Structure

1. **Create `Note` model** (`lib/apps/notes/models/note.dart`)
   - Fields: `id`, `title`, `content`, `createdAt`, `updatedAt`
   - `fromJson()` / `toJson()` for metadata serialization

2. **Create `NotesStorage` service** (`lib/apps/notes/services/notes_storage.dart`)
   - `loadNotes()` - read metadata.json, return list of notes
   - `loadNoteContent(id)` - read individual .md file
   - `saveNote(note)` - write .md file and update metadata.json
   - `deleteNote(id)` - remove file and update metadata
   - Uses `path_provider` to get app documents directory

3. **Create `NotesApp` SubApp** (`lib/apps/notes/notes_app.dart`)
   - Extend `SubApp` with id: `'notes'`, icon: `Icons.note`, color: `Colors.amber`
   - `build()` returns `NotesScreen`

4. **Register in main.dart**
   - Replace demo notes app with real `NotesApp()`

### Phase 2: List Screen

5. **Create `NotesScreen`** (`lib/apps/notes/notes_screen.dart`)
   - `StatefulWidget` that loads notes on init
   - AppBar with title "Notes" and add (+) button
   - `ListView.builder` showing `NoteListTile` for each note
   - Pull-to-refresh support
   - Empty state with "Create your first note" prompt

6. **Create `NoteListTile` widget** (`lib/apps/notes/widgets/note_list_tile.dart`)
   - Shows title and last modified date
   - Tap navigates to editor
   - Swipe-to-delete with confirmation

### Phase 3: Editor Screen

7. **Create `NoteEditorScreen`** (`lib/apps/notes/note_editor_screen.dart`)
   - Receives optional `Note` (null = new note)
   - AppBar with back button and save indicator
   - Title field (plain text)
   - Body field using `MarkdownField` widget
   - Auto-save on dispose or after debounce

8. **Create `MarkdownField` widget** (`lib/apps/notes/widgets/markdown_field.dart`)
   - The key Obsidian-like component
   - **Edit mode**: Shows `TextField` with markdown source
   - **Preview mode**: Renders markdown with `flutter_markdown` package
   - Behavior:
     - Tap anywhere: enter edit mode, show cursor
     - Focus lost (tap outside): switch to preview mode
     - Uses `FocusNode` to detect focus changes

### Phase 4: Polish

9. **Add dependencies to pubspec.yaml**
   - `path_provider: ^2.1.0` - for file storage paths
   - `flutter_markdown: ^0.6.0` - for markdown rendering

10. **Handle edge cases**
    - Empty title defaults to "Untitled" or first line of content
    - Confirm before discarding unsaved changes
    - Handle storage errors gracefully

---

## Widget Details

### MarkdownField Behavior

```dart
class MarkdownField extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String> onChanged;
}

class _MarkdownFieldState extends State<MarkdownField> {
  late FocusNode _focusNode;
  late TextEditingController _controller;
  bool _isEditing = false;

  @override
  void initState() {
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      setState(() => _isEditing = _focusNode.hasFocus);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: null,
        onChanged: widget.onChanged,
      );
    } else {
      return GestureDetector(
        onTap: () => _focusNode.requestFocus(),
        child: MarkdownBody(data: _controller.text),
      );
    }
  }
}
```

---

## State Management

Keep it simple with `StatefulWidget` and lifting state:
- `NotesScreen` holds the list of notes
- `NoteEditorScreen` holds the current note being edited
- Pass callbacks for save/delete operations

No external state management package needed for this scope.

---

## Testing Strategy

1. **Unit tests** for `Note` model serialization
2. **Unit tests** for `NotesStorage` (mock file system)
3. **Widget tests** for `MarkdownField` focus behavior
4. **Integration test** for create/edit/delete flow

---

## Future Enhancements (Out of Scope)

- Search functionality
- Multiple folders/tags
- Markdown toolbar (bold, italic, links)
- Note linking `[[note-name]]`
- Export to PDF
