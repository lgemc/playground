import 'package:flutter/material.dart';
import '../../shared/models/quiz.dart';
import '../../../../services/quiz_service.dart';

/// Screen showing quiz results after completion
class QuizResultsScreen extends StatefulWidget {
  final String attemptId;

  const QuizResultsScreen({
    Key? key,
    required this.attemptId,
  }) : super(key: key);

  @override
  State<QuizResultsScreen> createState() => _QuizResultsScreenState();
}

class _QuizResultsScreenState extends State<QuizResultsScreen> {
  final _quizService = QuizService.instance;

  QuizAttempt? _attempt;
  Quiz? _quiz;
  List<Map<String, dynamic>> _details = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    setState(() => _loading = true);

    try {
      final results = await _quizService.getAttemptDetails(widget.attemptId);

      setState(() {
        _attempt = results['attempt'];
        _quiz = results['quiz'];
        _details = results['details'];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading results: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  Color _getScoreColor(int score) {
    if (score >= 90) return Colors.green;
    if (score >= 70) return Colors.blue;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _attempt == null || _quiz == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final passed = _attempt!.passed;
    final scoreColor = _getScoreColor(_attempt!.score);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz Results'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Score card
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    passed ? Icons.check_circle : Icons.cancel,
                    size: 80,
                    color: passed ? Colors.green : Colors.red,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    passed ? 'Passed!' : 'Not Passed',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: passed ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_attempt!.score}%',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_attempt!.totalPoints} / ${_attempt!.maxPoints} points',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStat(
                        Icons.quiz,
                        'Questions',
                        '${_details.length}',
                      ),
                      _buildStat(
                        Icons.check_circle,
                        'Correct',
                        '${_details.where((d) => (d['answer'] as QuizAnswer).isCorrect).length}',
                      ),
                      _buildStat(
                        Icons.cancel,
                        'Incorrect',
                        '${_details.where((d) => !(d['answer'] as QuizAnswer).isCorrect).length}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Question review
          Text(
            'Question Review',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Review your answers below',
            style: TextStyle(color: Colors.grey[600]),
          ),

          const SizedBox(height: 16),

          // List of questions and answers
          if (_details.isEmpty)
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Question Details Not Available',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This quiz may have been regenerated after you took it. '
                      'The original questions are no longer available. '
                      'Your score is still valid!',
                      style: TextStyle(color: Colors.orange.shade900),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._details.asMap().entries.map((entry) {
            final index = entry.key;
            final detail = entry.value;
            final answer = detail['answer'] as QuizAnswer;
            final isCorrect = answer.isCorrect;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Question header
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: isCorrect ? Colors.green : Colors.red,
                          radius: 16,
                          child: Icon(
                            isCorrect ? Icons.check : Icons.close,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Question ${index + 1}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Chip(
                          label: Text('${detail['points']} pts'),
                          backgroundColor: isCorrect ? Colors.green[100] : Colors.red[100],
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Question content
                    Text(
                      detail['content'] as String,
                      style: const TextStyle(fontSize: 16),
                    ),

                    const SizedBox(height: 12),

                    // User answer
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isCorrect ? Colors.green[50] : Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCorrect ? Colors.green : Colors.red,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.person,
                                size: 16,
                                color: isCorrect ? Colors.green : Colors.red,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Your answer:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isCorrect ? Colors.green[900] : Colors.red[900],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            answer.userAnswer.isEmpty ? '(No answer)' : answer.userAnswer,
                            style: TextStyle(
                              color: isCorrect ? Colors.green[900] : Colors.red[900],
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (!isCorrect) ...[
                      const SizedBox(height: 8),
                      // Correct answer
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.blue,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.lightbulb,
                                  size: 16,
                                  color: Colors.blue[900],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Correct answer:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[900],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              detail['correctAnswer'] as String? ?? '(No answer provided)',
                              style: TextStyle(
                                color: Colors.blue[900],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: const Text('Done'),
        ),
      ),
    );
  }

  Widget _buildStat(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Colors.grey[700]),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
