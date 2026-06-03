import SwiftUI

/// Main view displaying conversion history as cards
struct ConversionHistoryView: View {
    @State private var conversions: [Conversion] = []
    @State private var filteredConversions: [Conversion] = []
    @State private var searchText = ""
    @State private var showingInput = false
    @State private var preselectedInputType: ConversionType? = nil
    @State private var isLoading = true
    @State private var selectedFilter: FilterOption = .all
    @State private var availableLabels: [String] = []
    @State private var labelCounts: [String: Int] = [:]
    @State private var navigateToChatId: String?
    @State private var showingSearch = false
    @State private var selectedView: ViewType = .conversions
    @State private var currentPage = 0
    @State private var hasMorePages = true
    @State private var isLoadingMore = false
    @State private var showingSettings = false

    private let conversionService = ConversionService.shared
    private let conversionStorage = ConversionStorage.shared
    private let pageSize = 50

    enum ViewType {
        case conversions
        case labels
    }

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
        VStack(spacing: 0) {
            if selectedView == .conversions {
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
            } else {
                LabelsConfigView(onLabelSelected: { label in
                    // Switch to conversions view and apply the label filter
                    selectedView = .conversions
                    selectedFilter = .label(label)
                })
            }

            // Bottom navigation bar or search bar
            if showingSearch {
                searchBar
            } else {
                bottomNavigationBar
            }
        }
        .navigationTitle(selectedView == .conversions ? "AI Conversions" : "Labels")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                ConversionSettingsView()
            }
        }
        .modelDownloadPermissionAlert()
        .onChange(of: searchText) { oldValue, newValue in
            filterConversions()
        }
        .onChange(of: selectedView) { oldValue, newValue in
            if newValue == .labels {
                showingSearch = false
            }
        }
        .onChange(of: selectedFilter) { oldValue, newValue in
            filterConversions()
        }
        .onAppear {
            loadConversions()
            loadLabels()
        }
        .sheet(isPresented: $showingInput, onDismiss: {
            // Reload from storage to ensure we have the latest persisted data
            print("🔄 Sheet dismissed, reloading conversions...")
            preselectedInputType = nil
            // Immediate reload to refresh the list
            loadConversions()
            loadLabels()
        }) {
            ConversionInputView(preselectedType: preselectedInputType) { chatId in
                navigateToChatId = chatId
            }
        }
        .onChange(of: navigateToChatId) { oldValue, newValue in
            if newValue != nil {
                // Reload conversions after a short delay to ensure metadata is saved
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                    loadConversions()
                }
            }
        }
        .background(
            NavigationLink(
                destination: navigateToChatId.map { ChatView(chatId: $0) },
                isActive: Binding(
                    get: { navigateToChatId != nil },
                    set: {
                        if !$0 {
                            navigateToChatId = nil
                            // Reload when coming back from chat
                            loadConversions()
                            loadLabels()
                        }
                    }
                )
            ) {
                EmptyView()
            }
            .hidden()
        )
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
        VStack {
            Spacer()

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

            Spacer()
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
                        // Lazy loading trigger
                        if conversion == filteredConversions.last && hasMorePages && !isLoadingMore {
                            loadMoreConversions()
                        }

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
                            // Lazy loading trigger
                            if conversion == filteredConversions.last && hasMorePages && !isLoadingMore {
                                loadMoreConversions()
                            }

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

            // Loading indicator at the bottom when loading more
            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
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
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)

                TextField("Search conversions...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            Button {
                withAnimation {
                    showingSearch = false
                    searchText = ""
                }
            } label: {
                Text("Cancel")
                    .foregroundColor(.blue)
                    .font(.body)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5),
            alignment: .top
        )
    }

    @ViewBuilder
    private var bottomNavigationBar: some View {
        HStack(spacing: 0) {
            // Conversions tab
            Button {
                selectedView = .conversions
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                        .font(.title2)
                    Text("Conversions")
                        .font(.caption)
                }
                .foregroundColor(selectedView == .conversions ? .blue : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Labels tab
            Button {
                selectedView = .labels
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "tag")
                        .font(.title2)
                    Text("Labels")
                        .font(.caption)
                }
                .foregroundColor(selectedView == .labels ? .blue : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Search button
            Button {
                withAnimation {
                    showingSearch = true
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                    Text("Search")
                        .font(.caption)
                }
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // New conversion menu
            Menu {
                ForEach(ConversionType.allCases, id: \.self) { type in
                    Button {
                        openInputWithType(type)
                    } label: {
                        HStack {
                            Image(systemName: type.inputIcon)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                            Image(systemName: type.outputIcon)
                            Text(type.displayName)
                        }
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                    Text("New")
                        .font(.caption)
                }
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5),
            alignment: .top
        )
    }

    // MARK: - Data Management

    private func openInputWithType(_ type: ConversionType) {
        preselectedInputType = type
        showingInput = true
    }

    private func loadConversions() {
        // Reset pagination
        currentPage = 0
        hasMorePages = true

        // Load first page based on filter
        let loaded: [Conversion]
        switch selectedFilter {
        case .all:
            loaded = conversionService.getAllConversions(limit: pageSize, offset: 0)
        case .favorites:
            loaded = conversionService.getFavorites(limit: pageSize, offset: 0)
        case .label(let labelName):
            loaded = conversionService.getConversionsByLabel(label: labelName, limit: pageSize, offset: 0)
        }

        print("📋 Loaded \(loaded.count) conversions from storage (page 0)")
        conversions = loaded
        hasMorePages = loaded.count == pageSize
        filterConversions()
        isLoading = false
    }

    private func loadMoreConversions() {
        guard !isLoadingMore && hasMorePages else { return }

        isLoadingMore = true
        currentPage += 1

        // Load next page based on filter
        let moreConversions: [Conversion]
        switch selectedFilter {
        case .all:
            moreConversions = conversionService.getAllConversions(limit: pageSize, offset: currentPage * pageSize)
        case .favorites:
            moreConversions = conversionService.getFavorites(limit: pageSize, offset: currentPage * pageSize)
        case .label(let labelName):
            moreConversions = conversionService.getConversionsByLabel(label: labelName, limit: pageSize, offset: currentPage * pageSize)
        }

        print("📋 Loaded \(moreConversions.count) more conversions (page \(currentPage))")

        // Append to existing list
        conversions.append(contentsOf: moreConversions)
        hasMorePages = moreConversions.count == pageSize
        filterConversions()
        isLoadingMore = false
    }

    private func filterConversions() {
        // Since we're now filtering at database level, we only apply search here
        var filtered = conversions

        // Apply search (in-memory for now, can be moved to SQL later)
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
        // Get label counts efficiently with single SQL query
        labelCounts = conversionService.getLabelCounts()

        // Sort labels by count (most to least)
        availableLabels = labelCounts.keys.sorted { label1, label2 in
            let count1 = labelCounts[label1] ?? 0
            let count2 = labelCounts[label2] ?? 0
            return count1 > count2
        }
    }

    private func getConversionCount(for label: String) -> Int {
        return labelCounts[label] ?? 0
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
