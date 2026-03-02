import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'config_service.dart';
import '../apps/file_system/services/file_system_storage.dart';
import '../apps/file_system/models/file_item.dart';

/// Service for generating audio using TTS API (OpenedAI Speech compatible)
class AudioGenerationService {
  static final AudioGenerationService instance = AudioGenerationService._();
  AudioGenerationService._();

  static const String _configKeyUrl = 'audio_generation.api_url';
  static const String _configKeyVoice = 'audio_generation.voice';
  static const String _configKeyModel = 'audio_generation.model';

  /// Initialize default configuration
  static void initializeDefaults() {
    ConfigService.instance.setDefault(
      _configKeyUrl,
      'http://192.168.0.7:8000',
    );
    ConfigService.instance.setDefault(
      _configKeyVoice,
      'alloy',
    );
    ConfigService.instance.setDefault(
      _configKeyModel,
      'tts-1',
    );
  }

  /// Get the configured API URL
  String get apiUrl => ConfigService.instance.get(_configKeyUrl) ?? '';

  /// Get the configured voice
  String get voice => ConfigService.instance.get(_configKeyVoice) ?? 'alloy';

  /// Get the configured model
  String get model => ConfigService.instance.get(_configKeyModel) ?? 'tts-1';

  /// Check if service is configured
  bool get isConfigured => apiUrl.isNotEmpty;

  /// Generate audio from text
  ///
  /// Returns the FileItem for the generated audio stored in the file system
  Future<FileItem> generateAudio({
    required String text,
    required String filename,
    String? customVoice,
    String? customModel,
    String folderPath = 'generated/audio/', // Store in generated/audio/ folder by default
  }) async {
    if (!isConfigured) {
      throw Exception('Audio generation API not configured');
    }

    // Sanitize filename
    final sanitizedFilename = _sanitizeFilename(filename);

    // Prepare request body (OpenAI-compatible TTS API format)
    final requestBody = {
      'model': customModel ?? model,
      'input': text,
      'voice': customVoice ?? voice,
      'response_format': 'mp3',
    };

    try {
      // Make API request
      final response = await http.post(
        Uri.parse('$apiUrl/v1/audio/speech'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(minutes: 2));

      if (response.statusCode != 200) {
        throw Exception('API request failed: ${response.statusCode} ${response.body}');
      }

      // Response is raw audio bytes (MP3)
      final audioBytes = response.bodyBytes;

      if (audioBytes.isEmpty) {
        throw Exception('No audio data returned from API');
      }

      // Save to temporary file first
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, sanitizedFilename));
      await tempFile.writeAsBytes(audioBytes);

      // Add to file system storage
      final fileItem = await FileSystemStorage.instance.addFile(
        tempFile,
        folderPath,
      );

      // Clean up temp file
      await tempFile.delete();

      return fileItem;
    } catch (e) {
      throw Exception('Failed to generate audio: $e');
    }
  }

  /// Generate audio from text for a specific app
  ///
  /// Uses app-specific folder: generated/audio/{appId}/
  Future<FileItem> generateAudioForApp({
    required String text,
    required String filename,
    required String appId,
    String? customVoice,
    String? customModel,
  }) async {
    return generateAudio(
      text: text,
      filename: filename,
      customVoice: customVoice,
      customModel: customModel,
      folderPath: 'generated/audio/$appId/',
    );
  }

  /// Sanitize filename to ensure it's valid
  ///
  /// Removes invalid characters and ensures .mp3 extension
  String _sanitizeFilename(String filename) {
    // Remove extension if present
    var cleanName = filename.replaceAll(RegExp(r'\.(mp3|wav|ogg|m4a)$'), '');

    // Replace spaces with underscores
    cleanName = cleanName.replaceAll(' ', '_');

    // Remove non-alphanumeric characters (except underscores and hyphens)
    cleanName = cleanName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');

    // Limit length
    if (cleanName.length > 100) {
      cleanName = cleanName.substring(0, 100);
    }

    // Add timestamp to ensure uniqueness
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    return '${cleanName}_$timestamp.mp3';
  }
}
