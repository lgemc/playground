import 'package:flutter/material.dart';
import '../../shared/models/reviewable_item.dart';
import '../../../../core/database/crdt_database.dart';

/// Screen showing all concepts (reviewable items) for an activity
class ConceptsListScreen extends StatefulWidget {
  final String activityId;
  final String? activityName;

  const ConceptsListScreen({
    Key? key,
    required this.activityId,
    this.activityName,
  }) : super(key: key);

  @override
  State<ConceptsListScreen> createState() => _ConceptsListScreenState();
}

class _ConceptsListScreenState extends State<ConceptsListScreen> {
  List<ReviewableItem> _concepts = [];
  bool _isLoading = true;
  String _filterType = 'all';
  final Map<String, int> _typeCounts = {};

  @override
  void initState() {
    super.initState();
    _loadConcepts();
  }

  Future<void> _loadConcepts() async {
    setState(() => _isLoading = true);

    try {
      final results = await CrdtDatabase.instance.query(
        'SELECT * FROM reviewable_items WHERE activity_id = ? ORDER BY created_at DESC',
        [widget.activityId],
      );

      final concepts = results.map((row) => ReviewableItem.fromDbRow(row)).toList();

      // Count by type
      final counts = <String, int>{};
      for (final concept in concepts) {
        counts[concept.type.name] = (counts[concept.type.name] ?? 0) + 1;
      }

      setState(() {
        _concepts = concepts;
        _typeCounts.clear();
        _typeCounts.addAll(counts);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading concepts: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading concepts: $e')),
        );
      }
    }
  }

  List<ReviewableItem> get _filteredConcepts {
    if (_filterType == 'all') return _concepts;
    return _concepts.where((c) => c.type.name == _filterType).toList();
  }

  Future<void> _deleteConcept(ReviewableItem concept) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Concept'),
        content: const Text('Are you sure you want to delete this concept?'),
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

    if (confirmed != true) return;

    try {
      await CrdtDatabase.instance.execute(
        'DELETE FROM reviewable_items WHERE id = ?',
        [concept.id],
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Concept deleted')),
        );
        _loadConcepts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting concept: $e')),
        );
      }
    }
  }

  IconData _getTypeIcon(ReviewableType type) {
    switch (type) {
      case ReviewableType.flashcard:
        return Icons.style;
      case ReviewableType.multipleChoice:
        return Icons.checklist;
      case ReviewableType.trueFalse:
        return Icons.check_circle_outline;
      case ReviewableType.fillInBlank:
        return Icons.text_fields;
      case ReviewableType.shortAnswer:
        return Icons.subject;
      case ReviewableType.procedure:
        return Icons.list_alt;
      case ReviewableType.summary:
        return Icons.summarize;
    }
  }

  Color _getTypeColor(ReviewableType type) {
    switch (type) {
      case ReviewableType.flashcard:
        return Colors.blue;
      case ReviewableType.multipleChoice:
        return Colors.green;
      case ReviewableType.trueFalse:
        return Colors.orange;
      case ReviewableType.fillInBlank:
        return Colors.purple;
      case ReviewableType.shortAnswer:
        return Colors.teal;
      case ReviewableType.procedure:
        return Colors.indigo;
      case ReviewableType.summary:
        return Colors.pink;
    }
  }

  String _getTypeLabel(ReviewableType type) {
    switch (type) {
      case ReviewableType.flashcard:
        return 'Flashcard';
      case ReviewableType.multipleChoice:
        return 'Multiple Choice';
      case ReviewableType.trueFalse:
        return 'True/False';
      case ReviewableType.fillInBlank:
        return 'Fill in Blank';
      case ReviewableType.shortAnswer:
        return 'Short Answer';
      case ReviewableType.procedure:
        return 'Procedure';
      case ReviewableType.summary:
        return 'Summary';
    }
  }

  Widget _buildConceptCard(ReviewableItem concept) {
    final color = _getTypeColor(concept.type);
    final icon = _getTypeIcon(concept.type);
    final label = _getTypeLabel(concept.type);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              border: Border(
                bottom: BorderSide(color: color.withValues(alpha: 0.3)),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.red[700],
                  onPressed: () => _deleteConcept(concept),
                ),
              ],
            ),
          ),

          // Content based on type
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildConceptContent(concept),
          ),
        ],
      ),
    );
  }

  Widget _buildConceptContent(ReviewableItem concept) {
    switch (concept.type) {
      case ReviewableType.flashcard:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Term:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              concept.content,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Text(
              'Definition:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              concept.answer ?? 'No answer provided',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        );

      case ReviewableType.multipleChoice:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Question:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              concept.content,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Text(
              'Correct Answer:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      concept.answer ?? 'No answer provided',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            if (concept.distractors.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Wrong Answers:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
              ...concept.distractors.map((distractor) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.close, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        distractor,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ],
        );

      case ReviewableType.trueFalse:
        final isTrue = concept.answer?.toLowerCase() == 'true';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Statement:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              concept.content,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  isTrue ? Icons.check_circle : Icons.cancel,
                  color: isTrue ? Colors.green : Colors.red,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  isTrue ? 'TRUE' : 'FALSE',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isTrue ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ],
        );

      case ReviewableType.fillInBlank:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sentence:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              concept.content,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Text(
              'Answer:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
              ),
              child: Text(
                concept.answer ?? 'No answer provided',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );

      case ReviewableType.shortAnswer:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Question:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              concept.content,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Text(
              'Expected Answer:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              concept.answer ?? 'No answer provided',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        );

      case ReviewableType.procedure:
      case ReviewableType.summary:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              concept.content,
              style: const TextStyle(fontSize: 16),
            ),
            if (concept.answer != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                concept.answer!,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.activityName ?? 'Concepts'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        actions: [
          if (_concepts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Chip(
                  label: Text(
                    '${_filteredConcepts.length} concepts',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  backgroundColor: Colors.purple[700],
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _concepts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.psychology_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No concepts yet',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text('Generate concepts from the activity'),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Filter chips
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: Text('All (${_concepts.length})'),
                              selected: _filterType == 'all',
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _filterType = 'all');
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            ...ReviewableType.values.where((type) => _typeCounts[type.name] != null).map(
                              (type) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    '${_getTypeLabel(type)} (${_typeCounts[type.name]})',
                                  ),
                                  selected: _filterType == type.name,
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() => _filterType = type.name);
                                    }
                                  },
                                  avatar: Icon(
                                    _getTypeIcon(type),
                                    size: 18,
                                    color: _filterType == type.name
                                        ? Colors.white
                                        : _getTypeColor(type),
                                  ),
                                  selectedColor: _getTypeColor(type),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Concepts list
                    Expanded(
                      child: _filteredConcepts.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.filter_alt_off, size: 64, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No concepts in this category',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredConcepts.length,
                              itemBuilder: (context, index) {
                                return _buildConceptCard(_filteredConcepts[index]);
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
