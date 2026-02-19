import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math';
import '../../shared/models/reviewable_item.dart';

/// Widget for displaying and answering different types of quiz questions
class QuestionWidget extends StatefulWidget {
  final ReviewableItem reviewableItem;
  final String? userAnswer;
  final Function(String) onAnswerChanged;
  final bool shuffleAnswers;

  const QuestionWidget({
    Key? key,
    required this.reviewableItem,
    this.userAnswer,
    required this.onAnswerChanged,
    this.shuffleAnswers = true,
  }) : super(key: key);

  @override
  State<QuestionWidget> createState() => _QuestionWidgetState();
}

class _QuestionWidgetState extends State<QuestionWidget> {
  late List<String> _options;
  final TextEditingController _textController = TextEditingController();
  final Set<String> _selectedMultipleChoices = {};

  @override
  void initState() {
    super.initState();
    _initializeOptions();
    _initializeAnswer();
  }

  void _initializeOptions() {
    if (widget.reviewableItem.type == ReviewableType.multipleChoice ||
        widget.reviewableItem.type == ReviewableType.trueFalse) {
      // Combine correct answer with distractors
      _options = [
        if (widget.reviewableItem.answer != null) widget.reviewableItem.answer!,
        ...widget.reviewableItem.distractors,
      ];

      // Shuffle if needed
      if (widget.shuffleAnswers) {
        _options.shuffle(Random());
      }
    }
  }

  void _initializeAnswer() {
    if (widget.userAnswer != null) {
      _textController.text = widget.userAnswer!;

      // For multiple choice with multiple selections
      if (widget.userAnswer!.contains(',')) {
        _selectedMultipleChoices.addAll(
          widget.userAnswer!.split(',').map((e) => e.trim()),
        );
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Question content
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildTypeIcon(),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getTypeLabel(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.reviewableItem.content,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Answer input based on type
        _buildAnswerInput(),
      ],
    );
  }

  Widget _buildTypeIcon() {
    IconData icon;
    Color color;

    switch (widget.reviewableItem.type) {
      case ReviewableType.multipleChoice:
        icon = Icons.radio_button_checked;
        color = Colors.blue;
        break;
      case ReviewableType.trueFalse:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case ReviewableType.fillInBlank:
        icon = Icons.edit;
        color = Colors.orange;
        break;
      case ReviewableType.shortAnswer:
        icon = Icons.notes;
        color = Colors.purple;
        break;
      case ReviewableType.flashcard:
        icon = Icons.style;
        color = Colors.teal;
        break;
      case ReviewableType.procedure:
        icon = Icons.list;
        color = Colors.indigo;
        break;
      case ReviewableType.summary:
        icon = Icons.summarize;
        color = Colors.pink;
        break;
    }

    return Icon(icon, size: 16, color: color);
  }

  String _getTypeLabel() {
    switch (widget.reviewableItem.type) {
      case ReviewableType.multipleChoice:
        // Check metadata for single vs multiple selection
        final metadata = widget.reviewableItem.metadata;
        final isMultipleSelection = metadata['multipleSelection'] == true;
        return isMultipleSelection ? 'Multiple Selection' : 'Multiple Choice (Single)';
      case ReviewableType.trueFalse:
        return 'True or False';
      case ReviewableType.fillInBlank:
        return 'Fill in the Blank';
      case ReviewableType.shortAnswer:
        return 'Short Answer';
      case ReviewableType.flashcard:
        return 'Flashcard';
      case ReviewableType.procedure:
        return 'Procedure';
      case ReviewableType.summary:
        return 'Summary';
    }
  }

  Widget _buildAnswerInput() {
    switch (widget.reviewableItem.type) {
      case ReviewableType.multipleChoice:
        final metadata = widget.reviewableItem.metadata;
        final isMultipleSelection = metadata['multipleSelection'] == true;
        return isMultipleSelection
            ? _buildMultipleSelectionInput()
            : _buildSingleChoiceInput();

      case ReviewableType.trueFalse:
        return _buildTrueFalseInput();

      case ReviewableType.fillInBlank:
        return _buildFillInBlankInput();

      case ReviewableType.shortAnswer:
      case ReviewableType.flashcard:
      case ReviewableType.procedure:
      case ReviewableType.summary:
        return _buildTextInput();
    }
  }

  Widget _buildSingleChoiceInput() {
    return Column(
      children: _options.map((option) {
        final isSelected = widget.userAnswer == option;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: isSelected ? Colors.blue[50] : null,
          child: InkWell(
            onTap: () => widget.onAnswerChanged(option),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: isSelected ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      option,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMultipleSelectionInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Select all correct answers',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ..._options.map((option) {
          final isSelected = _selectedMultipleChoices.contains(option);

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: isSelected ? Colors.blue[50] : null,
            child: CheckboxListTile(
              value: isSelected,
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _selectedMultipleChoices.add(option);
                  } else {
                    _selectedMultipleChoices.remove(option);
                  }
                  // Join with commas for storage
                  widget.onAnswerChanged(_selectedMultipleChoices.join(', '));
                });
              },
              title: Text(
                option,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildTrueFalseInput() {
    return Row(
      children: [
        Expanded(
          child: Card(
            color: widget.userAnswer == 'true' ? Colors.green[50] : null,
            child: InkWell(
              onTap: () => widget.onAnswerChanged('true'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 48,
                      color: widget.userAnswer == 'true' ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'True',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: widget.userAnswer == 'true'
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            color: widget.userAnswer == 'false' ? Colors.red[50] : null,
            child: InkWell(
              onTap: () => widget.onAnswerChanged('false'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.cancel,
                      size: 48,
                      color: widget.userAnswer == 'false' ? Colors.red : Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'False',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: widget.userAnswer == 'false'
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFillInBlankInput() {
    // Parse the content to find blanks (_____)
    final content = widget.reviewableItem.content;
    final blanks = '___'.allMatches(content).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  blanks > 1
                      ? 'Fill in the blanks (separate with commas)'
                      : 'Fill in the blank',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _textController,
          onChanged: widget.onAnswerChanged,
          decoration: InputDecoration(
            hintText: 'Type your answer here...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          maxLines: blanks > 1 ? 3 : 1,
        ),
      ],
    );
  }

  Widget _buildTextInput() {
    final isLongForm = widget.reviewableItem.type == ReviewableType.procedure ||
        widget.reviewableItem.type == ReviewableType.summary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLongForm)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.purple[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Provide a detailed answer',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.purple[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (isLongForm) const SizedBox(height: 12),
        TextField(
          controller: _textController,
          onChanged: widget.onAnswerChanged,
          decoration: InputDecoration(
            hintText: 'Type your answer here...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          maxLines: isLongForm ? 8 : 3,
        ),
      ],
    );
  }
}
