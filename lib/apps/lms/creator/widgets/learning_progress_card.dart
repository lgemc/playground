import 'package:flutter/material.dart';
import '../../shared/models/learning_stats.dart';
import '../../../../services/spaced_repetition_service.dart';
import '../screens/review_session_screen.dart';

class LearningProgressCard extends StatelessWidget {
  final String courseId;

  const LearningProgressCard({super.key, required this.courseId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LearningStats>(
      future: SpacedRepetitionService.instance.getStats(courseId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final stats = snapshot.data!;

        // Don't show the card if there are no items
        if (stats.totalItems == 0) {
          return const SizedBox.shrink();
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.analytics,
                        color: Theme.of(context).primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'Learning Progress',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Stats grid
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat(
                      context,
                      'Due Today',
                      stats.remainingToday.toString(),
                      Icons.today,
                      stats.remainingToday > 0 ? Colors.orange : Colors.green,
                    ),
                    _buildStat(
                      context,
                      'Learned',
                      stats.learnedItems.toString(),
                      Icons.check_circle,
                      Colors.green,
                    ),
                    _buildStat(
                      context,
                      'Retention',
                      '${(stats.overallRetention * 100).round()}%',
                      Icons.trending_up,
                      Colors.blue,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Streak
                if (stats.reviewStreak > 0)
                  Row(
                    children: [
                      const Icon(Icons.local_fire_department,
                          color: Colors.orange),
                      const SizedBox(width: 8),
                      Text('${stats.reviewStreak} day streak!'),
                    ],
                  ),

                if (stats.reviewStreak > 0) const SizedBox(height: 16),

                // Action button
                if (stats.remainingToday > 0)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ReviewSessionScreen(
                            courseId: courseId,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Review Session'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'All caught up! Come back later for more reviews.',
                            style: TextStyle(color: Colors.green.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStat(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
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
}
