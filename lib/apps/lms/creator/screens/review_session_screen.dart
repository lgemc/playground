import 'package:flutter/material.dart';
import '../../shared/models/reviewable_item.dart';
import '../../shared/models/review_schedule.dart';
import '../../../../services/spaced_repetition_service.dart';

class ReviewSessionScreen extends StatefulWidget {
  final String courseId;
  final int maxItems;

  const ReviewSessionScreen({
    super.key,
    required this.courseId,
    this.maxItems = 20,
  });

  @override
  State<ReviewSessionScreen> createState() => _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends State<ReviewSessionScreen> {
  List<ReviewableItemWithSchedule> _items = [];
  int _currentIndex = 0;
  bool _showingAnswer = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    final items = await SpacedRepetitionService.instance.getDueReviews(
      courseId: widget.courseId,
      maxItems: widget.maxItems,
    );
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  void _showAnswer() {
    setState(() {
      _showingAnswer = true;
    });
  }

  Future<void> _submitQuality(ReviewQuality quality) async {
    final current = _items[_currentIndex];

    // Update schedule
    await SpacedRepetitionService.instance.updateAfterReview(
      current.schedule,
      quality,
    );

    // Move to next or finish
    if (_currentIndex < _items.length - 1) {
      setState(() {
        _currentIndex++;
        _showingAnswer = false;
      });
    } else {
      // Session complete
      if (mounted) {
        _showCompletionDialog();
      }
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session Complete!'),
        content: Text('You reviewed ${_items.length} items.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Exit review session
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review Session')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, size: 64, color: Colors.green.shade400),
              const SizedBox(height: 16),
              Text(
                'No reviews due!',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text('Come back later for more practice.'),
            ],
          ),
        ),
      );
    }

    final current = _items[_currentIndex];
    final progress = (_currentIndex + 1) / _items.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Session'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text('${_currentIndex + 1}/${_items.length}'),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: progress),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Type badge
            Chip(
              label: Text(current.item.type.name),
              backgroundColor: _getTypeColor(current.item.type),
            ),
            const SizedBox(height: 24),

            // Question
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  current.item.content,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Answer section
            if (_showingAnswer) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Answer:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        current.item.answer ?? '',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Quality rating
              Text(
                'Rate your recall:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildQualityButton(
                      'Blackout', ReviewQuality.blackout, Colors.red),
                  _buildQualityButton(
                      'Hard', ReviewQuality.hard, Colors.orange),
                  _buildQualityButton(
                      'Good', ReviewQuality.good, Colors.blue),
                  _buildQualityButton(
                      'Easy', ReviewQuality.easy, Colors.green),
                ],
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: _showAnswer,
                icon: const Icon(Icons.visibility),
                label: const Text('Show Answer'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ],

            const Spacer(),

            // Stats
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatColumn(
                      'Repetitions',
                      current.schedule.repetitions.toString(),
                    ),
                    _buildStatColumn(
                      'Interval',
                      '${current.schedule.intervalDays}d',
                    ),
                    _buildStatColumn(
                      'Retention',
                      '${(current.schedule.retentionRate * 100).round()}%',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityButton(String label, ReviewQuality quality, Color color) {
    return ElevatedButton(
      onPressed: () => _submitQuality(quality),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      child: Text(label),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Color _getTypeColor(ReviewableType type) {
    switch (type) {
      case ReviewableType.flashcard:
        return Colors.blue.shade100;
      case ReviewableType.multipleChoice:
        return Colors.purple.shade100;
      case ReviewableType.trueFalse:
        return Colors.green.shade100;
      default:
        return Colors.grey.shade100;
    }
  }
}
