import SwiftUI
import Combine

struct ImageGenSettingsView: View {
    @StateObject private var viewModel = ImageGenSettingsViewModel()

    var body: some View {
        Form {
            Section("Generation Method") {
                Toggle("Use On-Device MLX", isOn: $viewModel.useMLX)
                    .onChange(of: viewModel.useMLX) { _, newValue in
                        viewModel.saveUseMLX(newValue)
                    }

                if viewModel.useMLX {
                    Text("Generate images locally using Metal GPU. Faster and more private.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Use remote API for generation. Requires network connection.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.useMLX {
                Section("MLX Model") {
                    Picker("Model", selection: $viewModel.selectedModel) {
                        ForEach(FluxModelOption.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .onChange(of: viewModel.selectedModel) { _, newValue in
                        viewModel.saveModel(newValue)
                    }

                    Text(viewModel.selectedModel.description)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Enable Quantization", isOn: $viewModel.quantize)
                        .onChange(of: viewModel.quantize) { _, newValue in
                            viewModel.saveQuantization(newValue)
                        }

                    if viewModel.quantize {
                        Text("Reduces memory usage by ~50%. Slightly slower but enables generation on devices with less RAM.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Toggle("Use Float16", isOn: $viewModel.useFloat16)
                        .onChange(of: viewModel.useFloat16) { _, newValue in
                            viewModel.saveFloat16(newValue)
                        }

                    if viewModel.useFloat16 {
                        Text("Recommended. Uses half-precision for efficiency without quality loss.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Memory") {
                    HStack {
                        Text("Available Memory")
                        Spacer()
                        Text(String(format: "%.1f GB", viewModel.availableMemoryGB))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Model Memory")
                        Spacer()
                        Text(viewModel.estimatedMemory)
                            .foregroundColor(.secondary)
                    }

                    if viewModel.showMemoryWarning {
                        Label("Low memory. Enable quantization or use flux-schnell.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            } else {
                Section("Remote API") {
                    TextField("API URL", text: $viewModel.apiUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: viewModel.apiUrl) { _, newValue in
                            viewModel.saveAPIUrl(newValue)
                        }

                    Text("Example: http://192.168.1.100:8004")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Cache") {
                Button(role: .destructive) {
                    viewModel.clearModelCache()
                } label: {
                    Label("Clear Model Cache", systemImage: "trash")
                }

                Text("Frees up storage by removing downloaded models. They will be re-downloaded when needed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("About") {
                HStack {
                    Text("Model Framework")
                    Spacer()
                    Text("MLX + Flux")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Acceleration")
                    Spacer()
                    Text("Metal GPU")
                        .foregroundColor(.secondary)
                }

                Link(destination: URL(string: "https://github.com/mzbac/flux.swift")!) {
                    HStack {
                        Text("flux.swift on GitHub")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Image Gen Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - View Model

@MainActor
class ImageGenSettingsViewModel: ObservableObject {
    @Published var useMLX: Bool = true
    @Published var selectedModel: FluxModelOption = .fluxSchnell
    @Published var quantize: Bool = false
    @Published var useFloat16: Bool = true
    @Published var apiUrl: String = ""

    private let config = ConfigService.shared
    private let imageService = ImageGenerationService.shared

    var availableMemoryGB: Double {
        MLXChatService.shared.getAvailableMemoryGB()
    }

    var estimatedMemory: String {
        let memoryMB = selectedModel.estimatedMemoryMB
        let reducedMemory = quantize ? memoryMB / 2 : memoryMB
        return String(format: "~%.1f GB", Double(reducedMemory) / 1024.0)
    }

    var showMemoryWarning: Bool {
        let memoryMB = selectedModel.estimatedMemoryMB
        let requiredGB = Double(quantize ? memoryMB / 2 : memoryMB) / 1024.0
        return availableMemoryGB < requiredGB + 2.0  // +2GB headroom
    }

    init() {
        loadSettings()
    }

    func loadSettings() {
        useMLX = imageService.useMLX
        apiUrl = imageService.apiUrl

        if let modelName: String = config.getConfig(key: "image_generation.mlx_model"),
           let model = FluxModelOption(rawValue: modelName) {
            selectedModel = model
        }

        quantize = (config.getConfig(key: "flux.quantize") ?? "false") == "true"
        useFloat16 = (config.getConfig(key: "flux.float16") ?? "true") == "true"
    }

    func saveUseMLX(_ value: Bool) {
        config.setConfig(key: "image_generation.use_mlx", value: value ? "true" : "false")
    }

    func saveModel(_ model: FluxModelOption) {
        config.setConfig(key: "image_generation.mlx_model", value: model.rawValue)
        // Unload current model so it gets reloaded with new config
        imageService.unloadModel()
    }

    func saveQuantization(_ value: Bool) {
        config.setConfig(key: "flux.quantize", value: value ? "true" : "false")
        imageService.unloadModel()
    }

    func saveFloat16(_ value: Bool) {
        config.setConfig(key: "flux.float16", value: value ? "true" : "false")
        imageService.unloadModel()
    }

    func saveAPIUrl(_ url: String) {
        config.setConfig(key: "image_generation.api_url", value: url)
    }

    func clearModelCache() {
        imageService.unloadModel()
        // TODO: Delete cached model files from HuggingFace cache
        print("🗑️ Model cache cleared")
    }
}

// MARK: - Supporting Types

enum FluxModelOption: String, CaseIterable {
    case fluxSchnell = "flux-schnell"
    case fluxDev = "flux-dev"
    case fluxKontext = "flux-kontext"

    var displayName: String {
        switch self {
        case .fluxSchnell: return "Flux Schnell (Fast)"
        case .fluxDev: return "Flux Dev (Quality)"
        case .fluxKontext: return "Flux Kontext (Context)"
        }
    }

    var description: String {
        switch self {
        case .fluxSchnell:
            return "4 steps, ~10-15s generation. Best for quick iterations."
        case .fluxDev:
            return "20 steps, ~40-60s generation. Highest quality output."
        case .fluxKontext:
            return "20 steps, context-aware generation."
        }
    }

    var estimatedMemoryMB: Int {
        return 12000  // ~12GB for all Flux models
    }
}

#Preview {
    NavigationStack {
        ImageGenSettingsView()
    }
}
