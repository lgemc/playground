import 'package:flutter/material.dart';
import '../../shared/models/quiz.dart';
import '../../../../services/quiz_generation_service.dart';
import '../../../../services/quiz_service.dart';
import 'quiz_taking_screen.dart';
import 'quiz_results_screen.dart';

/// Screen showing all quizzes for a course
class QuizListScreen extends StatefulWidget {
  final String courseId;
  final String? moduleId;
  final String? subSectionId;
  final String? activityId;

  const QuizListScreen({
    Key? key,
    required this.courseId,
    this.moduleId,
    this.subSectionId,
    this.activityId,
  }) : super(key: key);

  @override
  State<QuizListScreen> createState() => _QuizListScreenState();
}

class _QuizListScreenState extends State<QuizListScreen> {
  final _quizGenService = QuizGenerationService.instance;
  final _quizService = QuizService.instance;
  List<Quiz> _quizzes = [];
  Map<String, Map<String, dynamic>> _statistics = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadQuizzes();
  }

  Future<void> _loadQuizzes() async {
    setState(() => _loading = true);

    try {
      final quizzes = await _quizGenService.getQuizzesForCourse(widget.courseId);

      // Filter by module/subsection/activity if provided
      final filtered = quizzes.where((quiz) {
        if (widget.activityId != null) {
          return quiz.activityId == widget.activityId;
        }
        if (widget.subSectionId != null) {
          return quiz.subSectionId == widget.subSectionId;
        }
        if (widget.moduleId != null) {
          return quiz.moduleId == widget.moduleId;
        }
        return true;
      }).toList();

      // Load statistics for each quiz
      final stats = <String, Map<String, dynamic>>{};
      for (final quiz in filtered) {
        stats[quiz.id] = await _quizService.getQuizStatistics(quiz.id);
      }

      setState(() {
        _quizzes = filtered;
        _statistics = stats;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading quizzes: $e')),
        );
      }
    }
  }

  Future<void> _deleteQuiz(Quiz quiz) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Quiz'),
        content: Text('Are you sure you want to delete "${quiz.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _quizGenService.deleteQuiz(quiz.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Quiz deleted')),
          );
        }
        _loadQuizzes();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting quiz: $e')),
          );
        }
      }
    }
  }

  void _startQuiz(Quiz quiz) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QuizTakingScreen(
          quizId: quiz.id,
          userId: 'default_user', // TODO: Use real user ID
        ),
      ),
    ).then((_) => _loadQuizzes()); // Refresh after quiz completion
  }

  void _viewResults(Quiz quiz) async {
    // Get latest attempt for this quiz
    final attempts = await _quizService.getAttemptsForQuiz(quiz.id);
    if (attempts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No attempts yet')),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => QuizResultsScreen(
            attemptId: attempts.first.id,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quizzes'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _quizzes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.quiz, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No quizzes yet',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Generate quizzes from extracted concepts',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _quizzes.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final quiz = _quizzes[index];
                    final stats = _statistics[quiz.id] ?? {};

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          backgroundColor: _getDifficultyColor(quiz.difficulty),
                          child: Icon(
                            Icons.quiz,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          quiz.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            if (quiz.description != null)
                              Text(
                                quiz.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              children: [
                                _buildChip(
                                  Icons.label,
                                  _formatDifficulty(quiz.difficulty),
                                  _getDifficultyColor(quiz.difficulty),
                                ),
                                _buildChip(
                                  Icons.numbers,
                                  '${quiz.questionCount} questions',
                                  Colors.blue,
                                ),
                                if (quiz.timeLimit != null)
                                  _buildChip(
                                    Icons.timer,
                                    '${quiz.timeLimit! ~/ 60} min',
                                    Colors.orange,
                                  ),
                                if (stats['totalAttempts'] != null && stats['totalAttempts'] > 0)
                                  _buildChip(
                                    Icons.assessment,
                                    '${stats['averageScore']?.toStringAsFixed(0) ?? 0}% avg',
                                    Colors.green,
                                  ),
                              ],
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton(
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'start',
                              child: Row(
                                children: [
                                  Icon(Icons.play_arrow),
                                  SizedBox(width: 8),
                                  Text('Start Quiz'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'results',
                              child: Row(
                                children: [
                                  Icon(Icons.analytics),
                                  SizedBox(width: 8),
                                  Text('View Results'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            switch (value) {
                              case 'start':
                                _startQuiz(quiz);
                                break;
                              case 'results':
                                _viewResults(quiz);
                                break;
                              case 'delete':
                                _deleteQuiz(quiz);
                                break;
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
      ],
    );
  }

  String _formatDifficulty(QuizDifficulty difficulty) {
    return difficulty.name.substring(0, 1).toUpperCase() +
        difficulty.name.substring(1);
  }

  Color _getDifficultyColor(QuizDifficulty difficulty) {
    switch (difficulty) {
      case QuizDifficulty.beginner:
        return Colors.green;
      case QuizDifficulty.intermediate:
        return Colors.blue;
      case QuizDifficulty.advanced:
        return Colors.orange;
      case QuizDifficulty.expert:
        return Colors.red;
    }
  }
}
