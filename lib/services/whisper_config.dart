/// Configuration keys for the Whisper transcription service.
///
/// Uses OpenAI-compatible API endpoints (/v1/audio/transcriptions).
/// These keys are used with ConfigService for global configuration.
/// Users can set values via the Settings app or programmatically.
class WhisperConfig {
  /// Base URL of the Whisper API server
  static const String baseUrl = 'whisper.base_url';

  /// Model name for transcription
  static const String model = 'whisper.model';

  /// Language code for transcription (e.g., 'en', 'es', 'fr')
  static const String language = 'whisper.language';

  /// Request timeout in seconds
  static const String timeoutSeconds = 'whisper.timeout_seconds';

  // Default values
  static const String defaultBaseUrl = 'http://localhost:8001';
  static const String defaultModel = 'Systran/faster-whisper-large-v3';
  static const String defaultLanguage = 'en';
  static const String defaultTimeoutSeconds = '900'; // 15 minutes
}
