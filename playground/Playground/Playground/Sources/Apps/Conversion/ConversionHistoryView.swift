import SwiftUI

/// Main view displaying conversion history as cards
struct ConversionHistoryView: View {
    @State private var conversions: [Conversion] = []
    @State private var showingInput = false
    @State private var isLoading = true

    private let conversionService = ConversionService.shared

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isLoading {
                loadingView
            } else if conversions.isEmpty {
                emptyStateView
            } else {
                conversionsListView
            }

            // Floating Action Button
            addButton
        }
        .onAppear {
            loadConversions()
        }
        .sheet(isPresented: $showingInput) {
            ConversionInputView(conversions: $conversions)
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading conversions...")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No Conversions Yet")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Tap the + button to create your first AI conversion")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    @ViewBuilder
    private var conversionsListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(conversions) { conversion in
                    ConversionCard(conversion: conversion)
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteConversion(conversion)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onAppear {
                            // Auto-refresh if conversion is still processing
                            if conversion.outputText == nil && conversion.outputFileId == nil {
                                scheduleRefresh(for: conversion)
                            }
                        }
                }
            }
            .padding()
            .padding(.bottom, 80) // Space for FAB
        }
        .refreshable {
            loadConversions()
        }
    }

    @ViewBuilder
    private var addButton: some View {
        Button(action: { showingInput = true }) {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(Color.blue)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .padding(24)
    }

    // MARK: - Data Management

    private func loadConversions() {
        conversions = conversionService.getAllConversions()
        isLoading = false
    }

    private func deleteConversion(_ conversion: Conversion) {
        do {
            try conversionService.deleteConversion(id: conversion.id)
            conversions.removeAll { $0.id == conversion.id }
        } catch {
            print("❌ Failed to delete conversion: \(error)")
        }
    }

    private func scheduleRefresh(for conversion: Conversion) {
        // Refresh after 2 seconds to check if processing is complete
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            if let updated = conversionService.getConversion(id: conversion.id),
               let index = conversions.firstIndex(where: { $0.id == conversion.id }) {
                conversions[index] = updated

                // Schedule another refresh if still processing
                if updated.outputText == nil && updated.outputFileId == nil {
                    scheduleRefresh(for: updated)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ConversionHistoryView()
            .navigationTitle("AI Conversions")
    }
}
