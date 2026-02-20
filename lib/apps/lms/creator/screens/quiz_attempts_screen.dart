import 'package:flutter/material.dart';
import '../../shared/models/quiz.dart';
import '../../../../services/quiz_service.dart';
import 'quiz_results_screen.dart';

/// Screen showing all attempts for a specific quiz
class QuizAttemptsScreen extends StatefulWidget {
  final Quiz quiz;

  const QuizAttemptsScreen({super.key, required this.quiz});

  @override
  State<QuizAttemptsScreen> createState() => _QuizAttemptsScreenState();
}

class _QuizAttemptsScreenState extends State<QuizAttemptsScreen> {
  final _quizService = QuizService.instance;
  List<QuizAttempt> _attempts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAttempts();
  }

  Future<void> _loadAttempts() async {
    setState(() => _loading = true);

    try {
      final attempts = await _quizService.getAttemptsForQuiz(widget.quiz.id);
      setState(() {
        _attempts = attempts;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading attempts: $e')),
        );
      }
    }
  }

  void _viewAttempt(QuizAttempt attempt) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuizResultsScreen(attemptId: attempt.id),
      ),
    );
  }

  Future<void> _deleteAttempt(QuizAttempt attempt, int attemptNumber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Attempt'),
        content: Text('Are you sure you want to delete attempt #$attemptNumber?'),
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
        await _quizService.deleteAttempt(attempt.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Attempt deleted')),
          );
        }
        _loadAttempts(); // Refresh the list
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting attempt: $e')),
          );
        }
      }
    }
  }

  Color _getScoreColor(int score) {
    if (score >= 90) return Colors.green;
    if (score >= 70) return Colors.blue;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  String _getScoreLabel(int score, bool passed) {
    if (passed) return 'Passed';
    return 'Failed';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Attempts - ${widget.quiz.title}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _attempts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.quiz, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No attempts yet',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text('Take the quiz to see your attempts here'),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _attempts.length,
                  itemBuilder: (context, index) {
                    final attempt = _attempts[index];
                    final scoreColor = _getScoreColor(attempt.score);
                    final isCompleted = attempt.completedAt != null;
                    final attemptNumber = _attempts.length - index;

                    return Dismissible(
                      key: Key(attempt.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.red,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (direction) async {
                        return await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Attempt'),
                            content: Text('Are you sure you want to delete attempt #$attemptNumber?'),
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
                      },
                      onDismissed: (direction) async {
                        try {
                          await _quizService.deleteAttempt(attempt.id);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Attempt deleted')),
                            );
                          }
                          _loadAttempts();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                          _loadAttempts();
                        }
                      },
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isCompleted ? scoreColor : Colors.grey,
                          child: Text(
                            '#$attemptNumber',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              isCompleted
                                  ? '${attempt.score}%'
                                  : 'In Progress',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isCompleted ? scoreColor : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isCompleted)
                              Chip(
                                label: Text(
                                  _getScoreLabel(attempt.score, attempt.passed),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                backgroundColor: attempt.passed
                                    ? Colors.green.shade100
                                    : Colors.red.shade100,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              'Started: ${_formatDate(attempt.startedAt)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (isCompleted)
                              Text(
                                'Completed: ${_formatDate(attempt.completedAt!)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              'Points: ${attempt.totalPoints}/${attempt.maxPoints}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: isCompleted
                            ? const Icon(Icons.chevron_right)
                            : const Icon(Icons.pending, color: Colors.grey),
                        onTap: isCompleted ? () => _viewAttempt(attempt) : null,
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes == 0) {
          return 'Just now';
        }
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
