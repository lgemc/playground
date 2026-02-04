import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/transcript.dart';
import '../../../services/share_service.dart';
import '../../../services/share_content.dart';
import '../services/transcript_storage.dart';

/// Screen to view and interact with transcripts.
class TranscriptViewerScreen extends StatefulWidget {
  final Transcript transcript;
  final String fileName;
  final Function(double timestamp)? onSeekToTimestamp;

  const TranscriptViewerScreen({
    super.key,
    required this.transcript,
    required this.fileName,
    this.onSeekToTimestamp,
  });

  @override
  State<TranscriptViewerScreen> createState() => _TranscriptViewerScreenState();
}

class _TranscriptViewerScreenState extends State<TranscriptViewerScreen> {
  String _searchQuery = '';
  String? _selectedSpeaker;
  bool _showWordTimestamps = false;
  bool _showOnlyRelevant = false;
  Map<String, bool> _relevantSegments = {};

  @override
  void initState() {
    super.initState();
    _loadRelevantSegments();
  }

  Future<void> _loadRelevantSegments() async {
    final segments = await TranscriptStorage.instance
        .getRelevantSegmentsForFile(widget.fileName);
    setState(() {
      _relevantSegments = segments;
    });
  }

  String _getSegmentKey(TranscriptSegment segment) {
    return '${segment.start}_${segment.end}';
  }

  bool _isSegmentRelevant(TranscriptSegment segment) {
    return _relevantSegments[_getSegmentKey(segment)] ?? false;
  }

  Future<void> _toggleSegmentRelevance(TranscriptSegment segment) async {
    final isCurrentlyRelevant = _isSegmentRelevant(segment);
    await TranscriptStorage.instance.setSegmentRelevance(
      fileName: widget.fileName,
      segmentStart: segment.start,
      segmentEnd: segment.end,
      isRelevant: !isCurrentlyRelevant,
    );
    await _loadRelevantSegments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Transcript: ${widget.fileName}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearchDialog,
          ),
          IconButton(
            icon: Icon(_showOnlyRelevant ? Icons.star : Icons.star_border),
            onPressed: () {
              setState(() {
                _showOnlyRelevant = !_showOnlyRelevant;
              });
            },
            tooltip: _showOnlyRelevant ? 'Show all segments' : 'Show only relevant',
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _showExportDialog,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (speaker) {
              setState(() {
                _selectedSpeaker = speaker == 'all' ? null : speaker;
              });
            },
            itemBuilder: (context) {
              final speakers = widget.transcript.speakers.toList()..sort();
              return [
                const PopupMenuItem(
                  value: 'all',
                  child: Text('All speakers'),
                ),
                ...speakers.map((speaker) => PopupMenuItem(
                      value: speaker,
                      child: Text(speaker),
                    )),
              ];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildInfoHeader(),
          Expanded(child: _buildSegmentList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _showWordTimestamps = !_showWordTimestamps;
          });
        },
        child: Icon(_showWordTimestamps ? Icons.text_fields : Icons.timer),
      ),
    );
  }

  Widget _buildInfoHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[200],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Language: ${widget.transcript.language.toUpperCase()}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Duration: ${_formatDuration(widget.transcript.duration)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Segments: ${widget.transcript.segments.length} | '
            'Speakers: ${widget.transcript.speakers.length}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blue[200]!, width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tap words to share • Long press for details • ${_showWordTimestamps ? 'Colored by confidence' : 'Toggle word mode for confidence view'}',
                    style: TextStyle(fontSize: 11, color: Colors.blue[900]),
                  ),
                ),
              ],
            ),
          ),
          if (_selectedSpeaker != null || _showOnlyRelevant)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  if (_selectedSpeaker != null)
                    Chip(
                      label: Text('Speaker: $_selectedSpeaker'),
                      onDeleted: () {
                        setState(() {
                          _selectedSpeaker = null;
                        });
                      },
                    ),
                  if (_showOnlyRelevant)
                    Chip(
                      avatar: const Icon(Icons.star, size: 16),
                      label: const Text('Relevant only'),
                      onDeleted: () {
                        setState(() {
                          _showOnlyRelevant = false;
                        });
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSegmentList() {
    final segments = _getFilteredSegments();

    if (segments.isEmpty) {
      return const Center(
        child: Text('No segments match your filters'),
      );
    }

    return ListView.builder(
      itemCount: segments.length,
      itemBuilder: (context, index) {
        final segment = segments[index];
        final isHighlighted = _searchQuery.isNotEmpty &&
            segment.text.toLowerCase().contains(_searchQuery.toLowerCase());

        final isRelevant = _isSegmentRelevant(segment);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: isHighlighted ? Colors.yellow[100] : null,
          child: InkWell(
            onTap: widget.onSeekToTimestamp != null
                ? () => widget.onSeekToTimestamp!(segment.start)
                : null,
            onLongPress: () => _showSegmentMenu(context, segment),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (isRelevant)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(Icons.star, size: 16, color: Colors.amber),
                              ),
                            Text(
                              '${segment.startFormatted} - ${segment.endFormatted}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Chip(
                            label: Text(
                              segment.speaker,
                              style: const TextStyle(fontSize: 10),
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _showSegmentMenu(context, segment),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Show clickable words in normal mode too
                  Wrap(
                    spacing: 2,
                    runSpacing: 4,
                    children: segment.words.map((word) {
                      return MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => _shareWord(word.word),
                          onLongPress: () => _showWordDetails(word),
                          child: Text(
                            '${word.word} ',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.blue[800],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (_showWordTimestamps) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: segment.words.map((word) {
                        return InkWell(
                          onTap: () => _shareWord(word.word),
                          onLongPress: () => _showWordDetails(word),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _getConfidenceColor(word.score),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _getConfidenceBorderColor(word.score),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              word.word,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[900],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<TranscriptSegment> _getFilteredSegments() {
    var segments = widget.transcript.segments;

    if (_selectedSpeaker != null) {
      segments = segments
          .where((segment) => segment.speaker == _selectedSpeaker)
          .toList();
    }

    if (_showOnlyRelevant) {
      segments = segments
          .where((segment) => _isSegmentRelevant(segment))
          .toList();
    }

    return segments;
  }

  Color _getConfidenceColor(double score) {
    if (score >= 0.9) return Colors.green[50]!;
    if (score >= 0.7) return Colors.amber[50]!;
    if (score >= 0.5) return Colors.orange[50]!;
    return Colors.red[50]!;
  }

  Color _getConfidenceBorderColor(double score) {
    if (score >= 0.9) return Colors.green[300]!;
    if (score >= 0.7) return Colors.amber[300]!;
    if (score >= 0.5) return Colors.orange[300]!;
    return Colors.red[300]!;
  }

  String _formatDuration(double seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = (seconds % 60).toInt();

    if (hours > 0) {
      return '${hours}h ${minutes}m ${secs}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${secs}s';
    }
    return '${secs}s';
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Transcript'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter search term...',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _searchQuery = '';
              });
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Transcript'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Plain Text'),
              onTap: () {
                _exportPlainText();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('JSON'),
              onTap: () {
                _exportJson();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.subtitles),
              title: const Text('WebVTT'),
              onTap: () {
                _exportVTT();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.closed_caption),
              title: const Text('SRT'),
              onTap: () {
                _exportSRT();
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _exportPlainText() {
    final text = widget.transcript.fullText;
    Clipboard.setData(ClipboardData(text: text));
    _showSnackBar('Plain text copied to clipboard');
  }

  void _exportJson() {
    final json = widget.transcript.toJsonString();
    Clipboard.setData(ClipboardData(text: json));
    _showSnackBar('JSON copied to clipboard');
  }

  void _exportVTT() {
    final vtt = _generateVTT();
    Clipboard.setData(ClipboardData(text: vtt));
    _showSnackBar('WebVTT copied to clipboard');
  }

  void _exportSRT() {
    final srt = _generateSRT();
    Clipboard.setData(ClipboardData(text: srt));
    _showSnackBar('SRT copied to clipboard');
  }

  String _generateVTT() {
    final buffer = StringBuffer('WEBVTT\n\n');

    for (final segment in widget.transcript.segments) {
      buffer.writeln(
          '${_formatVTTTimestamp(segment.start)} --> ${_formatVTTTimestamp(segment.end)}');
      buffer.writeln(segment.text.trim());
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _generateSRT() {
    final buffer = StringBuffer();
    int index = 1;

    for (final segment in widget.transcript.segments) {
      buffer.writeln(index);
      buffer.writeln(
          '${_formatSRTTimestamp(segment.start)} --> ${_formatSRTTimestamp(segment.end)}');
      buffer.writeln(segment.text.trim());
      buffer.writeln();
      index++;
    }

    return buffer.toString();
  }

  String _formatVTTTimestamp(double seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toStringAsFixed(3).padLeft(6, '0')}';
  }

  String _formatSRTTimestamp(double seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = (seconds % 60).toInt();
    final millis = ((seconds % 1) * 1000).toInt();

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')},'
        '${millis.toString().padLeft(3, '0')}';
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _shareWord(String word) async {
    final content = ShareContent.text(
      sourceAppId: 'video_viewer',
      text: word,
    );

    await ShareService.instance.share(context, content);
  }

  void _showWordDetails(TranscriptWord word) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(word.word),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Start', '${word.start.toStringAsFixed(3)}s'),
            _buildDetailRow('End', '${word.end.toStringAsFixed(3)}s'),
            _buildDetailRow('Duration', '${word.duration.toStringAsFixed(3)}s'),
            _buildDetailRow('Confidence', '${word.confidencePercent.toStringAsFixed(1)}%'),
            _buildDetailRow('Speaker', word.speaker),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: word.word));
              Navigator.pop(context);
              _showSnackBar('Word copied to clipboard');
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _shareWord(word.word);
            },
            child: const Text('Share'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(value),
        ],
      ),
    );
  }

  void _showSegmentMenu(BuildContext context, TranscriptSegment segment) {
    final isRelevant = _isSegmentRelevant(segment);

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isRelevant ? Icons.star_border : Icons.star,
                color: Colors.amber,
              ),
              title: Text(isRelevant ? 'Unmark as relevant' : 'Mark as relevant'),
              onTap: () {
                Navigator.pop(context);
                _toggleSegmentRelevance(segment);
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('Copy text'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: segment.text));
                Navigator.pop(context);
                _showSnackBar('Text copied to clipboard');
              },
            ),
            if (widget.onSeekToTimestamp != null)
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Jump to timestamp'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onSeekToTimestamp!(segment.start);
                },
              ),
          ],
        ),
      ),
    );
  }
}
