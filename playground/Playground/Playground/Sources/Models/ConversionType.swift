import Foundation

/// Defines all supported AI conversion types
enum ConversionType: String, Codable, CaseIterable {
    case textToText = "text_to_text"
    case textToAudio = "text_to_audio"
    case audioToText = "audio_to_text"
    case videoToText = "video_to_text"
    case fileToText = "file_to_text"

    var displayName: String {
        switch self {
        case .textToText: return "Text → Text"
        case .textToAudio: return "Text → Audio"
        case .audioToText: return "Audio → Text"
        case .videoToText: return "Video → Text"
        case .fileToText: return "File → Text"
        }
    }

    var inputIcon: String {
        switch self {
        case .textToText, .textToAudio:
            return "textformat"
        case .audioToText:
            return "waveform"
        case .videoToText:
            return "video"
        case .fileToText:
            return "doc"
        }
    }

    var outputIcon: String {
        switch self {
        case .textToText, .audioToText, .videoToText, .fileToText:
            return "textformat"
        case .textToAudio:
            return "waveform"
        }
    }

    var requiresFile: Bool {
        switch self {
        case .audioToText, .videoToText, .fileToText:
            return true
        case .textToText, .textToAudio:
            return false
        }
    }
}
