import 'package:flutter/material.dart';
import '../../../../core/database/crdt_database.dart';
import '../../shared/models/reviewable_item.dart';
import '../../shared/models/quiz.dart';
import '../../../../services/quiz_generation_service.dart';
import 'quiz_list_screen.dart';

/// Screen for viewing and managing extracted concepts from an activity
/// Only accessible to course creators in the LMS Creator app
class ConceptManagerScreen extends StatefulWidget {
  final String activityId;
  final String activityName;
  final String courseId;

  const ConceptManagerScreen({
    super.key,
    required this.activityId,
    required this.activityName,
    required this.courseId,
  });

  @override
  State<ConceptManagerScreen> createState() => _ConceptManagerScreenState();
}

class _ConceptManagerScreenState extends State<ConceptManagerScreen> {
  final _quizGenService = QuizGenerationService.instance;
  List<ReviewableItem> _concepts = [];
  bool _isLoading = true;
  bool _isGenerating = false;
  ReviewableType _filterType = ReviewableType.flashcard;

  @override
  void initState() {
    super.initState();
    _loadConcepts();
  }

  Future<void> _loadConcepts() async {
    setState(() => _isLoading = true);

    try {
      final rows = await CrdtDatabase.instance.query(
        '''SELECT * FROM reviewable_items
           WHERE activity_id = ?
           ORDER BY created_at DESC''',
        [widget.activityId],
      );

      final concepts = rows.map((row) => ReviewableItem.fromDbRow(row)).toList();

      setState(() {
        _concepts = concepts;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading concepts: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteConcept(ReviewableItem concept) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Concept'),
        content: Text('Are you sure you want to delete this concept?\n\n${concept.content}'),
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
        await CrdtDatabase.instance.execute(
          'DELETE FROM reviewable_items WHERE id = ?',
          [concept.id],
        );
        _loadConcepts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Concept deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  Future<void> _generateQuiz() async {
    if (_concepts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No concepts available to generate quiz')),
      );
      return;
    }

    // Show quiz generation dialog
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _QuizGenerationDialog(),
    );

    if (result == null) return;

    setState(() => _isGenerating = true);

    try {
      final difficulty = result['difficulty'] as QuizDifficulty;
      final questionCount = result['questionCount'] as int;

      final quiz = await _quizGenService.generateQuiz(
        courseId: widget.courseId,
        reviewableItems: _concepts,
        difficulty: difficulty,
        questionCount: questionCount,
        activityId: widget.activityId,
      );

      setState(() => _isGenerating = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quiz "${quiz.title}" generated!')),
        );
      }
    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating quiz: $e')),
        );
      }
    }
  }

  void _viewQuizzes() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QuizListScreen(
          courseId: widget.courseId,
          activityId: widget.activityId,
        ),
      ),
    );
  }

  List<ReviewableItem> get _filteredConcepts {
    return _concepts.where((c) => c.type == _filterType).toList();
  }

  Map<ReviewableType, int> get _conceptCounts {
    final counts = <ReviewableType, int>{};
    for (final type in ReviewableType.values) {
      counts[type] = _concepts.where((c) => c.type == type).length;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Extracted Concepts'),
            Text(
              widget.activityName,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'View Quizzes',
            onPressed: _viewQuizzes,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle),
            tooltip: 'Generate Quiz',
            onPressed: _isGenerating ? null : _generateQuiz,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Stats card
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatColumn(
                          'Total',
                          _concepts.length.toString(),
                          Icons.lightbulb_outline,
                        ),
                        _buildStatColumn(
                          'Flashcards',
                          _conceptCounts[ReviewableType.flashcard].toString(),
                          Icons.card_membership,
                        ),
                        _buildStatColumn(
                          'Questions',
                          _conceptCounts[ReviewableType.multipleChoice].toString(),
                          Icons.quiz,
                        ),
                      ],
                    ),
                  ),
                ),

                // Type filter
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: ReviewableType.values.map((type) {
                      final count = _conceptCounts[type] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text('${_getTypeName(type)} ($count)'),
                          selected: _filterType == type,
                          onSelected: count > 0
                              ? (selected) {
                                  if (selected) {
                                    setState(() => _filterType = type);
                                  }
                                }
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 16),

                // Concepts list
                Expanded(
                  child: _filteredConcepts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lightbulb_outline,
                                  size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'No ${_getTypeName(_filterType).toLowerCase()} concepts yet',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              const Text('Extract concepts from activity content'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredConcepts.length,
                          itemBuilder: (context, index) {
                            final concept = _filteredConcepts[index];
                            return _buildConceptCard(concept);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Colors.deepPurple),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
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

  Widget _buildConceptCard(ReviewableItem concept) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(
                    _getTypeName(concept.type),
                    style: const TextStyle(fontSize: 11),
                  ),
                  backgroundColor: _getTypeColor(concept.type),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  color: Colors.red,
                  onPressed: () => _deleteConcept(concept),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              concept.content,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (concept.answer != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Answer:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade900,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(concept.answer!),
                  ],
                ),
              ),
            ],
            if (concept.distractors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Distractors:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              ...concept.distractors.map((d) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Text('• $d', style: TextStyle(color: Colors.grey[600])),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  String _getTypeName(ReviewableType type) {
    switch (type) {
      case ReviewableType.flashcard:
        return 'Flashcard';
      case ReviewableType.multipleChoice:
        return 'Multiple Choice';
      case ReviewableType.trueFalse:
        return 'True/False';
      case ReviewableType.shortAnswer:
        return 'Short Answer';
      case ReviewableType.fillInBlank:
        return 'Fill in Blank';
      case ReviewableType.procedure:
        return 'Procedure';
      case ReviewableType.summary:
        return 'Summary';
    }
  }

  Color _getTypeColor(ReviewableType type) {
    switch (type) {
      case ReviewableType.flashcard:
        return Colors.blue.shade100;
      case ReviewableType.multipleChoice:
        return Colors.purple.shade100;
      case ReviewableType.trueFalse:
        return Colors.green.shade100;
      case ReviewableType.shortAnswer:
        return Colors.orange.shade100;
      case ReviewableType.fillInBlank:
        return Colors.pink.shade100;
      case ReviewableType.procedure:
        return Colors.teal.shade100;
      case ReviewableType.summary:
        return Colors.amber.shade100;
    }
  }
}

/// Dialog for configuring quiz generation options
class _QuizGenerationDialog extends StatefulWidget {
  @override
  State<_QuizGenerationDialog> createState() => _QuizGenerationDialogState();
}

class _QuizGenerationDialogState extends State<_QuizGenerationDialog> {
  QuizDifficulty _difficulty = QuizDifficulty.intermediate;
  int _questionCount = 10;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generate Quiz'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select quiz difficulty and number of questions:'),
          const SizedBox(height: 16),

          // Difficulty selection
          const Text(
            'Difficulty:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<QuizDifficulty>(
            value: _difficulty,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: QuizDifficulty.values.map((difficulty) {
              return DropdownMenuItem(
                value: difficulty,
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 12,
                      color: _getDifficultyColor(difficulty),
                    ),
                    const SizedBox(width: 8),
                    Text(_formatDifficulty(difficulty)),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _difficulty = value);
              }
            },
          ),

          const SizedBox(height: 16),

          // Question count
          const Text(
            'Number of questions:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _questionCount.toDouble(),
                  min: 5,
                  max: 30,
                  divisions: 25,
                  label: _questionCount.toString(),
                  onChanged: (value) {
                    setState(() => _questionCount = value.round());
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(
                  _questionCount.toString(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, {
              'difficulty': _difficulty,
              'questionCount': _questionCount,
            });
          },
          child: const Text('Generate'),
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
