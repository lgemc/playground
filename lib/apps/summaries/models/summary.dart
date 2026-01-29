/// Status of a summary generation task
enum SummaryStatus {
  pending,
  processing,
  completed,
  failed,
}

/// Represents a summary of a file
class Summary {
  final String id;
  final String fileId; // Reference to file in file system
  final String fileName; // Cached file name for display
  final String filePath; // Cached file path
  final String summaryText; // Markdown content of the summary
  final SummaryStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? errorMessage;

  Summary({
    required this.id,
    required this.fileId,
    required this.fileName,
    required this.filePath,
    required this.summaryText,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.errorMessage,
  });

  factory Summary.fromMap(Map<String, dynamic> map) {
    return Summary(
      id: map['id'] as String,
      fileId: map['file_id'] as String,
      fileName: map['file_name'] as String,
      filePath: map['file_path'] as String,
      summaryText: map['summary_text'] as String,
      status: SummaryStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => SummaryStatus.pending,
      ),
      createdAt: DateTime.parse(map['created_at'] as String),
      completedAt: map['completed_at'] != null
          ? DateTime.parse(map['completed_at'] as String)
          : null,
      errorMessage: map['error_message'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_id': fileId,
      'file_name': fileName,
      'file_path': filePath,
      'summary_text': summaryText,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'error_message': errorMessage,
    };
  }

  Summary copyWith({
    String? id,
    String? fileId,
    String? fileName,
    String? filePath,
    String? summaryText,
    SummaryStatus? status,
    DateTime? createdAt,
    DateTime? completedAt,
    String? errorMessage,
  }) {
    return Summary(
      id: id ?? this.id,
      fileId: fileId ?? this.fileId,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      summaryText: summaryText ?? this.summaryText,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  bool get isPending => status == SummaryStatus.pending;
  bool get isProcessing => status == SummaryStatus.processing;
  bool get isCompleted => status == SummaryStatus.completed;
  bool get isFailed => status == SummaryStatus.failed;
}
