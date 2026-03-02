import SwiftUI

/// Detailed view of messages in a specific queue
struct QueueDetailView: View {
    let queueId: String
    let queueName: String

    @State private var messages: [QueueMessage] = []
    @State private var metrics: QueueMetrics?
    @State private var isLoading = true
    @State private var selectedMessage: QueueMessage?
    @State private var showingMessageDetail = false
    @State private var showingDeleteConfirm = false
    @State private var showingClearQueueConfirm = false
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Metrics summary
            if let metrics = metrics {
                MetricsSummary(metrics: metrics)
                    .padding()
                    .background(Color(.systemGray6))
            }

            // Message list
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if messages.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No messages in queue")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(messages) { message in
                        MessageRow(message: message)
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
        .navigationTitle(queueName)
        .toolbar {
            if !messages.isEmpty {
                Button(role: .destructive) {
                    showingClearQueueConfirm = true
                } label: {
                    Label("Clear Queue", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingMessageDetail) {
            if let message = selectedMessage {
                MessageDetailSheet(message: message)
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
            Text("Are you sure you want to delete this message?")
        }
        .alert("Clear Queue", isPresented: $showingClearQueueConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    await clearQueue()
                }
            }
        } message: {
            Text("Are you sure you want to clear all \(messages.count) messages from this queue?")
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
            messages = try await QueueService.shared.getMessages(queueId: queueId)
            metrics = try await QueueService.shared.getQueueMetrics(queueId)
            isLoading = false
        } catch {
            print("Failed to load messages: \(error)")
            isLoading = false
        }
    }

    private func deleteMessage(_ message: QueueMessage) async {
        do {
            try await QueueService.shared.acknowledge(message.id)
            await loadMessages()
        } catch {
            print("Failed to delete message: \(error)")
        }
    }

    private func retryMessage(_ message: QueueMessage) async {
        do {
            try await QueueService.shared.reject(message.id, requeue: true, errorReason: "Manual retry")
            await loadMessages()
        } catch {
            print("Failed to retry message: \(error)")
        }
    }

    private func clearQueue() async {
        do {
            try await QueueService.shared.clearQueue(queueId)
            await loadMessages()
        } catch {
            print("Failed to clear queue: \(error)")
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

/// Summary metrics display
struct MetricsSummary: View {
    let metrics: QueueMetrics

    var body: some View {
        HStack(spacing: 20) {
            MetricColumn(label: "Total", value: metrics.messageCount, color: .blue)
            Divider()
            MetricColumn(label: "Available", value: metrics.availableCount, color: .green)
            Divider()
            MetricColumn(label: "Locked", value: metrics.lockedCount, color: .orange)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MetricColumn: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// Row displaying a single message
struct MessageRow: View {
    let message: QueueMessage

    var statusColor: Color {
        let now = Date()
        if let lockExpires = message.lockExpiresAt, lockExpires > now {
            return .orange // Locked
        }
        if message.deliveryCount >= 2 {
            return .red // Near max retries
        }
        return .green // Available
    }

    var statusIcon: String {
        let now = Date()
        if let lockExpires = message.lockExpiresAt, lockExpires > now {
            return "lock.fill"
        }
        if message.deliveryCount >= 2 {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.circle.fill"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.eventType)
                    .font(.headline)

                HStack(spacing: 8) {
                    Label(message.appId, systemImage: "app.fill")
                    Label("Attempt \(message.deliveryCount)", systemImage: "arrow.clockwise")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Text(formatTimestamp(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let lockExpires = message.lockExpiresAt, lockExpires > Date() {
                VStack(alignment: .trailing) {
                    Text("LOCKED")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    if let lockedBy = message.lockedBy {
                        Text(lockedBy.prefix(8))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
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

/// Detail sheet showing full message information
struct MessageDetailSheet: View {
    let message: QueueMessage
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

                Section("Processing Status") {
                    DetailRow(label: "Delivery Count", value: "\(message.deliveryCount)")
                    if let lastDelivered = message.lastDeliveredAt {
                        DetailRow(label: "Last Delivered", value: formatDate(lastDelivered))
                    }
                    if let lockedBy = message.lockedBy {
                        DetailRow(label: "Locked By", value: lockedBy)
                    }
                    if let lockExpires = message.lockExpiresAt {
                        DetailRow(label: "Lock Expires", value: formatDate(lockExpires))
                    }
                    if let visibleAfter = message.visibleAfter {
                        DetailRow(label: "Visible After", value: formatDate(visibleAfter))
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
            .navigationTitle("Message Details")
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

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .textSelection(.enabled)
        }
    }
}
