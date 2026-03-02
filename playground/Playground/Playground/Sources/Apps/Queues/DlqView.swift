import SwiftUI

/// View for the Dead Letter Queue (messages that failed after max retries)
struct DlqView: View {
    @State private var messages: [DlqMessage] = []
    @State private var isLoading = true
    @State private var selectedMessage: DlqMessage?
    @State private var showingMessageDetail = false
    @State private var showingDeleteConfirm = false
    @State private var showingClearConfirm = false
    @State private var timer: Timer?

    var body: some View {
        VStack {
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if messages.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("No failed messages")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(messages) { message in
                        DlqMessageRow(message: message)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMessage = message
                                showingMessageDetail = true
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    selectedMessage = message
                                    showingDeleteConfirm = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    Task {
                                        await retryMessage(message)
                                    }
                                } label: {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                }
                                .tint(.blue)
                            }
                    }
                }
            }
        }
        .navigationTitle("Dead Letter Queue")
        .toolbar {
            if !messages.isEmpty {
                Button(role: .destructive) {
                    showingClearConfirm = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingMessageDetail) {
            if let message = selectedMessage {
                DlqMessageDetailSheet(message: message)
            }
        }
        .alert("Delete Message", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let message = selectedMessage {
                    Task {
                        await deleteMessage(message)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to permanently delete this failed message?")
        }
        .alert("Clear All", isPresented: $showingClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    await clearAll()
                }
            }
        } message: {
            Text("Are you sure you want to permanently delete all \(messages.count) failed messages?")
        }
        .onAppear {
            Task {
                await loadMessages()
                startAutoRefresh()
            }
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .refreshable {
            await loadMessages()
        }
    }

    private func loadMessages() async {
        do {
            messages = try await QueueService.shared.getDlqMessages()
            isLoading = false
        } catch {
            print("Failed to load DLQ messages: \(error)")
            isLoading = false
        }
    }

    private func deleteMessage(_ message: DlqMessage) async {
        do {
            try await QueueService.shared.deleteDlqMessage(message.id)
            await loadMessages()
        } catch {
            print("Failed to delete DLQ message: \(error)")
        }
    }

    private func retryMessage(_ message: DlqMessage) async {
        do {
            try await QueueService.shared.retryFromDlq(message.id)
            await loadMessages()
        } catch {
            print("Failed to retry message: \(error)")
        }
    }

    private func clearAll() async {
        do {
            try await QueueService.shared.clearDlq()
            await loadMessages()
        } catch {
            print("Failed to clear DLQ: \(error)")
        }
    }

    private func startAutoRefresh() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task {
                await loadMessages()
            }
        }
    }

    private func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }
}

/// Row displaying a single DLQ message
struct DlqMessageRow: View {
    let message: DlqMessage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.eventType)
                    .font(.headline)

                HStack(spacing: 8) {
                    Label(message.appId, systemImage: "app.fill")
                    Label("Queue: \(message.queueId)", systemImage: "tray.fill")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                if let errorReason = message.errorReason {
                    Text(errorReason)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }

                Text("Failed: \(formatTimestamp(message.movedToDlqAt))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("\(message.deliveryCount)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.2))
                    .foregroundColor(.red)
                    .cornerRadius(4)
                Text("attempts")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Detail sheet showing full DLQ message information
struct DlqMessageDetailSheet: View {
    let message: DlqMessage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Message Info") {
                    DetailRow(label: "ID", value: message.id)
                    DetailRow(label: "Event Type", value: message.eventType)
                    DetailRow(label: "App ID", value: message.appId)
                    DetailRow(label: "Queue", value: message.queueId)
                }

                Section("Failure Details") {
                    DetailRow(label: "Delivery Attempts", value: "\(message.deliveryCount)")
                    if let lastDelivered = message.lastDeliveredAt {
                        DetailRow(label: "Last Attempt", value: formatDate(lastDelivered))
                    }
                    DetailRow(label: "Moved to DLQ", value: formatDate(message.movedToDlqAt))
                    if let errorReason = message.errorReason {
                        VStack(alignment: .leading) {
                            Text("Error Reason")
                                .foregroundColor(.secondary)
                            Text(errorReason)
                                .foregroundColor(.red)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Payload") {
                    if let payload = message.getPayload(),
                       let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        Text(jsonString)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("No payload")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Failed Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
