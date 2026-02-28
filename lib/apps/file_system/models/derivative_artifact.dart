class DerivativeArtifact {
  final String id;
  final String fileId; // Parent file ID
  final String type; // 'summary', 'transcript', 'translation', etc.
  final String derivativePath; // Path to .md file
  final String status; // 'pending', 'processing', 'completed', 'failed'
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? errorMessage;
  final String? contentHash; // SHA-256 hash for sync
  final DateTime? deletedAt; // Soft delete support

  DerivativeArtifact({
    required this.id,
    required this.fileId,
    required this.type,
    required this.derivativePath,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.errorMessage,
    this.contentHash,
    this.deletedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_id': fileId,
      'type': type,
      'derivative_path': derivativePath,
      'status': status,
      'created_at': createdAt.millisecondsSinceEpoch,
      'completed_at': completedAt?.millisecondsSinceEpoch,
      'error_message': errorMessage,
      'content_hash': contentHash,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
    };
  }

  factory DerivativeArtifact.fromJson(Map<String, dynamic> json) {
    return DerivativeArtifact(
      id: json['id'] as String,
      fileId: json['file_id'] as String,
      type: json['type'] as String,
      derivativePath: json['derivative_path'] as String,
      status: json['status'] as String,
      createdAt: _parseTimestamp(json['created_at']),
      completedAt: json['completed_at'] != null
          ? _parseTimestamp(json['completed_at'])
          : null,
      errorMessage: json['error_message'] as String?,
      contentHash: json['content_hash'] as String?,
      deletedAt: json['deleted_at'] != null
          ? _parseTimestamp(json['deleted_at'])
          : null,
    );
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is String) {
      return DateTime.parse(value);
    }
    throw ArgumentError('Invalid timestamp format: $value');
  }

  DerivativeArtifact copyWith({
    String? id,
    String? fileId,
    String? type,
    String? derivativePath,
    String? status,
    DateTime? createdAt,
    DateTime? completedAt,
    String? errorMessage,
    String? contentHash,
    DateTime? deletedAt,
  }) {
    return DerivativeArtifact(
      id: id ?? this.id,
      fileId: fileId ?? this.fileId,
      type: type ?? this.type,
      derivativePath: derivativePath ?? this.derivativePath,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      errorMessage: errorMessage ?? this.errorMessage,
      contentHash: contentHash ?? this.contentHash,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
