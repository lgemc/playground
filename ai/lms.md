# LMS (Learning Management System) - Implementation Plan

## Overview

A sub-app for managing courses, lesson modules, and educational content. Integrates with the existing file system app for resource management.

---

## Data Models

### 1. Course
```dart
class Course {
  final String id;
  final String name;
  final String? description;
  final String? thumbnailFileId;  // Reference to file system
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<LessonModule> modules;
}
```

### 2. LessonModule
```dart
class LessonModule {
  final String id;
  final String courseId;
  final String name;
  final String? description;
  final int order;  // For sorting within course
  final DateTime createdAt;
  final List<LessonSubSection> subSections;
}
```

### 3. LessonSubSection
```dart
class LessonSubSection {
  final String id;
  final String moduleId;
  final String name;  // Required
  final String? description;  // Optional
  final int order;  // For sorting within module
  final DateTime createdAt;
  final List<Activity> activities;
}
```

### 4. Activity (Base)
```dart
abstract class Activity {
  final String id;
  final String subSectionId;
  final String name;  // Required
  final String? description;  // Optional
  final DateTime createdAt;
  final int order;  // For sorting within sub-section
  final ActivityType type;
}

enum ActivityType {
  resourceFile,
  quiz,  // Future implementation
}
```

### 5. ResourceFileActivity
```dart
class ResourceFileActivity extends Activity {
  final String fileId;  // Reference to file system (NOT path or name)
  final ResourceType resourceType;  // lecture, audio, video, document
}

enum ResourceType {
  lecture,
  audio,
  video,
  document,
  other,
}
```

---

## Folder Structure

```
lib/apps/lms/
├── lms_app.dart                    # SubApp implementation
├── models/
│   ├── course.dart
│   ├── lesson_module.dart
│   ├── lesson_sub_section.dart
│   ├── activity.dart
│   └── resource_file_activity.dart
├── services/
│   ├── lms_storage_service.dart    # JSON persistence
│   └── file_system_bridge.dart     # Integration with file system app
├── screens/
│   ├── courses_list_screen.dart    # Main screen - list of courses
│   ├── course_detail_screen.dart   # Shows modules in a course
│   ├── module_detail_screen.dart   # Shows sub-sections in a module
│   ├── sub_section_screen.dart     # Shows activities in a sub-section
│   ├── activity_viewer_screen.dart # View/play resource content
│   └── forms/
│       ├── course_form_screen.dart
│       ├── module_form_screen.dart
│       ├── sub_section_form_screen.dart
│       └── activity_form_screen.dart
└── widgets/
    ├── course_card.dart
    ├── module_list_tile.dart
    ├── sub_section_list_tile.dart
    ├── activity_list_tile.dart
    └── file_picker_dialog.dart     # Select file from file system
```

---

## Data Storage

Location: `data/lms/`

```
data/lms/
├── courses.json          # All courses with nested structure
└── settings.json         # App preferences
```

### JSON Structure Example
```json
{
  "courses": [
    {
      "id": "uuid",
      "name": "Flutter Development",
      "description": "Learn Flutter from scratch",
      "thumbnailFileId": "file-uuid",
      "createdAt": "2024-01-15T10:00:00Z",
      "updatedAt": "2024-01-15T10:00:00Z",
      "modules": [
        {
          "id": "uuid",
          "name": "Introduction",
          "order": 0,
          "subSections": [
            {
              "id": "uuid",
              "name": "Getting Started",
              "description": "Setup your environment",
              "order": 0,
              "activities": [
                {
                  "id": "uuid",
                  "type": "resourceFile",
                  "name": "Installation Guide",
                  "description": "Step by step setup",
                  "fileId": "file-system-uuid",
                  "resourceType": "document",
                  "createdAt": "2024-01-15T10:00:00Z",
                  "order": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

---

## Implementation Steps

### Phase 1: Core Setup
- [ ] Create `LmsApp` class extending `SubApp`
- [ ] Register in `main.dart`
- [ ] Create data models with JSON serialization
- [ ] Implement `LmsStorageService` for persistence

### Phase 2: Course Management
- [ ] `CoursesListScreen` - display all courses as cards/grid
- [ ] `CourseFormScreen` - create/edit course
- [ ] Swipe to delete course (with confirmation)

### Phase 3: Module Management
- [ ] `CourseDetailScreen` - list modules in a course
- [ ] `ModuleFormScreen` - create/edit module
- [ ] Drag-to-reorder modules
- [ ] Swipe to delete module

### Phase 4: Sub-Section Management
- [ ] `ModuleDetailScreen` - list sub-sections
- [ ] `SubSectionFormScreen` - create/edit sub-section
- [ ] Drag-to-reorder sub-sections
- [ ] Swipe to delete sub-section

### Phase 5: Activity Management
- [ ] `SubSectionScreen` - list activities
- [ ] `ActivityFormScreen` - create/edit activity
- [ ] `FilePickerDialog` - select file from file system app
- [ ] `ActivityViewerScreen` - display/play resource content
- [ ] Drag-to-reorder activities
- [ ] Swipe to delete activity

### Phase 6: File System Integration
- [ ] Create `FileSystemBridge` service
- [ ] Query files by ID from file system storage
- [ ] Display file preview/thumbnail in activity cards
- [ ] Open files with appropriate viewer based on type

---

## UI/UX Design

### Navigation Flow
```
Courses List → Course Detail → Module Detail → Sub-Section → Activity Viewer
     ↓              ↓              ↓               ↓
   [+ Add]       [+ Module]    [+ Section]    [+ Activity]
```

### Interaction Patterns (per CLAUDE.md guidelines)
- **Swipe left**: Delete with red background + confirmation
- **Swipe right**: Edit with blue background
- **Long press**: Drag to reorder
- **Tap**: Navigate into / view content

### Course Card Design
```
┌─────────────────────────────┐
│  [Thumbnail]                │
│  Course Name                │
│  Description...             │
│  📚 X modules               │
└─────────────────────────────┘
```

### Activity List Tile Design
```
┌─────────────────────────────────────┐
│ [Icon]  Activity Name               │
│         Description (if any)        │
│         📎 filename.pdf             │
└─────────────────────────────────────┘
```

---

## File System Integration Details

The LMS must reference files by ID, not by path or name. This requires:

1. **Reading from file system storage**: Access `data/files/files.json` to resolve file IDs
2. **File picker**: Show available files from file system, return selected file ID
3. **File resolution**: Given a file ID, get the actual file path for viewing

```dart
class FileSystemBridge {
  Future<List<FileEntry>> getAvailableFiles();
  Future<FileEntry?> getFileById(String fileId);
  Future<String?> getFilePathById(String fileId);
}
```

---

## Future Considerations (Quiz - Not in Scope)

When implementing quizzes later:
- `QuizActivity` extending `Activity`
- Question types: multiple choice, true/false, short answer
- Score tracking and progress
- Separate storage for quiz attempts/results

---

## Dependencies

- `uuid` - Generate unique IDs
- Existing file system app for resource management
- No additional packages required

---

## Testing Plan

1. Unit tests for models (serialization/deserialization)
2. Unit tests for storage service
3. Widget tests for form validation
4. Integration test for full course creation flow
