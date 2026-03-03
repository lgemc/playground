import SwiftUI

/// Screen to view and interact with transcripts
struct TranscriptViewerView: View {
    let transcript: Transcript
    let fileName: String
    var onSeekToTimestamp: ((Double) -> Void)?

    @State private var searchQuery = ""
    @State private var selectedSpeaker: String?
    @State private var showWordTimestamps = false
    @State private var showOnlyRelevant = false
    @State private var relevantSegments: Set<String> = []
    @State private var showingSearchSheet = false
    @State private var showingExportSheet = false
    @State private var showingSpeakerMenu = false
    @State private var selectedWord: TranscriptWord?
    @State private var selectedSegment: TranscriptSegment?
    @State private var showingWordDetails = false
    @State private var showingSegmentMenu = false

    var body: some View {
        VStack(spacing: 0) {
            infoHeader
            segmentList
        }
        .navigationTitle("Transcript: \(fileName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: { showingSearchSheet = true }) {
                    Image(systemName: "magnifyingglass")
                }

                Button(action: { showOnlyRelevant.toggle() }) {
                    Image(systemName: showOnlyRelevant ? "star.fill" : "star")
                        .foregroundColor(showOnlyRelevant ? .yellow : .primary)
                }

                Button(action: { showingExportSheet = true }) {
                    Image(systemName: "square.and.arrow.down")
                }

                Button(action: { showingSpeakerMenu = true }) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showingSearchSheet) {
            searchSheet
        }
        .sheet(isPresented: $showingExportSheet) {
            exportSheet
        }
        .confirmationDialog("Filter by Speaker", isPresented: $showingSpeakerMenu) {
            Button("All speakers") {
                selectedSpeaker = nil
            }
            ForEach(Array(transcript.speakers).sorted(), id: \.self) { speaker in
                Button(speaker) {
                    selectedSpeaker = speaker
                }
            }
        }
        .sheet(isPresented: $showingWordDetails) {
            if let word = selectedWord {
                wordDetailsSheet(word: word)
            }
        }
        .sheet(isPresented: $showingSegmentMenu) {
            if let segment = selectedSegment {
                segmentMenuSheet(segment: segment)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: { showWordTimestamps.toggle() }) {
                Image(systemName: showWordTimestamps ? "textformat" : "timer")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .padding()
        }
    }

    // MARK: - Info Header

    private var infoHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Language: \(transcript.language.uppercased())")
                    .fontWeight(.bold)
                Spacer()
                Text("Duration: \(formatDuration(transcript.duration))")
                    .fontWeight(.bold)
            }

            Text("Segments: \(transcript.segments.count) | Speakers: \(transcript.speakers.count)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                    .font(.caption)
                Text("Tap words to share • Long press for details • \(showWordTimestamps ? "Colored by confidence" : "Toggle word mode for confidence view")")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .padding(8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)

            if selectedSpeaker != nil || showOnlyRelevant {
                HStack(spacing: 8) {
                    if let speaker = selectedSpeaker {
                        HStack {
                            Text("Speaker: \(speaker)")
                                .font(.caption)
                            Button(action: { selectedSpeaker = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(16)
                    }

                    if showOnlyRelevant {
                        HStack {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                            Text("Relevant only")
                                .font(.caption)
                            Button(action: { showOnlyRelevant = false }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(16)
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemGray6))
    }

    // MARK: - Segment List

    private var segmentList: some View {
        let segments = filteredSegments

        return Group {
            if segments.isEmpty {
                ContentUnavailableView(
                    "No Segments",
                    systemImage: "text.bubble",
                    description: Text("No segments match your filters")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(segments) { segment in
                            segmentCard(segment)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func segmentCard(_ segment: TranscriptSegment) -> some View {
        let isHighlighted = !searchQuery.isEmpty &&
            segment.text.localizedCaseInsensitiveContains(searchQuery)
        let isRelevant = relevantSegments.contains(segment.id)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    if isRelevant {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                    Text("\(segment.startFormatted) - \(segment.endFormatted)")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .fontWeight(.bold)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(segment.speaker)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(12)

                    Button(action: {
                        selectedSegment = segment
                        showingSegmentMenu = true
                    }) {
                        Image(systemName: "ellipsis")
                            .font(.caption)
                    }
                }
            }

            // Words display
            if segment.words.isEmpty {
                // Fallback to plain text if no words
                Text(segment.text)
                    .font(.body)
            } else {
                // Clickable words in normal mode
                if !showWordTimestamps {
                    Text(segment.words.map { word in
                        AttributedString(word.word + " ")
                    }.reduce(AttributedString(), +))
                        .font(.body)
                        .foregroundColor(.blue)
                        .onTapGesture {
                            // Share full segment text
                            UIPasteboard.general.string = segment.text
                        }
                } else {
                    // Word timestamps with confidence colors
                    FlowLayout(spacing: 4) {
                        ForEach(segment.words) { word in
                            Button(action: {
                                selectedWord = word
                                showingWordDetails = true
                            }) {
                                Text(word.word)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(confidenceColor(word.score))
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(confidenceBorderColor(word.score), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(isHighlighted ? Color.yellow.opacity(0.2) : Color(uiColor: .systemBackground))
        .cornerRadius(8)
        .shadow(radius: 2)
        .onTapGesture {
            if let onSeek = onSeekToTimestamp {
                onSeek(segment.start)
            }
        }
        .onLongPressGesture {
            selectedSegment = segment
            showingSegmentMenu = true
        }
    }

    // MARK: - Search Sheet

    private var searchSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Enter search term...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                if !searchQuery.isEmpty {
                    Text("\(filteredSegments.count) segments match")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .navigationTitle("Search Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingSearchSheet = false
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") {
                        searchQuery = ""
                    }
                    .disabled(searchQuery.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Export Sheet

    private var exportSheet: some View {
        NavigationStack {
            List {
                Button(action: {
                    exportPlainText()
                    showingExportSheet = false
                }) {
                    Label("Plain Text", systemImage: "doc.text")
                }

                Button(action: {
                    exportJSON()
                    showingExportSheet = false
                }) {
                    Label("JSON", systemImage: "curlybraces")
                }

                Button(action: {
                    exportVTT()
                    showingExportSheet = false
                }) {
                    Label("WebVTT", systemImage: "captions.bubble")
                }

                Button(action: {
                    exportSRT()
                    showingExportSheet = false
                }) {
                    Label("SRT", systemImage: "text.bubble")
                }
            }
            .navigationTitle("Export Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showingExportSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Word Details Sheet

    private func wordDetailsSheet(word: TranscriptWord) -> some View {
        NavigationStack {
            List {
                HStack {
                    Text("Start")
                        .fontWeight(.bold)
                    Spacer()
                    Text(String(format: "%.3fs", word.start))
                }

                HStack {
                    Text("End")
                        .fontWeight(.bold)
                    Spacer()
                    Text(String(format: "%.3fs", word.end))
                }

                HStack {
                    Text("Duration")
                        .fontWeight(.bold)
                    Spacer()
                    Text(String(format: "%.3fs", word.duration))
                }

                HStack {
                    Text("Confidence")
                        .fontWeight(.bold)
                    Spacer()
                    Text(String(format: "%.1f%%", word.confidencePercent))
                }

                HStack {
                    Text("Speaker")
                        .fontWeight(.bold)
                    Spacer()
                    Text(word.speaker)
                }
            }
            .navigationTitle(word.word)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Copy") {
                        UIPasteboard.general.string = word.word
                        showingWordDetails = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingWordDetails = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Segment Menu Sheet

    private func segmentMenuSheet(segment: TranscriptSegment) -> some View {
        let isRelevant = relevantSegments.contains(segment.id)

        return NavigationStack {
            List {
                Button(action: {
                    toggleSegmentRelevance(segment)
                    showingSegmentMenu = false
                }) {
                    Label(
                        isRelevant ? "Unmark as relevant" : "Mark as relevant",
                        systemImage: isRelevant ? "star.slash" : "star.fill"
                    )
                }

                Button(action: {
                    UIPasteboard.general.string = segment.text
                    showingSegmentMenu = false
                }) {
                    Label("Copy text", systemImage: "doc.on.doc")
                }

                if onSeekToTimestamp != nil {
                    Button(action: {
                        onSeekToTimestamp?(segment.start)
                        showingSegmentMenu = false
                    }) {
                        Label("Jump to timestamp", systemImage: "play.circle")
                    }
                }
            }
            .navigationTitle("Segment Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showingSegmentMenu = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private var filteredSegments: [TranscriptSegment] {
        var segments = transcript.segments

        if let speaker = selectedSpeaker {
            segments = segments.filter { $0.speaker == speaker }
        }

        if showOnlyRelevant {
            segments = segments.filter { relevantSegments.contains($0.id) }
        }

        return segments
    }

    private func toggleSegmentRelevance(_ segment: TranscriptSegment) {
        if relevantSegments.contains(segment.id) {
            relevantSegments.remove(segment.id)
        } else {
            relevantSegments.insert(segment.id)
        }
        // TODO: Persist to storage
    }

    private func confidenceColor(_ score: Double) -> Color {
        if score >= 0.9 { return Color.green.opacity(0.2) }
        if score >= 0.7 { return Color.yellow.opacity(0.2) }
        if score >= 0.5 { return Color.orange.opacity(0.2) }
        return Color.red.opacity(0.2)
    }

    private func confidenceBorderColor(_ score: Double) -> Color {
        if score >= 0.9 { return Color.green.opacity(0.5) }
        if score >= 0.7 { return Color.yellow.opacity(0.5) }
        if score >= 0.5 { return Color.orange.opacity(0.5) }
        return Color.red.opacity(0.5)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(secs)s"
        }
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    // MARK: - Export Functions

    private func exportPlainText() {
        UIPasteboard.general.string = transcript.fullText
        print("Plain text copied to clipboard")
    }

    private func exportJSON() {
        if let json = try? transcript.toJSONString() {
            UIPasteboard.general.string = json
            print("JSON copied to clipboard")
        }
    }

    private func exportVTT() {
        UIPasteboard.general.string = generateVTT()
        print("WebVTT copied to clipboard")
    }

    private func exportSRT() {
        UIPasteboard.general.string = generateSRT()
        print("SRT copied to clipboard")
    }

    private func generateVTT() -> String {
        var vtt = "WEBVTT\n\n"

        for segment in transcript.segments {
            vtt += "\(formatVTTTimestamp(segment.start)) --> \(formatVTTTimestamp(segment.end))\n"
            vtt += "\(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
        }

        return vtt
    }

    private func generateSRT() -> String {
        var srt = ""
        var index = 1

        for segment in transcript.segments {
            srt += "\(index)\n"
            srt += "\(formatSRTTimestamp(segment.start)) --> \(formatSRTTimestamp(segment.end))\n"
            srt += "\(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
            index += 1
        }

        return srt
    }

    private func formatVTTTimestamp(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = seconds.truncatingRemainder(dividingBy: 60)

        return String(format: "%02d:%02d:%06.3f", hours, minutes, secs)
    }

    private func formatSRTTimestamp(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)

        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }
}

// MARK: - Flow Layout Helper

/// A custom layout that flows items horizontally and wraps to new lines
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            let position = result.positions[index]
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TranscriptViewerView(
            transcript: Transcript(
                status: "completed",
                language: "en",
                segments: [
                    TranscriptSegment(
                        start: 0.0,
                        end: 5.2,
                        text: "Hello world, this is a test transcript.",
                        words: [
                            TranscriptWord(word: "Hello", start: 0.0, end: 0.5, score: 0.95),
                            TranscriptWord(word: "world", start: 0.6, end: 1.0, score: 0.92),
                            TranscriptWord(word: "this", start: 1.5, end: 1.8, score: 0.88),
                            TranscriptWord(word: "is", start: 1.9, end: 2.0, score: 0.90),
                            TranscriptWord(word: "a", start: 2.1, end: 2.2, score: 0.85),
                            TranscriptWord(word: "test", start: 2.3, end: 2.7, score: 0.93),
                            TranscriptWord(word: "transcript", start: 2.8, end: 3.5, score: 0.91)
                        ],
                        speaker: "SPEAKER_00"
                    ),
                    TranscriptSegment(
                        start: 5.5,
                        end: 10.0,
                        text: "This demonstrates the transcript viewer features.",
                        words: [
                            TranscriptWord(word: "This", start: 5.5, end: 5.8, score: 0.96),
                            TranscriptWord(word: "demonstrates", start: 6.0, end: 6.8, score: 0.89),
                            TranscriptWord(word: "the", start: 6.9, end: 7.0, score: 0.94),
                            TranscriptWord(word: "transcript", start: 7.1, end: 7.8, score: 0.92),
                            TranscriptWord(word: "viewer", start: 7.9, end: 8.3, score: 0.90),
                            TranscriptWord(word: "features", start: 8.4, end: 9.0, score: 0.87)
                        ],
                        speaker: "SPEAKER_01"
                    )
                ],
                sourceFile: "example.mp4",
                generatedAt: Date()
            ),
            fileName: "example.mp4"
        )
    }
}
