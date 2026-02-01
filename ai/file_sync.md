# File System Sync: Design & Implementation Plan

## Current State

### What's Working
- ✅ General sync infrastructure (SyncableApp interface)
- ✅ Text-based app sync (Vocabulary, Notes)
- ✅ Global "Sync All" button in Launcher
- ✅ Device discovery via UDP broadcast
- ✅ TCP socket connections for data transfer
- ✅ JSON-based entity batching and transfer

### File System Status
The file system currently:
- **Storage**: Files stored in `data/file_system/storage/` directory
- **Database**: Raw SQLite without sync fields (`files` and `derivatives` tables)
- **No Sync Support**: Missing `updatedAt`, `deletedAt`, `deviceId`, `syncVersion` fields
- **Metadata Only**: Database tracks file paths, names, sizes, MIME types
- **Actual Files**: PDFs and other content stored as actual files on disk

### Why File Sync is Different

| Aspect | Text Apps (Vocab/Notes) | File System |
|--------|------------------------|-------------|
| **Data Size** | Small (KB) | Large (MB-GB) |
| **Transfer** | JSON batching | Binary streaming |
| **Conflict Resolution** | Last-write-wins | Content hashing needed |
| **Protocol** | Works with current | Needs extension |
| **Network** | Fast | Slow for large files |

---

## Problem Analysis

### Challenge 1: Database Schema
Current `files` table:
```sql
CREATE TABLE files (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  relative_path TEXT NOT NULL UNIQUE,
  folder_path TEXT NOT NULL,
  mime_type TEXT,
  size INTEGER,
  is_favorite INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL  -- Exists but not used for sync!
)
```

**Missing for Sync:**
- `deleted_at TEXT` - Soft delete tracking
- `device_id TEXT` - Which device last modified
- `sync_version INTEGER` - Version counter for conflicts
- `content_hash TEXT` - SHA-256 to detect actual file changes

### Challenge 2: Large File Transfer
Vocabulary words are ~1KB each, batched 100 at a time = 100KB per message.

A PDF can be 10MB+. Problems:
- Can't encode 10MB as JSON string (memory, performance)
- Network timeout if sending single huge message
- No progress indication
- Retry on failure means re-sending entire file

**Current Protocol Limitations:**
```dart
// Current SyncProtocol - sends everything in one JSON message
await protocol.sendEntities(entities);  // ❌ Won't work for 10MB PDF
```

### Challenge 3: Actual File Content
Unlike vocabulary words (all data in DB), file system has:
1. **Metadata** (in database) - name, path, size
2. **Content** (on disk) - the actual PDF/image bytes

Both need to sync, but they're separate!

**Sync must:**
- Send metadata changes (new files, renames, moves)
- Send actual file bytes (only if content changed)
- Handle files that exist on one device but not another
- Delete files that were removed remotely

### Challenge 4: Conflict Resolution
What if both devices edit the same file while offline?

**Text apps:** Simple last-write-wins (newer `syncVersion` wins)

**Files:** More complex:
- Same file, different content on each device
- Need content hash to detect "file changed"
- May need to keep both versions (conflict copies)
- Or show user a merge UI

---

## Updated Solution: CRDT + Blob Sync

**Key Change:** File system will use **CrdtDatabase** (like vocabulary/notes) instead of custom sync logic.

### Architecture Overview

```
┌─────────────────────────────────────────┐
│         Current Sync (Working)          │
├─────────────────────────────────────────┤
│ CrdtDatabase.getChangeset()             │
│   ↓                                     │
│ { 'vocabulary_words': [...],            │
│   'notes': [...] }                      │
│   ↓                                     │
│ SyncProtocol (JSON messages)            │
│   ↓                                     │
│ CrdtDatabase.merge(changeset)           │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│      New: File System Sync (Hybrid)     │
├─────────────────────────────────────────┤
│ Phase 1: CRDT Metadata Sync             │
│   CrdtDatabase.getChangeset()           │
│     ↓                                   │
│   { 'files': [...],                     │
│     'derivatives': [...] }              │
│     ↓                                   │
│   SyncProtocol (JSON)                   │
│     ↓                                   │
│   CrdtDatabase.merge(changeset)         │
│                                         │
│ Phase 2: Blob Sync (NEW)                │
│   Extract content_hash from metadata    │
│     ↓                                   │
│   SyncProtocol.requestBlobs([hash...])  │
│     ↓                                   │
│   Transfer in 64KB chunks               │
│     ↓                                   │
│   Verify hash & write to disk           │
└─────────────────────────────────────────┘
```

### Phase 1: Migrate to CRDT (Database Sync)

**Step 1.1:** Migrate `files` table to CrdtDatabase

File system currently uses raw SQLite. Need to migrate to CRDT tables:

```dart
// In FileSystemStorage.init()
await CrdtDatabase.instance.execute('''
  CREATE TABLE IF NOT EXISTS files (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    relative_path TEXT NOT NULL,
    folder_path TEXT NOT NULL,
    mime_type TEXT,
    size INTEGER,
    is_favorite INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER,
    content_hash TEXT
  )
''');

await CrdtDatabase.instance.execute('''
  CREATE TABLE IF NOT EXISTS derivatives (
    id TEXT PRIMARY KEY NOT NULL,
    file_id TEXT NOT NULL,
    type TEXT NOT NULL,
    status TEXT NOT NULL,
    error TEXT,
    artifact_path TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
  )
''');
```

**Benefits:**
- Automatic CRDT conflict resolution (same as vocabulary)
- No custom `device_id`/`sync_version` logic needed
- Works with existing sync infrastructure

**Migration Strategy:**
1. Keep existing `FileSystemStorage` interface
2. Change backend from raw SQLite to `CrdtDatabase.instance`
3. Sync automatically works (CRDT changeset includes `files` table)

---

### Phase 2: Full Content Sync (Complex, Do Later)

Sync both metadata **and** actual file bytes.

#### Approach A: Chunked Transfer over Existing Protocol

Extend `SyncProtocol` to support binary messages:

```dart
class SyncProtocol {
  // Existing: JSON entity transfer
  Future<void> sendEntities(List<Map<String, dynamic>> entities);

  // New: Binary file transfer
  Future<void> sendFile(String fileId, Stream<List<int>> content, int totalSize);
  Future<Stream<List<int>>> receiveFile(String fileId);
}
```

**Message Types:**
```dart
// 1. Metadata sync (existing)
{
  "type": "entities",
  "app_id": "file_system",
  "data": [{"id": "abc", "name": "doc.pdf", ...}]
}

// 2. File content request (new)
{
  "type": "file_request",
  "file_id": "abc"
}

// 3. File content response (new)
{
  "type": "file_chunk",
  "file_id": "abc",
  "chunk_index": 0,
  "total_chunks": 42,
  "data": "<base64 encoded 256KB chunk>"
}
```

**Flow:**
1. Sync metadata (fast, shows file list)
2. For each new/changed file, request content
3. Receive in chunks (e.g., 256KB at a time)
4. Verify with content hash
5. Save to disk

**Implementation Complexity:**
- Protocol changes (backwards incompatible?)
- Chunk size tuning (too small = slow, too large = timeout)
- Progress tracking per file
- Resume on connection drop
- Parallel transfers (multiple files at once?)

#### Approach B: Separate File Transfer Channel

Keep JSON sync for metadata, use **separate HTTP server** for files:

```dart
// DeviceSyncService starts both:
await _connectionService.startListening(7654);  // Existing: JSON sync
await _fileServer.start(7655);                   // New: HTTP file server
```

**Sync Flow:**
1. Metadata sync via existing protocol (port 7654)
2. Device discovers files it needs
3. HTTP GET `http://<device-ip>:7655/files/<file-id>` for each file
4. Standard HTTP features: range requests, resume, progress

**Benefits:**
- No protocol changes needed
- HTTP is well-understood (chunking, resume, etc.)
- Can use existing Dart packages (shelf, dio)
- Browser could download files too

**Drawbacks:**
- Two ports to manage
- HTTP overhead (headers, etc.)
- Need authentication (can't expose files to network)

---

## Content Change Detection

How to know if a file actually changed?

### Option 1: Modification Time
```dart
if (remoteFile.updatedAt.isAfter(localFile.updatedAt)) {
  // Download new version
}
```
**Problem:** Clock skew between devices, accidental touches

### Option 2: File Size
```dart
if (remoteFile.size != localFile.size) {
  // Download new version
}
```
**Problem:** File could change without size changing (e.g., edit PDF metadata)

### Option 3: Content Hash (Recommended)
```dart
final localHash = sha256.convert(await localFile.readAsBytes());
if (remoteFile.contentHash != localHash.toString()) {
  // Download new version
}
```

**Add to database:**
```sql
ALTER TABLE files ADD COLUMN content_hash TEXT;
```

**When to compute:**
- On file upload
- Before sync (to detect changes)
- After receiving file (to verify)

**Performance:**
Hashing a 10MB file takes ~50ms. Acceptable.

---

## Conflict Resolution Strategies

### Strategy 1: Last-Write-Wins (Simplest)
```dart
if (remoteFile.syncVersion > localFile.syncVersion) {
  await downloadFile(remoteFile);
  await deleteLocal(localFile);
}
```

**Pro:** Simple, consistent with vocabulary/notes sync
**Con:** User might lose work if devices edit same file

### Strategy 2: Content-Based (Smarter)
```dart
if (remoteFile.contentHash != localFile.contentHash) {
  if (remoteFile.updatedAt > localFile.updatedAt) {
    await downloadFile(remoteFile);
  } else {
    await uploadFile(localFile);  // Local is newer
  }
}
```

**Pro:** Detects actual changes, not just metadata
**Con:** Still loses work if both edited same file

### Strategy 3: Conflict Copies (Safest)
```dart
if (bothFilesChanged(remoteFile, localFile)) {
  await saveAs(remoteFile, "${name} (from ${remoteDevice})");
  // Keep local version too
  // User merges manually
}
```

**Pro:** Never loses data
**Con:** User has to merge, clutters file list

**Recommendation:** Start with Strategy 2, add Strategy 3 later if needed.

---

## Selective Sync (Nice to Have)

Not all files need sync. Let users choose:

### Option 1: Folder-Based
```dart
class FileSystemSyncable {
  Set<String> _syncedFolders = {'/Documents', '/Photos'};

  Future<List<Map>> getChangesForSync(DateTime? since) async {
    return files.where((f) =>
      _syncedFolders.any((folder) => f.folderPath.startsWith(folder))
    );
  }
}
```

### Option 2: Size-Based
```dart
// Only sync files under 10MB
return files.where((f) => f.size < 10 * 1024 * 1024);
```

### Option 3: User Settings
```dart
// In settings screen:
- [ ] Sync all files
- [x] Sync favorites only
- [ ] Sync files under 10MB
- [x] Sync folder: /Documents
```

---

## Implementation Roadmap

### Milestone 1: Database Preparation (1-2 days)
- [ ] Add sync fields to `files` table (migration script)
- [ ] Add `content_hash` field
- [ ] Implement `getFilesSince(DateTime)` query
- [ ] Add `upsertFileMetadata()` method
- [ ] Update file upload to set `device_id`, `sync_version`

### Milestone 2: Metadata-Only Sync (2-3 days)
- [ ] Create `FileSystemSyncable` class
- [ ] Implement `getChangesForSync()` (metadata only)
- [ ] Implement `applyChangesFromSync()` (metadata only)
- [ ] Update `FileSystemApp.syncable` getter
- [ ] Test: Create file on Device A, see metadata on Device B
- [ ] Add "Not downloaded" indicator in UI

### Milestone 3: Content Hash & Detection (1-2 days)
- [ ] Add SHA-256 hashing on file upload
- [ ] Store hash in database
- [ ] Compute hash before sync
- [ ] Compare hashes to detect changes

### Milestone 4: Protocol Extension (3-5 days)
- [ ] Design file transfer message format
- [ ] Extend `SyncProtocol` to support binary chunks
- [ ] Implement chunked send (256KB chunks)
- [ ] Implement chunked receive
- [ ] Add progress callbacks
- [ ] Test with 1MB, 10MB, 100MB files

### Milestone 5: Full Content Sync (3-5 days)
- [ ] After metadata sync, identify missing files
- [ ] Request file content for each missing file
- [ ] Receive chunks, write to disk
- [ ] Verify hash after download
- [ ] Update UI with download progress
- [ ] Handle connection drops (resume)

### Milestone 6: Conflict Resolution (2-3 days)
- [ ] Detect conflicting edits (both devices changed same file)
- [ ] Implement conflict copy strategy
- [ ] Show conflicts in UI
- [ ] Allow user to resolve (keep one, keep both, merge)

### Milestone 7: Selective Sync (2-3 days)
- [ ] Add settings for selective sync
- [ ] Filter by folder
- [ ] Filter by size
- [ ] Filter by favorites
- [ ] Respect filters in `getChangesForSync()`

### Milestone 8: Derivatives Sync (2-3 days)
- [ ] Decide: Sync derivatives or regenerate?
- [ ] If syncing: Add `derivatives` table sync support
- [ ] If regenerating: Trigger derivative jobs on new files
- [ ] Test: PDF with summary on Device A → Device B gets summary

**Total Estimate:** 15-25 days of development

---

## Testing Strategy

### Unit Tests
- Hash computation
- Metadata serialization/deserialization
- Conflict detection logic
- Selective sync filters

### Integration Tests
- Sync 1 file between two devices
- Sync 100 files
- Sync 1GB file (large file handling)
- Connection drop during transfer (resume)
- Simultaneous edits (conflict resolution)

### Manual Testing Scenarios
1. **New file:** Create PDF on A → appears on B
2. **Edit file:** Replace PDF on A → updates on B
3. **Delete file:** Delete on A → soft-deletes on B
4. **Conflict:** Edit same file on A and B while offline → both versions kept
5. **Large file:** Upload 50MB PDF → transfers successfully
6. **Slow network:** Simulate 1Mbps → shows progress, doesn't timeout
7. **Folder structure:** Create /Work/Projects/Doc.pdf on A → same path on B

---

## Open Questions

1. **Should derivatives sync?**
   - Pro: Faster (don't regenerate summaries)
   - Con: Larger data, may be stale if source file changed
   - **Decision:** Regenerate derivatives on target device (derivatives are cached views)

2. **How to handle file moves/renames?**
   - Track `relative_path` changes
   - Need to distinguish move vs delete+create
   - Maybe add `previous_path` field?

3. **What about permissions/access control?**
   - Currently no concept of "my files" vs "shared files"
   - Sync everything or filter by creator?
   - Future enhancement

4. **Binary format vs Base64?**
   - Binary: Smaller (no encoding overhead), faster
   - Base64: Easier to debug, works in JSON
   - **Decision:** Use binary chunks for Phase 2, Base64 for quick prototype

5. **Sync on WiFi only?**
   - Large files over mobile data = expensive
   - Add setting: "Sync on WiFi only"
   - Auto-pause sync when switching to cellular

---

## Success Criteria

### Phase 1 (Metadata)
- ✅ File list syncs across devices
- ✅ Favorites, folder structure preserved
- ✅ Deleted files don't reappear
- ✅ No crashes or data loss

### Phase 2 (Content)
- ✅ Can sync a 1MB PDF successfully
- ✅ Can sync a 50MB PDF successfully
- ✅ Progress bar shows during transfer
- ✅ Resume works after connection drop
- ✅ Conflicts don't lose data
- ✅ Sync completes within 2x the theoretical minimum time (file size / network speed)

---

## Alternative: Cloud Sync

Instead of P2P sync, use a central server:

**Pros:**
- Always available (not just when both devices on network)
- Can sync 3+ devices easily
- Professional infrastructure (S3, etc.)

**Cons:**
- Costs money (storage, bandwidth)
- Privacy concerns (files on third-party server)
- Requires internet (P2P works on local network)

**Recommendation:** P2P is more aligned with the "playground" philosophy (self-contained, privacy-first). Cloud sync could be added later as an optional feature.

---

## References

- Current sync implementation: `lib/core/sync/`
- File storage: `lib/apps/file_system/services/file_system_storage.dart`
- Sync protocol: `lib/core/sync/services/sync_protocol.dart`
- Planning doc: `ai/general_sync.md`
