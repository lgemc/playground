import SwiftUI
import Combine

/// Main view for displaying logs with filtering and real-time updates
struct LogsView: View {
    @State private var logs: [LogEntry] = []
    @State private var apps: [String] = []
    @State private var selectedApp: String?
    @State private var selectedSeverity: LogSeverity?
    @State private var isLoading = true
    @State private var selectedLog: LogEntry?
    @State private var showingSidebar = false
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Filter bar
                FilterBar(
                    apps: apps,
                    selectedApp: $selectedApp,
                    selectedSeverity: $selectedSeverity
                )
                .padding()
                .background(Color(.systemGray6))

                // Logs list
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if logs.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No logs")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(logs) { log in
                            LogItemView(log: log)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedLog = log
                                    withAnimation {
                                        showingSidebar = true
                                    }
                                }
                        }
                    }
                }
            }

            // Metadata sidebar
            if showingSidebar, let log = selectedLog {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        // Overlay to dismiss sidebar
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation {
                                    showingSidebar = false
                                }
                            }

                        // Sidebar
                        MetadataSidebar(log: log) {
                            withAnimation {
                                showingSidebar = false
                            }
                        }
                        .frame(width: min(400, geometry.size.width * 0.8))
                        .transition(.move(edge: .trailing))
                    }
                }
            }
        }
        .navigationTitle("Logs")
        .onAppear {
            Task {
                await loadLogs()
                await loadApps()
                subscribeToLogs()
            }
        }
        .onChange(of: selectedApp) {
            Task {
                await loadLogs()
            }
        }
        .onChange(of: selectedSeverity) {
            Task {
                await loadLogs()
            }
            // Close sidebar when filters change
            withAnimation {
                showingSidebar = false
            }
        }
        .refreshable {
            await loadLogs()
            await loadApps()
        }
    }

    private func loadLogs() async {
        do {
            logs = try await LogStorage.shared.getLogs(
                appId: selectedApp,
                severity: selectedSeverity
            )
            isLoading = false
        } catch {
            print("Failed to load logs: \(error)")
            isLoading = false
        }
    }

    private func loadApps() async {
        do {
            apps = try await LogStorage.shared.getApps()
        } catch {
            print("Failed to load apps: \(error)")
        }
    }

    private func subscribeToLogs() {
        LogStorage.shared.logStream
            .receive(on: DispatchQueue.main)
            .sink { newLog in
                // Insert at top if matches current filters
                let appMatches = selectedApp == nil || newLog.appId == selectedApp
                let severityMatches = selectedSeverity == nil || newLog.severityEnum == selectedSeverity

                if appMatches && severityMatches {
                    logs.insert(newLog, at: 0)
                }

                // Update apps list if new app
                if !apps.contains(newLog.appId) {
                    apps.append(newLog.appId)
                    apps.sort()
                }
            }
            .store(in: &cancellables)
    }
}

/// Filter bar for app and severity selection
struct FilterBar: View {
    let apps: [String]
    @Binding var selectedApp: String?
    @Binding var selectedSeverity: LogSeverity?

    var body: some View {
        HStack(spacing: 12) {
            // App filter
            Menu {
                Button("All Apps") {
                    selectedApp = nil
                }
                Divider()
                ForEach(apps, id: \.self) { app in
                    Button(app) {
                        selectedApp = app
                    }
                }
            } label: {
                HStack {
                    Text("App: \(selectedApp ?? "All")")
                    Image(systemName: "chevron.down")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .cornerRadius(8)
            }

            // Severity filter
            Menu {
                Button("All Severities") {
                    selectedSeverity = nil
                }
                Divider()
                ForEach([LogSeverity.debug, .info, .warning, .error, .critical], id: \.self) { severity in
                    Button(severity.name.capitalized) {
                        selectedSeverity = severity
                    }
                }
            } label: {
                HStack {
                    Text("Severity: \(selectedSeverity?.name.capitalized ?? "All")")
                    Image(systemName: "chevron.down")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .cornerRadius(8)
            }

            Spacer()
        }
    }
}

/// Individual log item display
struct LogItemView: View {
    let log: LogEntry

    var severityColor: Color {
        switch log.severityEnum {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .critical: return .purple
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Severity badge
            Text(log.severity.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(severityColor)
                .cornerRadius(4)
                .frame(width: 60)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(log.appName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatTimestamp(log.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(log.message)
                    .font(.body)
                    .lineLimit(2)

                if log.eventType != "general" {
                    Label(log.eventType, systemImage: "tag")
                        .font(.caption2)
                        .foregroundColor(.secondary)
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

/// Sidebar showing detailed log metadata
struct MetadataSidebar: View {
    let log: LogEntry
    let onDismiss: () -> Void

    var severityColor: Color {
        switch log.severityEnum {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .critical: return .purple
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Log Details")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemGray6))

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Severity badge
                    HStack {
                        Text(log.severity.uppercased())
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(severityColor)
                            .cornerRadius(6)
                        Spacer()
                    }

                    // Metadata fields
                    DetailField(label: "App", value: log.appName)
                    DetailField(label: "Event Type", value: log.eventType)
                    DetailField(label: "Timestamp", value: formatFullDate(log.timestamp))

                    // Message
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Message")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(log.message)
                            .font(.body)
                            .textSelection(.enabled)
                    }

                    // Additional metadata
                    if let metadata = log.getMetadata(), !metadata.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Metadata")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted),
                               let jsonString = String(data: jsonData, encoding: .utf8) {
                                Text(jsonString)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemBackground))
        .shadow(radius: 10)
    }

    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct DetailField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
