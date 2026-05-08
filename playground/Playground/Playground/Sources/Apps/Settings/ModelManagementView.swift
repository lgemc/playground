import SwiftUI
import Combine

@MainActor
class ModelManagementViewModel: ObservableObject {
    @Published var models: [RegisteredModel] = []
    @Published var isLoading = true
    @Published var totalSizeMB: Int = 0
    @Published var modelToDelete: RegisteredModel?
    @Published var showingDeleteConfirmation = false
    @Published var errorMessage: String?

    func loadModels() async {
        isLoading = true
        do {
            let allModels = try await ModelRegistry.shared.getAllModels()
            models = allModels
            totalSizeMB = try await ModelRegistry.shared.getTotalSizeMB()
        } catch {
            print("Error loading models: \(error)")
            errorMessage = "Failed to load models: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func deleteModel(_ model: RegisteredModel) async {
        do {
            try await ModelRegistry.shared.deleteModel(modelId: model.modelId)
            await loadModels() // Refresh the list
        } catch {
            print("Error deleting model: \(error)")
            errorMessage = "Failed to delete model: \(error.localizedDescription)"
        }
    }

    func confirmDelete(model: RegisteredModel) {
        modelToDelete = model
        showingDeleteConfirmation = true
    }
}

struct ModelManagementView: View {
    @StateObject private var viewModel = ModelManagementViewModel()

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView("Loading models...")
            } else {
                List {
                    // Summary Section
                    Section {
                        HStack {
                            Image(systemName: "internaldrive")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Total Storage Used")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(formatSize(viewModel.totalSizeMB))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Downloaded")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("\(viewModel.models.filter { $0.isDownloaded }.count)")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // Models grouped by type
                    ForEach(RegisteredModel.ModelType.allCases, id: \.self) { type in
                        let modelsOfType = viewModel.models.filter { $0.type == type }
                        if !modelsOfType.isEmpty {
                            Section(header: Text(type.displayName)) {
                                ForEach(modelsOfType) { model in
                                    ModelRowView(
                                        model: model,
                                        onDelete: {
                                            viewModel.confirmDelete(model: model)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Model Management")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadModels()
        }
        .refreshable {
            await viewModel.loadModels()
        }
        .alert("Delete Model", isPresented: $viewModel.showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.modelToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let model = viewModel.modelToDelete {
                    Task {
                        await viewModel.deleteModel(model)
                        viewModel.modelToDelete = nil
                    }
                }
            }
        } message: {
            if let model = viewModel.modelToDelete {
                Text("Are you sure you want to delete '\(model.name)'? This will free up \(formatSize(model.sizeMB ?? 0)) of storage.")
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
    }

    private func formatSize(_ sizeMB: Int) -> String {
        if sizeMB >= 1024 {
            let gb = Double(sizeMB) / 1024.0
            return String(format: "%.1f GB", gb)
        } else {
            return "\(sizeMB) MB"
        }
    }
}

struct ModelRowView: View {
    let model: RegisteredModel
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Model icon
            Image(systemName: model.type.iconName)
                .font(.title2)
                .foregroundColor(model.type.color)
                .frame(width: 40, height: 40)
                .background(model.type.color.opacity(0.1))
                .cornerRadius(8)

            // Model info
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    if model.isDownloaded {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("Not Downloaded", systemImage: "arrow.down.circle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    if let sizeMB = model.sizeMB {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatSize(sizeMB))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Delete button (only for downloaded models)
            if model.isDownloaded {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.body)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatSize(_ sizeMB: Int) -> String {
        if sizeMB >= 1024 {
            let gb = Double(sizeMB) / 1024.0
            return String(format: "%.1f GB", gb)
        } else {
            return "\(sizeMB) MB"
        }
    }
}

// MARK: - Model Type Extensions

extension RegisteredModel.ModelType: CaseIterable {
    static var allCases: [RegisteredModel.ModelType] {
        [.chat, .whisper, .tts, .image, .flux]
    }

    var displayName: String {
        switch self {
        case .chat: return "Chat Models"
        case .whisper: return "Speech Recognition"
        case .tts: return "Text-to-Speech"
        case .image: return "Image Generation"
        case .flux: return "FLUX Models"
        }
    }

    var iconName: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .whisper: return "waveform"
        case .tts: return "speaker.wave.3.fill"
        case .image: return "photo.fill"
        case .flux: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .chat: return .blue
        case .whisper: return .purple
        case .tts: return .orange
        case .image: return .pink
        case .flux: return .indigo
        }
    }
}

// Preview
struct ModelManagementView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ModelManagementView()
        }
    }
}
