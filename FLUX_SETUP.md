# Image Generation Setup (DEPRECATED)

## ⚠️ This document is deprecated

We've switched from Flux to **Core ML Stable Diffusion** for better iPhone compatibility.

**See: [STABLE_DIFFUSION_SETUP.md](STABLE_DIFFUSION_SETUP.md)** for the new implementation.

---

## Why We Switched

**Flux Issues:**
- ❌ Dependency conflict: flux.swift requires swift-transformers < 0.2.0
- ❌ mlx-audio-swift requires swift-transformers >= 1.1.6
- ❌ Cannot use both in the same project
- ❌ High memory usage (6-12GB) - too much for iPhone

**Core ML Stable Diffusion Benefits:**
- ✅ No dependency conflicts
- ✅ iPhone-optimized (2-4GB memory)
- ✅ Uses Neural Engine (faster + better battery)
- ✅ Works on iPhone 12+
- ✅ Apple's official implementation

---

# Original Flux Setup (For Reference Only)

## Overview

~~I've set up **on-device Flux image generation** using MLX Swift, following the same pattern as your audio generation service. This runs entirely on-device with Metal GPU acceleration - **no Python API server needed**.~~

**UPDATE**: This approach was abandoned due to dependency conflicts with mlx-audio-swift.

## What I Created

### 1. MLX Services
- **MLXFluxService.swift** - Core MLX Flux service (like MLXAudioTTSService)
- **ImageGenerationService.swift** - High-level wrapper with MLX primary + API fallback (like AudioGenerationService)
- **Updated MLXModelConfig.swift** - Added FluxModel enum with configuration

### 2. Key Features
- ✅ On-device generation using MLX + Metal GPU
- ✅ Three Flux models: flux-schnell (fast), flux-dev (quality), flux-kontext (context-aware)
- ✅ Automatic model selection based on available memory
- ✅ Quantization support (4-bit/8-bit) for efficient memory use
- ✅ Progress tracking with streaming generation
- ✅ Automatic file management (saved to `data/file_system/storage/generated/images/`)
- ✅ Optional remote API fallback

## Installation Steps

### Step 1: Add flux.swift Package to Xcode

1. Open `Playground.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies**
3. Enter URL: `https://github.com/mzbac/flux.swift.git`
4. Version: **0.1.7** or later
5. Click **Add Package**
6. Select **FluxSwift** product
7. Click **Add Package**

### Step 2: Build the Project

```bash
cd playground/Playground
# Open in Xcode and build (Cmd+B)
```

The first build will download the flux.swift package and its dependencies.

## Usage Examples

### Basic Image Generation

```swift
import ImageGenerationService

// Generate an image
let imageURL = try await ImageGenerationService.shared.generateImage(
    prompt: "A serene landscape with mountains and a lake at sunset",
    width: 1024,
    height: 1024
)

print("Image saved to: \(imageURL)")
```

### With Progress Tracking

```swift
for try await progress in ImageGenerationService.shared.generateImageWithProgress(
    prompt: "A futuristic city with flying cars",
    width: 1024,
    height: 1024
) {
    print("Progress: \(progress.progress * 100)% - Step \(progress.step)/\(progress.totalSteps)")

    if progress.isComplete, let base64 = progress.previewImage {
        // Display final image
    }
}
```

### Configuration

```swift
let config = ConfigService.shared

// Use on-device MLX (default)
config.setConfig(key: "image_generation.use_mlx", value: "true")
config.setConfig(key: "image_generation.mlx_model", value: "flux-schnell")

// Enable quantization for lower memory usage
MLXFluxService.shared.config.setConfig(key: "flux.quantize", value: "true")
MLXFluxService.shared.config.setConfig(key: "flux.float16", value: "true")

// Optional: Configure remote API fallback
config.setConfig(key: "image_generation.api_url", value: "http://your-api:8004")
```

## Model Information

| Model | Steps | Time (iPhone) | Memory | Quality |
|-------|-------|---------------|--------|---------|
| flux-schnell | 4 | ~10-15s | 6-12GB* | Good |
| flux-dev | 20 | ~40-60s | 6-12GB* | Excellent |
| flux-kontext | 20 | ~40-60s | 6-12GB* | Excellent |

*With quantization enabled, memory usage can be reduced by ~50%

## Architecture

```
ImageGenerationService (high-level wrapper)
├── MLXFluxService (on-device, primary)
│   └── flux.swift package
│       └── MLX framework → Metal GPU
└── Remote API (optional fallback)
    └── Your Python API (if needed)
```

## Configuration Keys

| Key | Default | Description |
|-----|---------|-------------|
| `image_generation.use_mlx` | `true` | Use on-device MLX generation |
| `image_generation.mlx_model` | `flux-schnell` | Model: flux-schnell, flux-dev, flux-kontext |
| `image_generation.api_url` | `""` | Optional remote API endpoint |
| `flux.quantize` | `false` | Enable 4/8-bit quantization |
| `flux.float16` | `true` | Use float16 for efficiency |

## Memory Management

The service automatically manages memory:
- Models are lazy-loaded on first use
- Call `unloadModel()` to free memory when done
- Automatic cache clearing between generations

```swift
// Free memory when switching apps or backgrounding
ImageGenerationService.shared.unloadModel()
```

## Next Steps

### Create Image Generation App (ImageGenApp)

Now you can create the SwiftUI app interface. I'll do that next following the pattern of your other apps (ChatApp, VocabularyApp, etc.).

The app will allow users to:
- Enter text prompts
- Generate images with progress tracking
- View generation history
- Save/share generated images
- Configure model settings

### Model Download

On first use, flux.swift will automatically download models from HuggingFace:
- **flux-schnell**: ~12GB download (one-time)
- **flux-dev**: ~12GB download (one-time)

Models are cached in the app's data directory for offline use.

## Troubleshooting

### Build Errors
- Make sure to add the flux.swift package dependency
- Clean build folder: Shift+Cmd+K
- Restart Xcode if package resolution fails

### Memory Issues
- Enable quantization: `flux.quantize = true`
- Use flux-schnell (fastest, smallest)
- Close other apps before generating
- iPhone Pro models (8GB+ RAM) recommended

### Slow Generation
- First generation loads the model (~30s one-time cost)
- Subsequent generations are faster (~10-15s for flux-schnell)
- M5 GPUs are 3.8x faster than M4

## Python API (Optional)

If you want a remote API fallback, I created Python API files in `ai-server/flux-api/`:
- `app.py` - FastAPI service with MFLUX
- `Dockerfile` - Container setup
- `requirements.txt` - Dependencies

But **you don't need this** - the on-device MLX approach is the primary solution, matching your architecture for audio/text generation.

## Why This Approach?

1. **Consistent with your architecture**: Same pattern as AudioGenerationService (MLX primary + API fallback)
2. **On-device execution**: No server needed, works offline, faster
3. **Privacy**: All generation happens locally
4. **Cost-effective**: No API fees
5. **Better UX**: No network latency, progress tracking

## References

- flux.swift: https://github.com/mzbac/flux.swift
- MLX framework: https://github.com/ml-explore/mlx-swift
- Flux models: https://huggingface.co/black-forest-labs
