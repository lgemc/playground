import Foundation
import MLX

/// Manages native on-device MLX models with lazy loading
/// No server required - models are loaded directly from HuggingFace
actor MLXModelPool {
    static let shared = MLXModelPool()

    private var metadata: [String: MLXModelMetadata] = [:]

    private init() {}

    // MARK: - Model Management

    /// Track a model as loaded
    func markAsLoaded(modelId: String, type: MLXModelMetadata.ModelType, estimatedMemoryMB: Int) {
        var meta = metadata[modelId] ?? MLXModelMetadata(
            modelId: modelId,
            type: type,
            estimatedMemoryMB: estimatedMemoryMB
        )
        meta.state = .loaded
        meta.loadedAt = Date()
        metadata[modelId] = meta
    }

    /// Track a model as loading
    func markAsLoading(modelId: String, type: MLXModelMetadata.ModelType, estimatedMemoryMB: Int) {
        var meta = metadata[modelId] ?? MLXModelMetadata(
            modelId: modelId,
            type: type,
            estimatedMemoryMB: estimatedMemoryMB
        )
        meta.state = .loading
        metadata[modelId] = meta
    }

    /// Track a model as failed
    func markAsFailed(modelId: String, error: Error) {
        if var meta = metadata[modelId] {
            meta.state = .failed(error)
            metadata[modelId] = meta
        }
    }

    /// Mark a model as unloaded
    func markAsUnloaded(modelId: String) {
        if var meta = metadata[modelId] {
            meta.state = .notLoaded
            meta.loadedAt = nil
            metadata[modelId] = meta
        }
    }

    /// Get current model state
    func getModelState(modelId: String) -> MLXModelState {
        return metadata[modelId]?.state ?? .notLoaded
    }

    /// List all loaded models
    func getLoadedModels() -> [MLXModelMetadata] {
        return metadata.values.filter { model in
            if case .loaded = model.state {
                return true
            }
            return false
        }
    }

    /// Get total estimated memory usage
    func getTotalMemoryUsageMB() -> Int {
        return getLoadedModels().reduce(0) { $0 + $1.estimatedMemoryMB }
    }

    /// Clear all tracking metadata
    func clearAll() {
        metadata.removeAll()
        MLX.Memory.clearCache()
    }
}
