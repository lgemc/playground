import SwiftUI

/// Main view displaying conversion history as cards
struct ConversionHistoryView: View {
    @State private var conversions: [Conversion] = []
    @State private var filteredConversions: [Conversion] = []
    @State private var searchText = ""
    @State private var showingInput = false
    @State private var showingSettings = false
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
        .navigationTitle("AI Conversions")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search conversions...")
        .onChange(of: searchText) { oldValue, newValue in
            filterConversions()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
        .onAppear {
            loadConversions()
        }
        .sheet(isPresented: $showingInput, onDismiss: {
            // Reload from storage to ensure we have the latest persisted data
            // Small delay to ensure async storage write completes
            print("🔄 Sheet dismissed, reloading conversions...")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                loadConversions()
            }
        }) {
            ConversionInputView()
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
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
        List {
            ForEach(filteredConversions) { conversion in
                if let chatId = conversion.metadata["chat_id"] {
                    NavigationLink(value: chatId) {
                        ConversionCard(conversion: conversion)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .onAppear {
                        // Auto-refresh if conversion is still processing
                        if conversion.outputText == nil && conversion.outputFileId == nil {
                            scheduleRefresh(for: conversion)
                        }
                    }
                } else {
                    ConversionCard(conversion: conversion)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .onAppear {
                            // Auto-refresh if conversion is still processing
                            if conversion.outputText == nil && conversion.outputFileId == nil {
                                scheduleRefresh(for: conversion)
                            }
                        }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    deleteConversion(filteredConversions[index])
                }
            }

            // Spacer for FAB
            Color.clear
                .frame(height: 80)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .refreshable {
            loadConversions()
        }
        .navigationDestination(for: String.self) { chatId in
            ChatView(chatId: chatId)
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
        let loaded = conversionService.getAllConversions()
        print("📋 Loaded \(loaded.count) conversions from storage")
        for conv in loaded.prefix(5) {
            print("  - \(conv.type.displayName): \(conv.id)")
        }
        conversions = loaded
        filterConversions()
        isLoading = false
    }

    private func filterConversions() {
        if searchText.isEmpty {
            filteredConversions = conversions
        } else {
            filteredConversions = conversions.filter { conversion in
                // Search in input text
                if let input = conversion.inputText, input.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                // Search in output text
                if let output = conversion.outputText, output.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                // Search in type
                if conversion.type.displayName.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                return false
            }
        }
    }

    private func deleteConversion(_ conversion: Conversion) {
        do {
            try conversionService.deleteConversion(id: conversion.id)
            conversions.removeAll { $0.id == conversion.id }
            filterConversions() // Update filtered list
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
