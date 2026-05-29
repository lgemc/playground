import Foundation

/// Represents a timestamped segment from Whisper transcription
struct WhisperSegment: Codable, Identifiable {
    let id: Int
    let start: Double
    let end: Double
    let text: String

    var formattedTimeRange: String {
        formatTime(start) + " - " + formatTime(end)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, millis)
    }
}
