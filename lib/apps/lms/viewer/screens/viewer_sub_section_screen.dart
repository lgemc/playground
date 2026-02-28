import 'dart:io';
import 'package:flutter/material.dart';
import '../../shared/lms.dart';
import '../../../file_system/screens/pdf_reader_screen.dart';
import '../../../video_viewer/screens/video_player_screen.dart';
import '../../../file_system/screens/file_derivatives_screen.dart';
import '../../creator/screens/quiz_list_screen.dart';
import 'concepts_list_screen.dart';
import '../../shared/models/reviewable_item.dart';
import '../../shared/models/quiz.dart';
import '../../../../core/database/crdt_database.dart';
import '../../../../services/concept_extraction_service.dart';
import '../../../../services/quiz_generation_service.dart';

class ViewerSubSectionScreen extends StatefulWidget {
  final String courseId;
  final String moduleId;
  final String subSectionId;

  const ViewerSubSectionScreen({
    super.key,
    required this.courseId,
    required this.moduleId,
    required this.subSectionId,
  });

  @override
  State<ViewerSubSectionScreen> createState() => _ViewerSubSectionScreenState();
}

class _ViewerSubSectionScreenState extends State<ViewerSubSectionScreen> {
  final _storage = LmsCrdtStorageService.instance;
  final _conceptService = ConceptExtractionService.instance;
  final _quizService = QuizGenerationService.instance;
  LessonSubSection? _subSection;
  bool _isLoading = true;
  final Map<String, bool> _activitiesWithDerivatives = {};
  final Map<String, int> _conceptsCounts = {};
  final Map<String, int> _quizzesCounts = {};

  @override
  void initState() {
    super.initState();
    _loadSubSection();
  }

  Future<void> _loadSubSection() async {
    setState(() => _isLoading = true);
    final course = await _storage.getCourse(widget.courseId);
    final module = course?.modules.firstWhere((m) => m.id == widget.moduleId);
    final subSection = module?.subSections.firstWhere(
      (s) => s.id == widget.subSectionId,
    );

    // Check for derivatives, concepts, and quizzes
    if (subSection != null) {
      for (final activity in subSection.activities) {
        if (activity is ResourceFileActivity && activity.fileId != null) {
          final hasDerivatives = await FileSystemBridge.instance.hasDerivatives(activity.fileId!);
          _activitiesWithDerivatives[activity.id] = hasDerivatives;
        }

        // Count concepts for this activity
        final conceptsCount = await _getConceptsCount(activity.id);
        _conceptsCounts[activity.id] = conceptsCount;

        // Count quizzes for this activity
        final quizzesCount = await _getQuizzesCount(activity.id);
        _quizzesCounts[activity.id] = quizzesCount;
      }
    }

    setState(() {
      _subSection = subSection;
      _isLoading = false;
    });
  }

  Future<int> _getConceptsCount(String activityId) async {
    try {
      final results = await CrdtDatabase.instance.query(
        'SELECT COUNT(*) as count FROM reviewable_items WHERE activity_id = ?',
        [activityId],
      );
      return results.isNotEmpty ? (results.first['count'] as int) : 0;
    } catch (e) {
      print('Error getting concepts count: $e');
      return 0;
    }
  }

  Future<int> _getQuizzesCount(String activityId) async {
    try {
      final results = await CrdtDatabase.instance.query(
        'SELECT COUNT(*) as count FROM quizzes WHERE activity_id = ? AND deleted_at IS NULL',
        [activityId],
      );
      return results.isNotEmpty ? (results.first['count'] as int) : 0;
    } catch (e) {
      print('Error getting quizzes count: $e');
      return 0;
    }
  }

  Future<void> _viewDerivatives(Activity activity) async {
    if (activity is ResourceFileActivity && activity.fileId != null) {
      final fileItem = await FileSystemBridge.instance.getFileItemById(activity.fileId!);
      if (fileItem != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FileDerivativesScreen(file: fileItem),
          ),
        );
      }
    }
  }

  Future<void> _viewConcepts(Activity activity) async {
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ConceptsListScreen(
            activityId: activity.id,
            activityName: activity.name,
          ),
        ),
      ).then((_) {
        // Refresh counts after returning
        _loadSubSection();
      });
    }
  }

  Future<void> _generateConcepts(Activity activity) async {
    if (activity is! ResourceFileActivity || activity.fileId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No file attached to generate concepts from')),
        );
      }
      return;
    }

    // Check if file has derivatives (transcript or summary)
    final hasDerivatives = _activitiesWithDerivatives[activity.id] ?? false;
    if (!hasDerivatives) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Generate transcript first from derivatives')),
        );
      }
      return;
    }

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Generating concepts...'),
          ],
        ),
      ),
    );

    try {
      // Get transcript from derivatives
      final fileItem = await FileSystemBridge.instance.getFileItemById(activity.fileId!);
      if (fileItem == null) throw Exception('File not found');

      // Get transcript text
      final transcriptResults = await CrdtDatabase.instance.query(
        'SELECT content FROM file_derivatives WHERE file_id = ? AND type = ?',
        [activity.fileId, 'transcript'],
      );

      if (transcriptResults.isEmpty) {
        throw Exception('No transcript found. Generate transcript from derivatives first.');
      }

      final transcript = transcriptResults.first['content'] as String;

      // Generate concepts
      final concepts = await _conceptService.extractFromTranscript(
        activityId: activity.id,
        courseId: widget.courseId,
        moduleId: widget.moduleId,
        subSectionId: widget.subSectionId,
        transcript: transcript,
      );

      // Save concepts to database
      for (final concept in concepts) {
        final row = concept.toDbRow();
        await CrdtDatabase.instance.execute('''
          INSERT INTO reviewable_items (id, activity_id, course_id, module_id, subsection_id,
                                       type, content, answer, distractors, metadata,
                                       created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', [
          row['id'], row['activity_id'], row['course_id'], row['module_id'],
          row['subsection_id'], row['type'], row['content'], row['answer'],
          row['distractors'], row['metadata'], row['created_at'], row['updated_at']
        ]);
      }

      // Update count
      _conceptsCounts[activity.id] = concepts.length;

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generated ${concepts.length} concepts')),
        );
        setState(() {}); // Refresh UI
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating concepts: $e')),
        );
      }
    }
  }

  Future<void> _viewQuizzes(Activity activity) async {
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => QuizListScreen(
            courseId: widget.courseId,
            moduleId: widget.moduleId,
            subSectionId: widget.subSectionId,
            activityId: activity.id,
          ),
        ),
      ).then((_) {
        // Refresh counts after returning
        _loadSubSection();
      });
    }
  }

  Future<void> _generateQuiz(Activity activity) async {
    // Check if concepts exist
    final conceptsCount = _conceptsCounts[activity.id] ?? 0;
    if (conceptsCount == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Generate concepts first before creating quizzes')),
        );
      }
      return;
    }

    // Show quiz generation dialog with difficulty selection
    if (!mounted) return;
    final difficulty = await showDialog<QuizDifficulty>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate Quiz'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$conceptsCount concepts available'),
            const SizedBox(height: 16),
            const Text('Select difficulty:'),
            ...QuizDifficulty.values.map((diff) => RadioListTile<QuizDifficulty>(
              title: Text(diff.name.toUpperCase()),
              value: diff,
              groupValue: QuizDifficulty.intermediate,
              onChanged: (value) => Navigator.pop(context, value),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (difficulty == null || !mounted) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Generating quiz...'),
          ],
        ),
      ),
    );

    try {
      // Get concepts for this activity
      final results = await CrdtDatabase.instance.query(
        'SELECT * FROM reviewable_items WHERE activity_id = ?',
        [activity.id],
      );

      final concepts = results.map((row) => ReviewableItem.fromDbRow(row)).toList();

      // Generate quiz
      final quiz = await _quizService.generateQuiz(
        courseId: widget.courseId,
        moduleId: widget.moduleId,
        subSectionId: widget.subSectionId,
        activityId: activity.id,
        reviewableItems: concepts,
        difficulty: difficulty,
        questionCount: 10,
      );

      // Update count
      _quizzesCounts[activity.id] = (_quizzesCounts[activity.id] ?? 0) + 1;

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generated quiz: ${quiz.title}')),
        );
        setState(() {}); // Refresh UI
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating quiz: $e')),
        );
      }
    }
  }

  Future<void> _openActivity(Activity activity) async {
    if (activity is ResourceFileActivity) {
      if (activity.fileId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No file attached to this activity')),
          );
        }
        return;
      }

      try {
        final filePath = await FileSystemBridge.instance.getFilePathById(activity.fileId!);
        if (filePath == null) {
          throw 'File not found';
        }

        final physicalFile = File(filePath);
        if (!physicalFile.existsSync()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('File not downloaded yet'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return;
        }

        // Get file extension
        final fileName = filePath.split('/').last;
        final ext = fileName.contains('.')
            ? fileName.split('.').last.toLowerCase()
            : '';

        if (!mounted) return;

        // Open based on file type
        if (ext == 'pdf') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PdfReaderScreen(
                filePath: filePath,
                fileName: fileName,
              ),
            ),
          );
        } else if (ext == 'mp4' || ext == 'mkv' || ext == 'avi' ||
                   ext == 'mov' || ext == 'webm' || ext == 'flv' ||
                   ext == 'm4v' || ext == '3gp') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoPlayerScreen(
                filePath: filePath,
                fileName: fileName,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot open .$ext files yet')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error opening file: $e')),
          );
        }
      }
    }
  }

  IconData _getActivityIcon(Activity activity) {
    if (activity is ResourceFileActivity) {
      switch (activity.resourceType) {
        case ResourceType.lecture:
          return Icons.description;
        case ResourceType.audio:
          return Icons.audiotrack;
        case ResourceType.video:
          return Icons.video_library;
        case ResourceType.document:
          return Icons.insert_drive_file;
        case ResourceType.other:
          return Icons.attachment;
      }
    }
    return Icons.assignment;
  }

  Color _getActivityColor(Activity activity) {
    if (activity is ResourceFileActivity) {
      switch (activity.resourceType) {
        case ResourceType.lecture:
          return Colors.blue;
        case ResourceType.audio:
          return Colors.purple;
        case ResourceType.video:
          return Colors.red;
        case ResourceType.document:
          return Colors.green;
        case ResourceType.other:
          return Colors.grey;
      }
    }
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_subSection == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Section not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_subSection!.name),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _subSection!.activities.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.attachment, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No activities yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('This section has no activities'),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _subSection!.activities.length,
              itemBuilder: (context, index) {
                final activity = _subSection!.activities[index];
                final icon = _getActivityIcon(activity);
                final color = _getActivityColor(activity);
                final hasDerivatives = _activitiesWithDerivatives[activity.id] ?? false;
                final conceptsCount = _conceptsCounts[activity.id] ?? 0;
                final quizzesCount = _quizzesCounts[activity.id] ?? 0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.2),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    title: Text(
                      activity.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (activity.description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            activity.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (activity is ResourceFileActivity) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.label,
                                    size: 14,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    activity.resourceType.name.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              if (hasDerivatives)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome,
                                      size: 14,
                                      color: Colors.amber[700],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'DERIVATIVES',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.amber[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              if (conceptsCount > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.psychology,
                                      size: 14,
                                      color: Colors.purple[700],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$conceptsCount CONCEPTS',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.purple[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              if (quizzesCount > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.quiz,
                                      size: 14,
                                      color: Colors.green[700],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$quizzesCount QUIZZES',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                        if (value == 'open') {
                          _openActivity(activity);
                        } else if (value == 'derivatives') {
                          _viewDerivatives(activity);
                        } else if (value == 'viewConcepts') {
                          _viewConcepts(activity);
                        } else if (value == 'generateConcepts') {
                          _generateConcepts(activity);
                        } else if (value == 'viewQuizzes') {
                          _viewQuizzes(activity);
                        } else if (value == 'generateQuiz') {
                          _generateQuiz(activity);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'open',
                          child: ListTile(
                            leading: Icon(Icons.play_arrow),
                            title: Text('Open File'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        if (hasDerivatives)
                          const PopupMenuItem(
                            value: 'derivatives',
                            child: ListTile(
                              leading: Icon(Icons.auto_awesome, color: Colors.amber),
                              title: Text('View Derivatives'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        const PopupMenuItem(
                          enabled: false,
                          child: Divider(),
                        ),
                        if (conceptsCount > 0)
                          const PopupMenuItem(
                            value: 'viewConcepts',
                            child: ListTile(
                              leading: Icon(Icons.psychology, color: Colors.purple),
                              title: Text('View Concepts'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        if (hasDerivatives)
                          const PopupMenuItem(
                            value: 'generateConcepts',
                            child: ListTile(
                              leading: Icon(Icons.psychology_outlined, color: Colors.purple),
                              title: Text('Generate Concepts'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        const PopupMenuItem(
                          enabled: false,
                          child: Divider(),
                        ),
                        if (quizzesCount > 0)
                          const PopupMenuItem(
                            value: 'viewQuizzes',
                            child: ListTile(
                              leading: Icon(Icons.quiz, color: Colors.green),
                              title: Text('View Quizzes'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        if (conceptsCount > 0)
                          const PopupMenuItem(
                            value: 'generateQuiz',
                            child: ListTile(
                              leading: Icon(Icons.quiz_outlined, color: Colors.green),
                              title: Text('Generate Quiz'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                      ],
                    ),
                    onTap: () => _openActivity(activity),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
