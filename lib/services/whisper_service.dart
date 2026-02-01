import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'config_service.dart';
import 'whisper_config.dart';

/// Service for interacting with the OpenAI-compatible Whisper transcription API.
///
/// Uses the /v1/audio/transcriptions endpoint for synchronous transcription.
/// Configuration is managed via ConfigService with keys from WhisperConfig.
class WhisperService {
  static WhisperService? _instance;
  static WhisperService get instance => _instance ??= WhisperService._();

  WhisperService._();

  final _config = ConfigService.instance;

  /// Initialize global config defaults.
  /// Call this in main.dart before using the service.
  static void initializeDefaults() {
    final config = ConfigService.instance;
    config.setDefault(WhisperConfig.baseUrl, WhisperConfig.defaultBaseUrl);
    config.setDefault(WhisperConfig.model, WhisperConfig.defaultModel);
    config.setDefault(WhisperConfig.language, WhisperConfig.defaultLanguage);
    config.setDefault(
        WhisperConfig.timeoutSeconds, WhisperConfig.defaultTimeoutSeconds);
  }

  String get _baseUrl =>
      _config.get(WhisperConfig.baseUrl) ?? WhisperConfig.defaultBaseUrl;

  /// Check if service is configured with a valid URL
  bool get isConfigured {
    final url = _config.get(WhisperConfig.baseUrl);
    return url != null && url.isNotEmpty;
  }

  /// Transcribe an audio/video file using the OpenAI-compatible API.
  ///
  /// Returns the transcribed text.
  /// Throws [FileSystemException] if the file doesn't exist.
  /// Throws [HttpException] if the API request fails.
  Future<String> transcribe(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    final model =
        _config.get(WhisperConfig.model) ?? WhisperConfig.defaultModel;
    final language =
        _config.get(WhisperConfig.language) ?? WhisperConfig.defaultLanguage;
    final timeoutSeconds = int.tryParse(
          _config.get(WhisperConfig.timeoutSeconds) ?? '',
        ) ??
        int.parse(WhisperConfig.defaultTimeoutSeconds);

    final uri = Uri.parse('$_baseUrl/v1/audio/transcriptions');

    final request = http.MultipartRequest('POST', uri)
      ..fields['model'] = model
      ..fields['language'] = language
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamedResponse = await request.send().timeout(
          Duration(seconds: timeoutSeconds),
          onTimeout: () => throw HttpException(
            'Transcription request timed out after $timeoutSeconds seconds',
          ),
        );

    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw HttpException(
        'Transcription failed: ${response.statusCode} - ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final text = data['text'] as String?;

    if (text == null || text.isEmpty) {
      throw StateError('Transcription completed but no text returned');
    }

    return text;
  }

  /// Alias for transcribe() to maintain API compatibility.
  ///
  /// The onProgress callback is ignored since the new API is synchronous.
  Future<String> transcribeWithPolling(
    String filePath, {
    void Function(int progress, String message)? onProgress,
  }) async {
    onProgress?.call(0, 'Submitting transcription request...');
    final result = await transcribe(filePath);
    onProgress?.call(100, 'Transcription completed');
    return result;
  }

  /// Translate audio to English using the OpenAI-compatible API.
  ///
  /// Returns the translated text.
  Future<String> translate(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    final model =
        _config.get(WhisperConfig.model) ?? WhisperConfig.defaultModel;
    final timeoutSeconds = int.tryParse(
          _config.get(WhisperConfig.timeoutSeconds) ?? '',
        ) ??
        int.parse(WhisperConfig.defaultTimeoutSeconds);

    final uri = Uri.parse('$_baseUrl/v1/audio/translations');

    final request = http.MultipartRequest('POST', uri)
      ..fields['model'] = model
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamedResponse = await request.send().timeout(
          Duration(seconds: timeoutSeconds),
          onTimeout: () => throw HttpException(
            'Translation request timed out after $timeoutSeconds seconds',
          ),
        );

    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw HttpException(
        'Translation failed: ${response.statusCode} - ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final text = data['text'] as String?;

    if (text == null || text.isEmpty) {
      throw StateError('Translation completed but no text returned');
    }

    return text;
  }

  /// Check if the Whisper service is healthy.
  Future<bool> healthCheck() async {
    try {
      final uri = Uri.parse('$_baseUrl/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Configure the service programmatically.
  Future<void> configure({
    String? baseUrl,
    String? model,
    String? language,
    int? timeoutSeconds,
  }) async {
    if (baseUrl != null) {
      await _config.set(WhisperConfig.baseUrl, baseUrl);
    }
    if (model != null) {
      await _config.set(WhisperConfig.model, model);
    }
    if (language != null) {
      await _config.set(WhisperConfig.language, language);
    }
    if (timeoutSeconds != null) {
      await _config.set(
          WhisperConfig.timeoutSeconds, timeoutSeconds.toString());
    }
  }

  /// Reset instance for testing
  static void resetInstance() {
    _instance = null;
  }
}
