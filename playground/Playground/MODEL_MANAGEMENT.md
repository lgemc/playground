# Model Management Feature

This document explains the model management system that tracks, displays, and allows deletion of downloaded MLX models.

## Architecture

### Components

1. **ModelRegistry** (`Sources/Services/MLX/ModelRegistry.swift`)
   - Actor-based service for thread-safe model tracking
   - Stores model metadata in SQLite database (`model_registry.db`)
   - Provides CRUD operations for model records

2. **ModelRegistryInitializer** (`Sources/Services/MLX/ModelRegistryInitializer.swift`)
   - Initializes the registry with all available MLX models on app startup
   - Pre-populates database with model metadata (name, type, estimated size)

3. **Settings App** (`Sources/Apps/Settings/`)
   - New SubApp for app configuration
   - Contains Model Management subsection
   - Follows the same architecture as other SubApps (Chat, Files, etc.)

4. **ModelManagementView** (`Sources/Apps/Settings/ModelManagementView.swift`)
   - SwiftUI interface for viewing and managing models
   - Shows downloaded models grouped by type
   - Displays storage usage and model sizes
   - Allows deletion of downloaded models

## Database Schema

```sql
CREATE TABLE mlx_models (
    id TEXT PRIMARY KEY,                -- Unique ID
    model_id TEXT NOT NULL,             -- HuggingFace repo ID (e.g., "mlx-community/Qwen3-4B-4bit")
    type TEXT NOT NULL,                 -- "chat", "whisper", "tts", "image", "flux"
    name TEXT NOT NULL,                 -- Display name (e.g., "Qwen 3 4B (4-bit)")
    size_mb INTEGER,                    -- Estimated size in MB
    is_downloaded INTEGER DEFAULT 0,    -- 0 = not downloaded, 1 = downloaded
    download_progress REAL,             -- 0.0 to 1.0 (for future use)
    download_started_at TEXT,           -- ISO8601 timestamp (for future use)
    download_completed_at TEXT,         -- ISO8601 timestamp
    last_used_at TEXT,                  -- ISO8601 timestamp
    created_at TEXT NOT NULL,           -- ISO8601 timestamp
    updated_at TEXT NOT NULL            -- ISO8601 timestamp
)
```

## Usage

### Accessing Model Management

1. Launch the Playground app
2. Tap the "Settings" app from the launcher
3. Select "Model Management" from the settings menu

### Features

**View All Models**
- Models are grouped by type: Chat, Speech Recognition, TTS, Image Generation, FLUX
- Each model shows:
  - Display name
  - Download status (downloaded/not downloaded)
  - Size in MB or GB
  - Delete button (for downloaded models only)

**Storage Summary**
- Total storage used by all downloaded models
- Count of downloaded models

**Delete Models**
- Tap the trash icon next to a downloaded model
- Confirm deletion in the alert dialog
- Model files are removed from cache and database record is deleted

### Tracking Model Downloads

To mark a model as downloaded when it's loaded for the first time, add this to your service:

```swift
// Example: In MLXChatService when loading a model
let modelId = "mlx-community/Qwen3-4B-4bit"
try await ModelRegistry.shared.markAsDownloaded(
    modelId: modelId,
    sizeMB: 2800  // Actual size from file system
)
```

### Tracking Model Usage

To update the "last used" timestamp:

```swift
try await ModelRegistry.shared.updateLastUsed(modelId: modelId)
```

## Model Types

The registry supports five model types:

| Type    | Display Name          | Icon                | Color  | Examples                                |
|---------|-----------------------|---------------------|--------|-----------------------------------------|
| chat    | Chat Models           | bubble.left.and...  | Blue   | LFM 2.5, Qwen 3.5, Llama 3.2            |
| whisper | Speech Recognition    | waveform            | Purple | Whisper Tiny, Base, Small               |
| tts     | Text-to-Speech        | speaker.wave.3.fill | Orange | Kokoro, Qwen 3 TTS, CosyVoice           |
| image   | Image Generation      | photo.fill          | Pink   | Stable Diffusion 1.5, 2.1, SDXL Turbo   |
| flux    | FLUX Models           | sparkles            | Indigo | FLUX.1 Schnell, Dev, Kontext            |

## Pre-registered Models

All available MLX models are pre-registered on app startup with estimated sizes:

### Chat Models
- LFM 2.5 1.2B (4-bit) - 800 MB
- Qwen 3.5 2B (6-bit) - 1.6 GB
- Llama 3.2 3B Instruct (4-bit) - 1.85 GB
- Qwen 3 4B (4-bit) - 2.8 GB

### Whisper Models
- Whisper Tiny - 150 MB
- Whisper Base - 290 MB
- Whisper Small - 970 MB
- Distil Whisper Large v3 - 1.56 GB

### TTS Models
- Kokoro 82M - 350 MB
- Qwen 3 TTS - 800 MB
- CosyVoice 300M SFT - 600 MB

### Image Models
- Stable Diffusion 1.5 (4-bit) - 1.7 GB
- Stable Diffusion 2.1 (4-bit) - 2.2 GB
- SDXL Turbo (4-bit) - 3.2 GB

### FLUX Models
- FLUX.1 Schnell (4-bit) - 11 GB
- FLUX.1 Dev (4-bit) - 11 GB
- FLUX.1 Kontext (4-bit) - 11 GB

## Model File Deletion

When deleting a model, the system attempts to remove files from common HuggingFace cache locations:

- `~/Library/Caches/huggingface/hub/`
- `~/Library/Application Support/.cache/huggingface/hub/`

Model directories are identified by converting the model ID:
```
mlx-community/Qwen3-4B-4bit → models--mlx-community--Qwen3-4B-4bit
```

**Note:** MLX Swift manages its own model cache, so file deletion is best-effort. The database record is always removed, but some cached files may persist if stored in framework-managed directories.

## Future Enhancements

- Download progress tracking during model downloads
- Manual model download from the UI
- Automatic cleanup of old/unused models
- Model download queue management
- Cache size limits and automatic cleanup
- Model performance metrics (inference speed, memory usage)
