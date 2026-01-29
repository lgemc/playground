# Share Service

Inter-app content sharing system. One-way fire-and-forget sharing with user-initiated share buttons on all app elements.

## Overview

The Share Service enables apps to share content with other apps. Users trigger sharing via share buttons placed alongside delete buttons in list views. A bottom sheet presents compatible destination apps based on content type.

## Content Types

```dart
enum ShareContentType {
  text,       // Plain text (word, phrase, snippet)
  note,       // Full note with title/body
  file,       // File reference (path, name, metadata)
  url,        // URL/link
  json,       // Structured data (for advanced use cases)
}
```

## ShareContent Model

```dart
class ShareContent {
  final String id;
  final ShareContentType type;
  final String sourceAppId;
  final Map<String, dynamic> data;
  final DateTime timestamp;
}
```

Data payloads by type:
- **text**: `{ 'text': 'the content' }`
- **note**: `{ 'title': '...', 'body': '...', 'format': 'markdown' }`
- **file**: `{ 'path': '...', 'name': '...', 'mimeType': '...' }`
- **url**: `{ 'url': '...', 'title': '...' }`
- **json**: `{ 'data': {...}, 'schema': '...' }`

## ShareService

Singleton service at `lib/services/share_service.dart`.

```dart
class ShareService {
  static ShareService? _instance;
  static ShareService get instance => _instance ??= ShareService._();

  // Registry of apps and their accepted content types
  final Map<String, List<ShareContentType>> _receivers = {};

  // Register an app as a receiver for content types
  void registerReceiver(String appId, List<ShareContentType> acceptedTypes);

  // Unregister an app
  void unregisterReceiver(String appId);

  // Get apps that can receive a content type
  List<String> getReceiversFor(ShareContentType type);

  // Share content - shows picker if multiple receivers, direct if single
  Future<bool> share(BuildContext context, ShareContent content);

  // Share directly to a specific app (bypasses picker)
  Future<bool> shareTo(String targetAppId, ShareContent content);
}
```

## SubApp Integration

Extend SubApp to declare receiver capabilities:

```dart
abstract class SubApp {
  // ... existing ...

  /// Content types this app can receive (empty = can't receive)
  List<ShareContentType> get acceptedShareTypes => [];

  /// Called when content is shared to this app
  Future<void> onReceiveShare(ShareContent content) async {}
}
```

Apps declare what they accept and implement `onReceiveShare` to handle incoming content.

## App Registration

In `AppRegistry`, after registering an app, also register its share capabilities:

```dart
void register(SubApp app) {
  // ... existing registration ...

  if (app.acceptedShareTypes.isNotEmpty) {
    ShareService.instance.registerReceiver(app.id, app.acceptedShareTypes);
  }
}
```

## UI Components

### ShareButton Widget

Reusable button for list tiles:

```dart
class ShareButton extends StatelessWidget {
  final ShareContent content;
  final VoidCallback? onShared; // Optional callback after share completes

  // Renders an IconButton with share icon
  // On tap, calls ShareService.instance.share(context, content)
}
```

### ShareSheet Widget

Bottom sheet showing available destination apps:

```dart
class ShareSheet extends StatelessWidget {
  final ShareContent content;
  final List<SubApp> receivers;

  // Grid/list of app icons with names
  // Tapping an app calls ShareService.shareTo() and closes sheet
}
```

### List Tile Integration

Update list tiles to include share button in trailing area:

**Before (note_list_tile.dart):**
```dart
trailing: const Icon(Icons.chevron_right),
```

**After:**
```dart
trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    ShareButton(
      content: ShareContent(
        type: ShareContentType.note,
        sourceAppId: 'notes',
        data: {'title': note.title, 'body': note.body, 'format': 'markdown'},
      ),
    ),
    const Icon(Icons.chevron_right),
  ],
),
```

Alternatively, use a `PopupMenuButton` for more actions:
```dart
trailing: PopupMenuButton<String>(
  itemBuilder: (context) => [
    PopupMenuItem(value: 'share', child: Text('Share')),
    PopupMenuItem(value: 'delete', child: Text('Delete')),
  ],
  onSelected: (value) {
    if (value == 'share') _handleShare();
    if (value == 'delete') onDelete();
  },
),
```

## Event Emission

When sharing succeeds, emit an event to AppBus for logging/analytics:

```dart
await AppBus.instance.emit(AppEvent.create(
  type: 'share.completed',
  appId: content.sourceAppId,
  metadata: {
    'targetAppId': targetAppId,
    'contentType': content.type.name,
    'contentId': content.id,
  },
));
```

## Example: Vocabulary App Receiving Text

```dart
class VocabularyApp extends SubApp {
  @override
  List<ShareContentType> get acceptedShareTypes => [ShareContentType.text];

  @override
  Future<void> onReceiveShare(ShareContent content) async {
    if (content.type == ShareContentType.text) {
      final text = content.data['text'] as String;
      // Create new word entry from shared text
      await _storage.createWord(Word(word: text, meaning: ''));
    }
  }
}
```

## Example: Notes App Receiving Multiple Types

```dart
class NotesApp extends SubApp {
  @override
  List<ShareContentType> get acceptedShareTypes => [
    ShareContentType.text,
    ShareContentType.note,
    ShareContentType.url,
  ];

  @override
  Future<void> onReceiveShare(ShareContent content) async {
    switch (content.type) {
      case ShareContentType.text:
        // Create note with text as body
        await _createNoteFromText(content.data['text']);
        break;
      case ShareContentType.note:
        // Import note directly
        await _importNote(content.data);
        break;
      case ShareContentType.url:
        // Create note with URL as content
        await _createNoteFromUrl(content.data);
        break;
      default:
        break;
    }
  }
}
```

## Implementation Steps

1. **Create ShareContent model** (`lib/services/share_content.dart`)
   - ShareContentType enum
   - ShareContent class with factory constructor

2. **Create ShareService** (`lib/services/share_service.dart`)
   - Singleton with receiver registry
   - share() and shareTo() methods
   - Event emission on success

3. **Create ShareSheet widget** (`lib/widgets/share_sheet.dart`)
   - Bottom sheet with app grid
   - Uses AppRegistry to get app details (icon, name, color)

4. **Create ShareButton widget** (`lib/widgets/share_button.dart`)
   - IconButton that triggers share flow

5. **Extend SubApp** (`lib/core/sub_app.dart`)
   - Add acceptedShareTypes getter
   - Add onReceiveShare method

6. **Update AppRegistry** (`lib/core/app_registry.dart`)
   - Register share receivers on app registration

7. **Update list tiles** in each app:
   - notes: note_list_tile.dart
   - vocabulary: word_list_tile.dart
   - chat: chat_list_screen.dart (for messages)
   - file_system: file_tile.dart, folder_tile.dart

8. **Implement receivers** in apps that accept content:
   - vocabulary: accept text
   - notes: accept text, note, url
   - chat: accept text (as new message input)

## File Structure

```
lib/
  services/
    share_content.dart    # Model
    share_service.dart    # Service
  widgets/
    share_sheet.dart      # Bottom sheet picker
    share_button.dart     # Reusable button
  core/
    sub_app.dart          # Extended with share methods
    app_registry.dart     # Updated to register receivers
```
