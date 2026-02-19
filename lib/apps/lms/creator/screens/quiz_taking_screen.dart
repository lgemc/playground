import 'package:flutter/material.dart';
import 'dart:async';
import '../../shared/models/quiz.dart';
import '../../shared/models/reviewable_item.dart';
import '../../../../services/quiz_generation_service.dart';
import '../../../../services/quiz_service.dart';
import 'quiz_results_screen.dart';
import '../widgets/question_widget.dart';

/// Screen for taking a quiz
class QuizTakingScreen extends StatefulWidget {
  final String quizId;
  final String userId;

  const QuizTakingScreen({
    Key? key,
    required this.quizId,
    required this.userId,
  }) : super(key: key);

  @override
  State<QuizTakingScreen> createState() => _QuizTakingScreenState();
}

class _QuizTakingScreenState extends State<QuizTakingScreen> {
  final _quizGenService = QuizGenerationService.instance;
  final _quizService = QuizService.instance;

  Quiz? _quiz;
  QuizAttempt? _attempt;
  List<Map<String, dynamic>> _questions = [];
  int _currentQuestionIndex = 0;
  Map<int, String> _userAnswers = {};
  bool _loading = true;
  Timer? _timer;
  int _secondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    _initQuiz();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initQuiz() async {
    setState(() => _loading = true);

    try {
      // Load quiz
      final quiz = await _quizGenService.getQuiz(widget.quizId);
      if (quiz == null) {
        throw Exception('Quiz not found');
      }

      // Load questions with reviewable items
      final questions = await _quizGenService.getQuizQuestionsWithItems(widget.quizId);

      // Shuffle if needed
      if (quiz.shuffleQuestions) {
        questions.shuffle();
      }

      // Start attempt
      final attempt = await _quizService.startAttempt(
        quizId: widget.quizId,
        userId: widget.userId,
      );

      setState(() {
        _quiz = quiz;
        _questions = questions;
        _attempt = attempt;
        _loading = false;

        // Start timer if there's a time limit
        if (quiz.timeLimit != null) {
          _secondsRemaining = quiz.timeLimit!;
          _startTimer();
        }
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading quiz: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          _timer?.cancel();
          _submitQuiz();
        }
      });
    });
  }

  void _nextQuestion() {
    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
      });
    }
  }

  void _previousQuestion() {
    if (_currentQuestionIndex > 0) {
      setState(() {
        _currentQuestionIndex--;
      });
    }
  }

  void _onAnswerChanged(String answer) {
    setState(() {
      _userAnswers[_currentQuestionIndex] = answer;
    });
  }

  Future<void> _submitQuiz() async {
    _timer?.cancel();

    // Check if all questions are answered
    final unanswered = [];
    for (int i = 0; i < _questions.length; i++) {
      if (!_userAnswers.containsKey(i) || _userAnswers[i]!.trim().isEmpty) {
        unanswered.add(i + 1);
      }
    }

    if (unanswered.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Incomplete Quiz'),
          content: Text(
            'You have ${unanswered.length} unanswered question(s). '
            'Submit anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    try {
      // Submit all answers
      for (int i = 0; i < _questions.length; i++) {
        final question = _questions[i];
        final quizQuestion = question['quizQuestion'] as QuizQuestion;
        final reviewableItem = question['reviewableItem'] as ReviewableItem;
        final userAnswer = _userAnswers[i] ?? '';

        await _quizService.submitAnswer(
          attemptId: _attempt!.id,
          quizQuestionId: quizQuestion.id,
          userAnswer: userAnswer,
          reviewableItem: reviewableItem,
          questionPoints: quizQuestion.points,
        );
      }

      // Complete the attempt
      final completedAttempt = await _quizService.completeAttempt(_attempt!.id);

      if (mounted) {
        // Navigate to results screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => QuizResultsScreen(
              attemptId: completedAttempt.id,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting quiz: $e')),
        );
      }
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _quiz == null || _questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quiz')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final currentQuestion = _questions[_currentQuestionIndex];
    final quizQuestion = currentQuestion['quizQuestion'] as QuizQuestion;
    final reviewableItem = currentQuestion['reviewableItem'] as ReviewableItem;
    final currentAnswer = _userAnswers[_currentQuestionIndex];

    return WillPopScope(
      onWillPop: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exit Quiz'),
            content: const Text('Your progress will be lost. Are you sure?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
        return confirmed ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_quiz!.title),
          actions: [
            if (_quiz!.timeLimit != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.timer,
                        size: 20,
                        color: _secondsRemaining < 60 ? Colors.red : null,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatTime(_secondsRemaining),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _secondsRemaining < 60 ? Colors.red : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            // Progress indicator
            LinearProgressIndicator(
              value: (_currentQuestionIndex + 1) / _questions.length,
              backgroundColor: Colors.grey[200],
            ),

            // Question info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Question ${_currentQuestionIndex + 1} of ${_questions.length}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Chip(
                    label: Text('${quizQuestion.points} pts'),
                    backgroundColor: Colors.blue[100],
                  ),
                ],
              ),
            ),

            // Question widget
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: QuestionWidget(
                  reviewableItem: reviewableItem,
                  userAnswer: currentAnswer,
                  onAnswerChanged: _onAnswerChanged,
                  shuffleAnswers: _quiz!.shuffleAnswers,
                ),
              ),
            ),

            // Navigation buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_currentQuestionIndex > 0)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _previousQuestion,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Previous'),
                      ),
                    ),
                  if (_currentQuestionIndex > 0) const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: _currentQuestionIndex < _questions.length - 1
                        ? ElevatedButton.icon(
                            onPressed: _nextQuestion,
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Next'),
                          )
                        : ElevatedButton.icon(
                            onPressed: _submitQuiz,
                            icon: const Icon(Icons.check),
                            label: const Text('Submit Quiz'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
