import Foundation

/// Defines all supported AI conversion types
enum ConversionType: String, Codable, CaseIterable {
    case textToText = "text_to_text"
    case textToImage = "text_to_image"
    case imageToText = "image_to_text"
    case textToAudio = "text_to_audio"
    case audioToText = "audio_to_text"
    case videoToText = "video_to_text"
    case fileToText = "file_to_text"

    var displayName: String {
        switch self {
        case .textToText: return "Text → Text"
        case .textToImage: return "Text → Image"
        case .imageToText: return "Image → Text"
        case .textToAudio: return "Text → Audio"
        case .audioToText: return "Audio → Text"
        case .videoToText: return "Video → Text"
        case .fileToText: return "File → Text"
        }
    }

    var inputIcon: String {
        switch self {
        case .textToText, .textToImage, .textToAudio:
            return "textformat"
        case .imageToText:
            return "photo"
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
        case .textToText, .imageToText, .audioToText, .videoToText, .fileToText:
            return "textformat"
        case .textToImage:
            return "photo"
        case .textToAudio:
            return "waveform"
        }
    }

    var requiresFile: Bool {
        switch self {
        case .imageToText, .audioToText, .videoToText, .fileToText:
            return true
        case .textToText, .textToImage, .textToAudio:
            return false
        }
    }
}
