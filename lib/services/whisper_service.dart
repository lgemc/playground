import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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

  // Files larger than this are uploaded via S3 presigned URL to bypass
  // the Lambda 6 MB request payload limit.
  static const int _s3ThresholdBytes = 5 * 1024 * 1024; // 5 MB

  /// Transcribe an audio/video file using the /transcribe API.
  ///
  /// For files > 5 MB the upload is staged through S3 (tunnel upload-url flow)
  /// so the Lambda 6 MB request limit is not hit.
  ///
  /// Returns the full transcription response with segments and word-level data.
  /// Throws [FileSystemException] if the file doesn't exist.
  /// Throws [HttpException] if the API request fails.
  Future<Map<String, dynamic>> transcribeDetailed(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    final fileSize = await file.length();
    final timeoutSeconds = int.tryParse(
          _config.get(WhisperConfig.timeoutSeconds) ?? '',
        ) ??
        int.parse(WhisperConfig.defaultTimeoutSeconds);

    if (fileSize > _s3ThresholdBytes) {
      return _transcribeViaS3(filePath, timeoutSeconds: timeoutSeconds);
    }

    return _transcribeDirect(filePath, timeoutSeconds: timeoutSeconds);
  }

  /// Direct multipart POST — works for files under 5 MB / non-tunnel URLs.
  Future<Map<String, dynamic>> _transcribeDirect(
    String filePath, {
    required int timeoutSeconds,
  }) async {
    final language =
        _config.get(WhisperConfig.language) ?? WhisperConfig.defaultLanguage;

    final uri = Uri.parse('$_baseUrl/transcribe');

    final request = http.MultipartRequest('POST', uri)
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

    if (data['status'] != 'success' && data['success'] != true) {
      throw StateError('Transcription failed: ${data['status'] ?? data['error'] ?? data}');
    }

    return data;
  }

  /// S3-staged upload for files > 5 MB going through an AWS tunnel.
  ///
  /// Flow:
  ///  1. POST /upload-url/transcribe  → {upload_url, request_id, poll_url}
  ///  2. PUT file bytes to upload_url (S3 presigned)
  ///  3. Poll /poll/{request_id} until the tunnel forwards the request and
  ///     the local Whisper server responds.
  Future<Map<String, dynamic>> _transcribeViaS3(
    String filePath, {
    required int timeoutSeconds,
  }) async {
    final language =
        _config.get(WhisperConfig.language) ?? WhisperConfig.defaultLanguage;

    // ── Step 1: get presigned S3 upload URL ──────────────────────────────────
    // Build the upload-url endpoint from the tunnel root (scheme + host only),
    // because CloudFront routes /upload-url/* without path prefix rewriting.
    // _baseUrl may include a path prefix like /v1 which would break the route.
    final baseUri = Uri.parse(_baseUrl);
    final tunnelRoot = Uri(scheme: baseUri.scheme, host: baseUri.host, port: baseUri.hasPort ? baseUri.port : null);
    final uploadUrlEndpoint = tunnelRoot.resolve('/upload-url/transcribe');
    // Build boundary early so we can send the full Content-Type to the Lambda.
    // The Lambda stores it in DynamoDB; the CLI forwards it when POSTing to Whisper.
    final boundary = '----TunnelBoundary${DateTime.now().millisecondsSinceEpoch}';
    final contentType = 'multipart/form-data; boundary=$boundary';

    final initResponse = await http
        .post(
          uploadUrlEndpoint,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'method': 'POST',
            'content_type': contentType,
            'headers': {'Content-Type': contentType},
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (initResponse.statusCode != 200) {
      throw HttpException(
        'Failed to get upload URL: ${initResponse.statusCode} - ${initResponse.body}',
      );
    }

    final initData = jsonDecode(initResponse.body) as Map<String, dynamic>;
    final uploadUrl = initData['upload_url'] as String?;
    final requestId = initData['request_id'] as String?;

    if (uploadUrl == null || requestId == null) {
      throw StateError('Invalid upload-url response: $initData');
    }

    // ── Step 2: build multipart body and PUT directly to S3 ──────────────────
    // Construct the multipart body manually so it can be PUT to S3.
    // boundary and contentType were defined above for step 1.
    final fileBytes = await File(filePath).readAsBytes();
    final fileName = filePath.split(Platform.pathSeparator).last;

    final bodyParts = <int>[];
    void addString(String s) => bodyParts.addAll(s.codeUnits);

    addString('--$boundary\r\n');
    addString('Content-Disposition: form-data; name="language"\r\n\r\n');
    addString('$language\r\n');
    addString('--$boundary\r\n');
    addString(
        'Content-Disposition: form-data; name="file"; filename="$fileName"\r\n');
    addString('Content-Type: application/octet-stream\r\n\r\n');
    bodyParts.addAll(fileBytes);
    addString('\r\n--$boundary--\r\n');

    // Use dart:io HttpClient to set Content-Length explicitly.
    // S3 presigned PUTs reject chunked transfer encoding (broken pipe / 501),
    // so we must send Content-Length and stream the body in one shot.
    final bodyBytes = Uint8List.fromList(bodyParts);
    final ioClient = HttpClient();
    late int putStatusCode;
    late String putResponseBody;
    try {
      final req = await ioClient
          .putUrl(Uri.parse(uploadUrl))
          .timeout(Duration(seconds: timeoutSeconds));
      req.headers.set(HttpHeaders.contentLengthHeader, bodyBytes.length);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/octet-stream');
      req.add(bodyBytes);
      final res = await req.close().timeout(Duration(seconds: timeoutSeconds));
      putStatusCode = res.statusCode;
      putResponseBody = await res.transform(const Utf8Decoder()).join();
    } finally {
      ioClient.close();
    }

    if (putStatusCode < 200 || putStatusCode >= 300) {
      throw HttpException(
        'Failed to upload file to S3: $putStatusCode body=$putResponseBody',
      );
    }

    // ── Step 3: poll for the Whisper response ─────────────────────────────────
    final pollUrl = tunnelRoot.resolve('/poll/$requestId');
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));

      http.Response pollResponse;
      try {
        pollResponse = await http
            .get(pollUrl)
            .timeout(const Duration(seconds: 30));
      } catch (_) {
        // Transient network error (DNS failure, timeout, etc.) — keep polling.
        continue;
      }

      if (pollResponse.statusCode == 202) {
        // Still processing — keep polling
        continue;
      }

      if (pollResponse.statusCode == 200) {
        final data = jsonDecode(pollResponse.body) as Map<String, dynamic>;
        if (data['status'] != 'success' && data['success'] != true) {
          throw StateError('Transcription failed: ${data['status'] ?? data['error'] ?? data}');
        }
        return data;
      }

      throw HttpException(
        'Transcription poll failed: ${pollResponse.statusCode} - ${pollResponse.body}',
      );
    }

    throw HttpException(
      'Transcription timed out after $timeoutSeconds seconds',
    );
  }

  /// Transcribe an audio/video file and return only the text.
  ///
  /// Returns the transcribed text concatenated from all segments.
  /// Throws [FileSystemException] if the file doesn't exist.
  /// Throws [HttpException] if the API request fails.
  Future<String> transcribe(String filePath) async {
    final data = await transcribeDetailed(filePath);

    final segments = data['segments'] as List<dynamic>?;
    if (segments == null || segments.isEmpty) {
      throw StateError('Transcription completed but no segments returned');
    }

    // Concatenate all segment texts
    return segments
        .map((seg) => (seg as Map<String, dynamic>)['text'] as String?)
        .where((text) => text != null && text.isNotEmpty)
        .join(' ')
        .trim();
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
