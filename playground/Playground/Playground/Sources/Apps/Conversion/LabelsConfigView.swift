import SwiftUI

/// View for managing conversion labels
struct LabelsConfigView: View {
    @State private var labels: [String] = []
    @State private var labelCounts: [String: Int] = [:]
    @State private var newLabelName: String = ""
    @State private var showingAddLabel = false
    @State private var labelToDelete: String? = nil
    @Environment(\.dismiss) private var dismiss

    private let storage = ConversionStorage.shared
    private let service = ConversionService.shared
    var onLabelSelected: ((String) -> Void)? = nil

    var body: some View {
        List {
            Section {
                if labels.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tag.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No Labels Yet")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Create labels to organize your conversions")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(labels, id: \.self) { label in
                        Button {
                            // Navigate to conversions filtered by this label
                            onLabelSelected?(label)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "tag.fill")
                                    .foregroundColor(.blue)

                                Text(label)
                                    .font(.body)
                                    .foregroundColor(.primary)

                                Spacer()

                                // Count of conversions with this label
                                if let count = getConversionCount(for: label) {
                                    Text("\(count)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(.systemGray5))
                                        .cornerRadius(8)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                labelToDelete = label
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Labels")
            } footer: {
                if !labels.isEmpty {
                    Text("Swipe left to delete a label. Auto-labeling will choose from these labels.")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Manage Labels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddLabel = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Delete Label", isPresented: Binding(
            get: { labelToDelete != nil },
            set: { if !$0 { labelToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                labelToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let label = labelToDelete {
                    deleteLabel(label)
                }
            }
        } message: {
            if let label = labelToDelete {
                Text("Are you sure you want to delete '\(label)'? This will remove the label from all conversions.")
            }
        }
        .alert("New Label", isPresented: $showingAddLabel) {
            TextField("Label name", text: $newLabelName)
            Button("Cancel", role: .cancel) {
                newLabelName = ""
            }
            Button("Add") {
                addLabel()
            }
        } message: {
            Text("Enter a name for the new label (1-2 words)")
        }
        .onAppear {
            loadLabels()
        }
    }

    private func loadLabels() {
        // Get label counts efficiently with single SQL query
        labelCounts = service.getLabelCounts()

        // Sort labels by count (most to least)
        labels = labelCounts.keys.sorted { label1, label2 in
            let count1 = labelCounts[label1] ?? 0
            let count2 = labelCounts[label2] ?? 0
            return count1 > count2
        }
    }

    private func addLabel() {
        let label = newLabelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            newLabelName = ""
            return
        }

        // Check if label already exists
        if labels.contains(label) {
            print("⚠️ Label already exists")
            newLabelName = ""
            return
        }

        // To add a label, we need to create a dummy conversion with that label
        // Or we can just add it to the list locally and it will be saved when used
        // For now, let's just create a temporary entry to register the label
        labels.append(label)
        // Re-sort by count after adding
        loadLabels()

        newLabelName = ""
        print("✅ Added new label: \(label)")
    }

    private func deleteLabel(_ label: String) {
        // Remove label from all conversions that have it
        switch storage.getAllConversions() {
        case .ok(let conversions):
            for conversion in conversions where conversion.label == label {
                _ = storage.updateLabel(id: conversion.id, label: nil)
            }
        case .err:
            break
        }

        // Remove from local list
        labels.removeAll { $0 == label }
        labelToDelete = nil

        print("✅ Deleted label: \(label)")
    }

    private func getConversionCount(for label: String) -> Int? {
        return labelCounts[label]
    }
}

#Preview {
    NavigationStack {
        LabelsConfigView()
    }
}
