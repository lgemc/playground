import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'config_service.dart';
import '../apps/file_system/services/file_system_storage.dart';
import '../apps/file_system/models/file_item.dart';

/// Service for generating images using Stable Diffusion API
class ImageGenerationService {
  static final ImageGenerationService instance = ImageGenerationService._();
  ImageGenerationService._();

  static const String _configKeyUrl = 'image_generation.api_url';

  /// Initialize default configuration
  static void initializeDefaults() {
    ConfigService.instance.setDefault(
      _configKeyUrl,
      'http://192.168.0.7:85',
    );
  }

  /// Get the configured API URL
  String get apiUrl => ConfigService.instance.get(_configKeyUrl) ?? '';

  /// Check if service is configured
  bool get isConfigured => apiUrl.isNotEmpty;

  /// Generate an image from a text prompt
  ///
  /// Returns the FileItem for the generated image stored in the file system
  Future<FileItem> generateImage({
    required String prompt,
    String? negativePrompt,
    int steps = 25,
    int width = 1024,
    int height = 1024,
    double cfgScale = 7.0,
    String samplerName = 'DPM++ 2M Karras',
    int seed = -1,
    String folderPath = 'generated/', // Store in generated/ folder by default
  }) async {
    if (!isConfigured) {
      throw Exception('Image generation API not configured');
    }

    // Generate filename from prompt
    final filename = _generateFilename(prompt);

    // Prepare request body
    final requestBody = {
      'prompt': prompt,
      'negative_prompt': negativePrompt ?? 'blurry, low quality, deformed',
      'steps': steps,
      'width': width,
      'height': height,
      'cfg_scale': cfgScale,
      'sampler_name': samplerName,
      'seed': seed,
    };

    try {
      // Make API request
      final response = await http.post(
        Uri.parse('$apiUrl/sdapi/v1/txt2img'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) {
        throw Exception('API request failed: ${response.statusCode} ${response.body}');
      }

      // Parse response
      final responseData = jsonDecode(response.body);
      final images = responseData['images'] as List<dynamic>?;

      if (images == null || images.isEmpty) {
        throw Exception('No images returned from API');
      }

      // Decode base64 image
      final base64Image = images[0] as String;
      final imageBytes = base64Decode(base64Image);

      // Save to temporary file first
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, filename));
      await tempFile.writeAsBytes(imageBytes);

      // Add to file system storage
      final fileItem = await FileSystemStorage.instance.addFile(
        tempFile,
        folderPath,
      );

      // Clean up temp file
      await tempFile.delete();

      return fileItem;
    } catch (e) {
      throw Exception('Failed to generate image: $e');
    }
  }

  /// Generate a filename from a prompt
  ///
  /// Takes the first 5 words, converts to lowercase, replaces spaces with underscores
  String _generateFilename(String prompt) {
    // Take first 50 chars, convert to lowercase
    final cleanPrompt = prompt.toLowerCase().trim();
    final words = cleanPrompt.split(RegExp(r'\s+'));

    // Take first 5 words
    final filenameWords = words.take(5).join('_');

    // Remove non-alphanumeric characters (except underscores)
    final cleanFilename = filenameWords.replaceAll(RegExp(r'[^a-z0-9_]'), '');

    // Add timestamp to ensure uniqueness
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    return '${cleanFilename}_$timestamp.png';
  }
}
