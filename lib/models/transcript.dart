import 'dart:convert';

/// Represents a complete transcript with segments and metadata.
class Transcript {
  final String status;
  final String language;
  final List<TranscriptSegment> segments;
  final String? sourceFile;
  final DateTime? generatedAt;

  Transcript({
    required this.status,
    required this.language,
    required this.segments,
    this.sourceFile,
    this.generatedAt,
  });

  factory Transcript.fromJson(Map<String, dynamic> json) {
    try {
      return Transcript(
        status: json['status'] as String? ?? 'unknown',
        language: json['language'] as String? ?? 'en',
        segments: (json['segments'] as List<dynamic>?)
                ?.map((s) => TranscriptSegment.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        sourceFile: json['source_file'] as String?,
        generatedAt: json['generated_at'] != null
            ? DateTime.tryParse(json['generated_at'] as String)
            : null,
      );
    } catch (e) {
      throw FormatException('Failed to parse transcript JSON: $e\nJSON: $json');
    }
  }

  factory Transcript.fromJsonString(String jsonString) {
    return Transcript.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'language': language,
      'segments': segments.map((s) => s.toJson()).toList(),
      if (sourceFile != null) 'source_file': sourceFile,
      if (generatedAt != null) 'generated_at': generatedAt!.toIso8601String(),
    };
  }

  String toJsonString() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }

  /// Get full transcript text by concatenating all segments.
  String get fullText {
    return segments.map((s) => s.text).join(' ').trim();
  }

  /// Get total duration in seconds.
  double get duration {
    if (segments.isEmpty) return 0.0;
    return segments.last.end;
  }

  /// Find segment at a specific timestamp.
  TranscriptSegment? segmentAt(double timestamp) {
    for (final segment in segments) {
      if (timestamp >= segment.start && timestamp <= segment.end) {
        return segment;
      }
    }
    return null;
  }

  /// Get all unique speakers.
  Set<String> get speakers {
    return segments.map((s) => s.speaker).toSet();
  }
}

/// Represents a segment of transcribed text with timing information.
class TranscriptSegment {
  final double start;
  final double end;
  final String text;
  final List<TranscriptWord> words;
  final String speaker;

  TranscriptSegment({
    required this.start,
    required this.end,
    required this.text,
    required this.words,
    required this.speaker,
  });

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
      text: json['text'] as String? ?? '',
      words: (json['words'] as List<dynamic>?)
              ?.map((w) => TranscriptWord.fromJson(w as Map<String, dynamic>))
              .toList() ??
          [],
      speaker: json['speaker'] as String? ?? 'UNKNOWN',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start': start,
      'end': end,
      'text': text,
      'words': words.map((w) => w.toJson()).toList(),
      'speaker': speaker,
    };
  }

  /// Get duration of this segment in seconds.
  double get duration => end - start;

  /// Format timestamp as HH:MM:SS or MM:SS.
  String formatTimestamp(double timestamp) {
    final hours = timestamp ~/ 3600;
    final minutes = (timestamp % 3600) ~/ 60;
    final seconds = (timestamp % 60).toInt();
    final milliseconds = ((timestamp % 1) * 1000).toInt();

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}.'
          '${milliseconds.toString().padLeft(3, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${milliseconds.toString().padLeft(3, '0')}';
  }

  String get startFormatted => formatTimestamp(start);
  String get endFormatted => formatTimestamp(end);
}

/// Represents a single word with timing and confidence information.
class TranscriptWord {
  final String word;
  final double start;
  final double end;
  final double score;
  final String speaker;

  TranscriptWord({
    required this.word,
    required this.start,
    required this.end,
    required this.score,
    required this.speaker,
  });

  factory TranscriptWord.fromJson(Map<String, dynamic> json) {
    return TranscriptWord(
      word: json['word'] as String? ?? '',
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      speaker: json['speaker'] as String? ?? 'UNKNOWN',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'start': start,
      'end': end,
      'score': score,
      'speaker': speaker,
    };
  }

  /// Get duration of this word in seconds.
  double get duration => end - start;

  /// Get confidence percentage (0-100).
  double get confidencePercent => score * 100;
}
