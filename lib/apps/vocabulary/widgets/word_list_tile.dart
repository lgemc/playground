import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/share_content.dart';
import '../../../widgets/share_button.dart';
import '../models/word.dart';
import '../services/vocabulary_streaming_service.dart';

class WordListTile extends StatefulWidget {
  final Word word;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const WordListTile({
    super.key,
    required this.word,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<WordListTile> createState() => _WordListTileState();
}

class _WordListTileState extends State<WordListTile> {
  StreamSubscription<DefinitionStreamUpdate>? _subscription;
  DefinitionStreamUpdate? _streamUpdate;

  @override
  void initState() {
    super.initState();
    _subscribeToStreaming();
  }

  @override
  void didUpdateWidget(WordListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word.id != widget.word.id) {
      _subscription?.cancel();
      _subscribeToStreaming();
    }
  }

  void _subscribeToStreaming() {
    final streaming = VocabularyStreamingService.instance;
    _streamUpdate = streaming.getState(widget.word.id);
    _subscription = streaming.streamFor(widget.word.id).listen((update) {
      if (mounted) {
        setState(() => _streamUpdate = update);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final wordDate = DateTime(date.year, date.month, date.day);

    if (wordDate == today) {
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }

    final yesterday = today.subtract(const Duration(days: 1));
    if (wordDate == yesterday) {
      return 'Yesterday';
    }

    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final displayWord = word.word.isEmpty ? 'Untitled' : word.word;

    // Check streaming state
    final isGenerating = _streamUpdate?.state == DefinitionStreamState.generating;
    final streamedMeaning = _streamUpdate?.meaning ?? '';

    // Show streamed meaning if generating, otherwise show saved meaning
    final displayMeaning = isGenerating ? streamedMeaning : word.meaning;
    final hasMeaning = displayMeaning.isNotEmpty;

    return Dismissible(
      key: Key(word.id),
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
            title: const Text('Delete Word'),
            content: Text('Are you sure you want to delete "$displayWord"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => widget.onDelete(),
      child: ListTile(
        title: Text(
          displayWord,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasMeaning)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  displayMeaning,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Text(
                    _formatDate(word.createdAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).hintColor,
                        ),
                  ),
                  if (isGenerating) ...[
                    // Show loading indicator while generating
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Generating...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ] else if (!hasMeaning) ...[
                    // Show pending indicator when no meaning and not generating
                    const SizedBox(width: 8),
                    Icon(
                      Icons.pending,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Pending definition',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShareButton(
              content: ShareContent.text(
                sourceAppId: 'vocabulary',
                text: word.word,
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: widget.onTap,
      ),
    );
  }
}
