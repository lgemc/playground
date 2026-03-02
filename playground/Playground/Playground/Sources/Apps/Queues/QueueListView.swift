import SwiftUI

/// Overview of all queues with real-time metrics
struct QueueListView: View {
    @State private var metricsMap: [String: QueueMetrics] = [:]
    @State private var dlqCount: Int = 0
    @State private var isLoading = true
    @State private var timer: Timer?

    var body: some View {
        List {
            // Dead Letter Queue section
            Section {
                NavigationLink(destination: DlqView()) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Dead Letter Queue")
                        Spacer()
                        if dlqCount > 0 {
                            Text("\(dlqCount)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .cornerRadius(8)
                        }
                    }
                }
            }

            // Queue list section
            Section(header: Text("Active Queues")) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if metricsMap.isEmpty {
                    Text("No queues configured")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(QueueConfigs.getEnabled(), id: \.id) { config in
                        if let metrics = metricsMap[config.id] {
                            NavigationLink(destination: QueueDetailView(queueId: config.id, queueName: config.name)) {
                                QueueMetricsRow(config: config, metrics: metrics)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Queues")
        .onAppear {
            Task {
                await loadMetrics()
                startAutoRefresh()
            }
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .refreshable {
            await loadMetrics()
        }
    }

    private func loadMetrics() async {
        do {
            metricsMap = try await QueueService.shared.getAllMetrics()
            dlqCount = try await QueueService.shared.getDlqMessageCount()
            isLoading = false
        } catch {
            print("Failed to load queue metrics: \(error)")
            isLoading = false
        }
    }

    private func startAutoRefresh() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task {
                await loadMetrics()
            }
        }
    }

    private func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }
}

/// Row displaying metrics for a single queue
struct QueueMetricsRow: View {
    let config: QueueConfig
    let metrics: QueueMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(config.name)
                    .font(.headline)
                Spacer()
                MessageCountBadge(count: metrics.messageCount)
            }

            HStack(spacing: 16) {
                MetricItem(label: "Available", value: metrics.availableCount, color: .blue)
                MetricItem(label: "Locked", value: metrics.lockedCount, color: .orange)
                MetricItem(label: "Subscribers", value: metrics.subscriberCount, color: .green)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

/// Badge showing message count with color coding
struct MessageCountBadge: View {
    let count: Int

    var color: Color {
        if count == 0 { return .gray }
        if count < 50 { return .blue }
        if count < 100 { return .orange }
        return .red
    }

    var body: some View {
        Text("\(count)")
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(8)
    }
}

/// Individual metric display
struct MetricItem: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(label): \(value)")
                .foregroundColor(.secondary)
        }
    }
}
