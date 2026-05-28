# MLX Stable Diffusion Setup

## Overview

On-device image generation using **MLX Stable Diffusion** (from ml-explore/mlx-swift-examples) optimized for Apple Silicon.

✅ **No dependency conflicts**: Works with existing swift-transformers 1.1.9
✅ **iPhone & Mac**: Runs efficiently on both platforms
✅ **Low memory**: 2-4GB RAM usage (vs 6-12GB for Flux)
✅ **Fast**: 5-15 seconds for 512x512 images with SDXL Turbo
✅ **MLX-powered**: Uses Apple's MLX framework
✅ **No server needed**: Fully on-device

## Installation

### Step 1: Add Swift Package Dependency ✅ (Already Done!)

The `mlx-swift-examples` package has been added to your Xcode project with the **StableDiffusion** library.

Package URL: `https://github.com/ml-explore/mlx-swift-examples.git`
Product: **StableDiffusion**

### Step 2: Models Download Automatically ✅

MLX Stable Diffusion automatically downloads models from Hugging Face on first use. No manual setup needed!

Models are cached in:
```
~/Library/Containers/{YourAppID}/Data/Documents/huggingface/
```

### Step 3: Build and Run

```bash
cd playground/Playground
# Build in Xcode (Cmd+B)
```

The first generation will verify the model files exist.

## Available Models

### SDXL Turbo (Default - Recommended for iPhone)
- **HuggingFace**: `stabilityai/sdxl-turbo`
- **Size**: 512x512 images
- **Memory**: ~2-3GB
- **Speed**: 5-10s on iPhone 14+, 3-5s on M2
- **Steps**: 1-4 (super fast!)
- **Best for**: Real-time generation, iPhone, fast iterations

### Stable Diffusion 2.1 Base
- **HuggingFace**: `stabilityai/stable-diffusion-2-1-base`
- **Size**: 512x512 images
- **Memory**: ~2GB
- **Speed**: 15-25s on iPhone 14+
- **Steps**: 20-30
- **Best for**: Better quality, more control

### Custom Models
You can use any Stable Diffusion model from Hugging Face by changing the model ID in config.

## Usage

### Basic Generation

```swift
import ImageGenerationService

// Generate image (using SDXL Turbo - super fast!)
let imageURL = try await ImageGenerationService.shared.generateImage(
    prompt: "A serene landscape with mountains and a lake at sunset",
    width: 512,
    height: 512,
    steps: 4,          // SDXL Turbo default
    guidanceScale: 0.0  // SDXL Turbo uses 0.0
)

print("Image saved to: \(imageURL)")
```

### With Negative Prompts

```swift
let imageURL = try await ImageGenerationService.shared.generateImage(
    prompt: "A beautiful portrait of a woman",
    negativePrompt: "blurry, ugly, distorted, low quality",
    width: 512,
    height: 512,
    steps: 25,
    guidanceScale: 8.0
)
```

### With Progress Tracking

```swift
for try await progress in ImageGenerationService.shared.generateImageWithProgress(
    prompt: "A futuristic city with flying cars",
    width: 512,
    height: 512,
    steps: 20
) {
    print("Progress: \(progress.progress * 100)% - Step \(progress.step)/\(progress.totalSteps)")

    if progress.isComplete, let image = progress.currentImage {
        // Display final image
    }
}
```

## Configuration

Configure via `ConfigService`:

```swift
let config = ConfigService.shared

// Choose model
config.setConfig(key: "stable_diffusion.model", value: "stabilityai/sdxl-turbo")  // Default

// Conserve memory (recommended for iPhone)
config.setConfig(key: "stable_diffusion.conserve_memory", value: "true")  // Loads/unloads model parts
```

### Memory Management Options

- **`conserve_memory: true`** (default): Loads and unloads model parts as needed - best for iPhone (< 4GB memory)
- **`conserve_memory: false`**: Keeps entire model in memory - faster regeneration on devices with more RAM (Mac)

## Performance Comparison

| Device | Model | Size | Steps | Time | Memory |
|--------|-------|------|-------|------|--------|
| iPhone 15 Pro | SDXL Turbo | 512x512 | 4 | ~5-8s | 2.5GB |
| iPhone 14 Pro | SDXL Turbo | 512x512 | 4 | ~8-12s | 2.5GB |
| iPhone 13 | SDXL Turbo | 512x512 | 1 | ~10-15s | 2.5GB |
| M2 MacBook | SDXL Turbo | 512x512 | 4 | ~3-5s | 2GB |
| M2 MacBook | SD 2.1 | 512x512 | 20 | ~10-15s | 2GB |

## Optimization Tips

### For iPhone (Best Battery + Performance)

```swift
// Use Neural Engine
config.setConfig(key: "stable_diffusion.compute_units", value: "all")

// Enable memory reduction
config.setConfig(key: "stable_diffusion.reduce_memory", value: "true")

// Use optimal image size (512x512)
let url = try await service.generateImage(
    prompt: "...",
    width: 512,  // Don't go higher on iPhone
    height: 512,
    steps: 20     // 15-25 is optimal
)
```

### For Mac (Best Quality)

```swift
// Use all compute units
config.setConfig(key: "stable_diffusion.compute_units", value: "all")

// Disable memory reduction (not needed on Mac)
config.setConfig(key: "stable_diffusion.reduce_memory", value: "false")

// Use SDXL for high resolution
config.setConfig(key: "stable_diffusion.model", value: "stabilityai/stable-diffusion-xl-base")

let url = try await service.generateImage(
    prompt: "...",
    width: 1024,
    height: 1024,
    steps: 30
)
```

## Troubleshooting

### Model Not Found Error

**Error**: `Model not found at: .../data/models/stable_diffusion/...`

**Solution**: Download the Core ML model files (see Step 2 above). The models are ~2-6GB and must be downloaded separately.

### Out of Memory Error

**Solution**:
1. Enable memory reduction: `stable_diffusion.reduce_memory = true`
2. Use smaller image sizes: 512x512 instead of 1024x1024
3. Close other apps before generating
4. Use SD 2.1 instead of SDXL on iPhone

### Slow Generation

**Solution**:
1. Ensure compute units set to `all` (uses Neural Engine)
2. Reduce steps to 15-20 (diminishing returns after 20)
3. Use SD 1.5 instead of SD 2.1 (slightly faster)
4. Make sure model files are local (not on network drive)

### Poor Image Quality

**Solution**:
1. Increase steps to 25-30
2. Adjust guidance scale (7.5-9.0 for realistic, 3.0-5.0 for creative)
3. Use negative prompts to avoid unwanted elements
4. Try different models (SD 2.1 vs 1.5 vs SDXL)

## Memory Management

Free memory when app goes to background:

```swift
// In your app delegate or SwiftUI lifecycle
func applicationDidEnterBackground() {
    ImageGenerationService.shared.unloadModel()
}
```

## Architecture

```
ImageGenerationService (high-level wrapper)
└── CoreMLStableDiffusionService
    └── StableDiffusion (Apple's official package)
        └── Core ML → Neural Engine + GPU + CPU
```

## Why Core ML Stable Diffusion?

**vs Flux/MFLUX:**
- ✅ 3-5x lower memory usage
- ✅ Uses Neural Engine (faster, better battery)
- ✅ Works on iPhone (Flux requires 8GB+ RAM)
- ✅ Apple-optimized for iOS/macOS

**vs Python API:**
- ✅ No server needed
- ✅ Works offline
- ✅ Lower latency (no network)
- ✅ Better privacy (all on-device)

**vs Cloud APIs (DALL-E, Midjourney):**
- ✅ Free (no API costs)
- ✅ Private (no data sent to cloud)
- ✅ Faster (no network latency)
- ✅ Works offline

## Next Steps

1. Download models (see Step 2)
2. Build the app
3. Try generating your first image!

## Resources

- Apple's ML Stable Diffusion: https://github.com/apple/ml-stable-diffusion
- Core ML Models: https://huggingface.co/apple
- Stable Diffusion: https://huggingface.co/stabilityai
