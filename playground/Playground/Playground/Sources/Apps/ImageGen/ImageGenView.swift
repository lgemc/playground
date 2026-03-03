import SwiftUI

struct ImageGenView: View {
    @StateObject private var viewModel = ImageGenViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Generated image display
                generatedImageSection

                Divider()

                // Prompt input and controls
                controlsSection
            }
            .navigationTitle("Image Generation")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ImageGenHistoryView()) {
                        Image(systemName: "photo.stack")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ImageGenSettingsView()) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
    }

    // MARK: - Generated Image Section

    @ViewBuilder
    private var generatedImageSection: some View {
        ZStack {
            if let image = viewModel.generatedImage {
                // Display generated image
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contextMenu {
                        Button {
                            viewModel.saveToPhotos()
                        } label: {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            viewModel.shareImage()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
            } else if viewModel.isGenerating {
                // Show progress
                VStack(spacing: 20) {
                    ProgressView(value: viewModel.progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(width: 200)

                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Step \(viewModel.currentStep) of \(viewModel.totalSteps)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Generating image...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                // Placeholder
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)

                    Text("No image generated yet")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Enter a prompt below and tap Generate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
    }

    // MARK: - Controls Section

    @ViewBuilder
    private var controlsSection: some View {
        VStack(spacing: 16) {
            // Prompt input
            TextField("Describe the image you want to generate...", text: $viewModel.prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .disabled(viewModel.isGenerating)

            // Size presets
            HStack(spacing: 12) {
                Text("Size:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(ImageSize.allCases, id: \.self) { size in
                    Button {
                        viewModel.selectedSize = size
                    } label: {
                        Text(size.label)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(viewModel.selectedSize == size ? Color.purple : Color(.systemGray5))
                            .foregroundColor(viewModel.selectedSize == size ? .white : .primary)
                            .cornerRadius(8)
                    }
                }
            }

            // Generate button
            Button {
                Task {
                    await viewModel.generateImage()
                }
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text(viewModel.isGenerating ? "Generating..." : "Generate Image")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.canGenerate ? Color.purple : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!viewModel.canGenerate)

            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

// MARK: - Supporting Types

enum ImageSize: String, CaseIterable {
    case square = "1024x1024"
    case landscape = "1024x768"
    case portrait = "768x1024"

    var label: String {
        switch self {
        case .square: return "Square"
        case .landscape: return "Landscape"
        case .portrait: return "Portrait"
        }
    }

    var dimensions: (width: Int, height: Int) {
        switch self {
        case .square: return (1024, 1024)
        case .landscape: return (1024, 768)
        case .portrait: return (768, 1024)
        }
    }
}

#Preview {
    ImageGenView()
}
