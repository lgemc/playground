import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../apps/file_system/models/file_item.dart';
import '../../apps/file_system/services/file_system_storage.dart';
import '../whisper_service.dart';
import 'derivative_generator.dart';

/// Generator that transcribes video and audio files using the Whisper API.
class TranscriptGenerator extends DerivativeGenerator {
  final _whisperService = WhisperService.instance;

  // Supported video/audio MIME types
  static const _supportedMimeTypes = {
    'video/mp4',
    'video/mpeg',
    'video/quicktime',
    'video/x-msvideo',
    'video/webm',
    'audio/mpeg',
    'audio/mp3',
    'audio/wav',
    'audio/ogg',
    'audio/flac',
    'audio/m4a',
    'audio/x-m4a',
    'audio/aac',
  };

  // Supported extensions (fallback when MIME type unavailable)
  static const _supportedExtensions = {
    'mp4',
    'mpeg',
    'mpg',
    'mov',
    'avi',
    'webm',
    'mp3',
    'wav',
    'ogg',
    'flac',
    'm4a',
    'aac',
  };

  @override
  String get type => 'transcript';

  @override
  String get displayName => 'Transcript';

  @override
  IconData get icon => Icons.subtitles;

  @override
  bool canProcess(FileItem file) {
    // Check MIME type first
    if (file.mimeType != null) {
      if (_supportedMimeTypes.contains(file.mimeType)) {
        return true;
      }
      // Also check partial MIME type matches
      for (final mimeType in _supportedMimeTypes) {
        if (file.mimeType!.contains(mimeType.split('/').last)) {
          return true;
        }
      }
    }

    // Fallback to extension check
    final ext = file.extension.toLowerCase();
    return _supportedExtensions.contains(ext);
  }

  @override
  Future<String> generate(FileItem file) async {
    if (!_whisperService.isConfigured) {
      throw StateError(
        'Whisper service not configured. Set whisper.base_url in settings.',
      );
    }

    // Get full file path
    final filePath = FileSystemStorage.instance.getAbsolutePath(file);
    print('[TranscriptGenerator] File path: $filePath');
    print('[TranscriptGenerator] File name: ${file.name}');
    print('[TranscriptGenerator] File relative path: ${file.relativePath}');

    // Check if file exists on disk (metadata may be synced but content not yet)
    final physicalFile = File(filePath);
    final exists = await physicalFile.exists();
    print('[TranscriptGenerator] File exists: $exists');

    if (!exists) {
      final errorMsg = 'File not downloaded yet. Content sync in progress. Path: $filePath';
      print('[TranscriptGenerator] ERROR: $errorMsg');
      throw FileSystemException(errorMsg, filePath);
    }

    // Transcribe and get detailed response
    print('[TranscriptGenerator] Starting transcription...');
    final transcriptData = await _whisperService.transcribeDetailed(filePath);

    // Add metadata
    transcriptData['source_file'] = file.name;
    transcriptData['generated_at'] = DateTime.now().toIso8601String();

    // Return as formatted JSON
    return _formatTranscriptJson(transcriptData);
  }

  String _formatTranscriptJson(Map<String, dynamic> data) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(data);
  }
}
