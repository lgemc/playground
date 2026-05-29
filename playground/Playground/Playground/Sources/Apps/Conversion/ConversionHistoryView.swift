import SwiftUI

/// Main view displaying conversion history as cards
struct ConversionHistoryView: View {
    @State private var conversions: [Conversion] = []
    @State private var filteredConversions: [Conversion] = []
    @State private var searchText = ""
    @State private var showingInput = false
    @State private var preselectedInputType: ConversionType? = nil
    @State private var showingSettings = false
    @State private var isLoading = true
    @State private var selectedFilter: FilterOption = .all
    @State private var availableLabels: [String] = []

    private let conversionService = ConversionService.shared
    private let conversionStorage = ConversionStorage.shared

    enum FilterOption: Equatable {
        case all
        case favorites
        case label(String)

        var displayName: String {
            switch self {
            case .all: return "All"
            case .favorites: return "Favorites"
            case .label(let name): return name
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // Filter pills
                if !conversions.isEmpty {
                    filterBar
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }

                if isLoading {
                    loadingView
                } else if conversions.isEmpty {
                    emptyStateView
                } else {
                    conversionsListView
                }
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
        .onChange(of: selectedFilter) { oldValue, newValue in
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
            loadLabels()
        }
        .sheet(isPresented: $showingInput, onDismiss: {
            // Reload from storage to ensure we have the latest persisted data
            // Small delay to ensure async storage write completes
            print("🔄 Sheet dismissed, reloading conversions...")
            preselectedInputType = nil
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                loadConversions()
            }
        }) {
            ConversionInputView(preselectedType: preselectedInputType)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
    }

    @ViewBuilder
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // All filter
                FilterPill(
                    title: "All",
                    isSelected: selectedFilter == .all
                ) {
                    selectedFilter = .all
                }

                // Favorites filter
                FilterPill(
                    title: "Favorites",
                    icon: "star.fill",
                    isSelected: selectedFilter == .favorites
                ) {
                    selectedFilter = .favorites
                }

                // Label filters
                ForEach(availableLabels, id: \.self) { label in
                    FilterPill(
                        title: label,
                        icon: "tag.fill",
                        isSelected: selectedFilter == .label(label)
                    ) {
                        selectedFilter = .label(label)
                    }
                }
            }
            .padding(.horizontal, 4)
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
                        ConversionCard(conversion: conversion, onUpdate: {
                            loadConversions()
                            loadLabels()
                        })
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .onAppear {
                        // Auto-refresh if conversion is still processing or streaming
                        if conversion.outputText == nil && conversion.outputFileId == nil {
                            scheduleRefresh(for: conversion)
                        } else if conversion.metadata["streaming"] == "true" {
                            scheduleRefresh(for: conversion)
                        }
                    }
                } else {
                    ConversionCard(conversion: conversion, onUpdate: {
                        loadConversions()
                        loadLabels()
                    })
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .onAppear {
                            // Auto-refresh if conversion is still processing or streaming
                            if conversion.outputText == nil && conversion.outputFileId == nil {
                                scheduleRefresh(for: conversion)
                            } else if conversion.metadata["streaming"] == "true" {
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
        Menu {
            ForEach(ConversionType.allCases, id: \.self) { type in
                Button {
                    openInputWithType(type)
                } label: {
                    Label(type.displayName, systemImage: type.inputIcon)
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(Color.blue)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        } primaryAction: {
            showingInput = true
        }
        .padding(.trailing, 24)
        .padding(.bottom, 80) // Closer to bottom, near search area
    }

    // MARK: - Data Management

    private func openInputWithType(_ type: ConversionType) {
        preselectedInputType = type
        showingInput = true
    }

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
        var filtered = conversions

        // Apply filter
        switch selectedFilter {
        case .all:
            break // No filtering
        case .favorites:
            filtered = filtered.filter { $0.isFavorite }
        case .label(let labelName):
            filtered = filtered.filter { $0.label == labelName }
        }

        // Apply search
        if !searchText.isEmpty {
            filtered = filtered.filter { conversion in
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

        filteredConversions = filtered
    }

    private func loadLabels() {
        let result = conversionStorage.getAllLabels()
        if case .ok(let labels) = result {
            availableLabels = labels
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
        // Refresh every 0.5 seconds for streaming, 2 seconds for processing
        let delay = conversion.metadata["streaming"] == "true" ? 500_000_000 : 2_000_000_000

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay))

            if let updated = conversionService.getConversion(id: conversion.id),
               let index = conversions.firstIndex(where: { $0.id == conversion.id }) {
                conversions[index] = updated
                filterConversions() // Update filtered list to show new content

                // Schedule another refresh if still processing or streaming
                if updated.outputText == nil && updated.outputFileId == nil {
                    scheduleRefresh(for: updated)
                } else if updated.metadata["streaming"] == "true" {
                    scheduleRefresh(for: updated)
                }
            }
        }
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

#Preview {
    NavigationStack {
        ConversionHistoryView()
            .navigationTitle("AI Conversions")
    }
}
