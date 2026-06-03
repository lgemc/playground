import SwiftUI

/// View for managing conversion labels
struct LabelsConfigView: View {
    @State private var labels: [String] = []
    @State private var newLabelName: String = ""
    @State private var showingAddLabel = false
    @State private var labelToDelete: String? = nil

    private let storage = ConversionStorage.shared

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
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundColor(.blue)

                            Text(label)
                                .font(.body)

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
        switch storage.getAllLabels() {
        case .ok(let loadedLabels):
            labels = loadedLabels
        case .err(let error):
            print("❌ Failed to load labels: \(error)")
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
        labels.sort()

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
        switch storage.getConversionsByLabel(label: label) {
        case .ok(let conversions):
            return conversions.count
        case .err:
            return nil
        }
    }
}

#Preview {
    NavigationStack {
        LabelsConfigView()
    }
}
