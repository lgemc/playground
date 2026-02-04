import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../../../models/transcript.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String? filePath;
  final String? fileName;
  final Transcript? transcript;

  const VideoPlayerScreen({
    super.key,
    this.filePath,
    this.fileName,
    this.transcript,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _showTranscript = true;
  TranscriptSegment? _currentSegment;

  @override
  void initState() {
    super.initState();
    if (widget.filePath != null) {
      _initializeVideoPlayer();
    }
    // Start listening to video position if transcript available
    if (widget.transcript != null) {
      _startTranscriptSync();
    }
  }

  void _startTranscriptSync() {
    // Update current segment every 100ms based on video position
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted || _controller == null || !_controller!.value.isInitialized) {
        return false;
      }

      final position = _controller!.value.position.inMilliseconds / 1000.0;
      final segment = widget.transcript?.segmentAt(position);

      if (segment != _currentSegment) {
        setState(() {
          _currentSegment = segment;
        });
      }

      return true;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideoPlayer() async {
    try {
      _controller = VideoPlayerController.file(File(widget.filePath!));
      await _controller!.initialize();
      setState(() {
        _isInitialized = true;
      });
      _controller!.play();
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName ?? 'Video Player',
          overflow: TextOverflow.ellipsis,
        ),
        actions: widget.transcript != null
            ? [
                IconButton(
                  icon: Icon(
                    _showTranscript ? Icons.subtitles_off : Icons.subtitles,
                  ),
                  onPressed: () {
                    setState(() {
                      _showTranscript = !_showTranscript;
                    });
                  },
                  tooltip: _showTranscript ? 'Hide transcript' : 'Show transcript',
                ),
              ]
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (widget.filePath == null) {
      return const Center(
        child: Text('No video file selected'),
      );
    }

    // Desktop platforms - show button to open with system viewer
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_file, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Video: ${widget.fileName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Path: ${widget.filePath}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            const Text(
              'Video player not yet supported on desktop',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () {
                // Open with system default video player
                Process.run('xdg-open', [widget.filePath!]);
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open with system viewer'),
            ),
          ],
        ),
      );
    }

    // Mobile platforms - use video_player
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Error loading video'),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // Show transcript alongside video if available
    if (widget.transcript != null && _showTranscript) {
      return Row(
        children: [
          // Video player on left
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                  ),
                ),
                _buildControls(),
              ],
            ),
          ),
          // Transcript on right
          Expanded(
            flex: 1,
            child: _buildTranscriptPanel(),
          ),
        ],
      );
    }

    // No transcript or hidden
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
        ),
        _buildControls(),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.black87,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VideoProgressIndicator(
            _controller!,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: Colors.deepPurple,
              bufferedColor: Colors.grey,
              backgroundColor: Colors.white24,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
                onPressed: _togglePlayPause,
              ),
              const SizedBox(width: 16),
              Text(
                _formatDuration(_controller!.value.position),
                style: const TextStyle(color: Colors.white),
              ),
              const Text(' / ', style: TextStyle(color: Colors.white)),
              Text(
                _formatDuration(_controller!.value.duration),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Widget _buildTranscriptPanel() {
    if (widget.transcript == null) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          left: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.subtitles, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Transcript',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.transcript!.segments.length} segments',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          // Segments list
          Expanded(
            child: ListView.builder(
              itemCount: widget.transcript!.segments.length,
              itemBuilder: (context, index) {
                final segment = widget.transcript!.segments[index];
                final isCurrent = _currentSegment == segment;

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  color: isCurrent ? Colors.blue[50] : Colors.white,
                  elevation: isCurrent ? 4 : 1,
                  child: InkWell(
                    onTap: () {
                      // Seek to this segment
                      _controller?.seekTo(
                        Duration(
                          milliseconds: (segment.start * 1000).toInt(),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                segment.startFormatted,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isCurrent
                                      ? Colors.blue[700]
                                      : Colors.grey[600],
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  segment.speaker,
                                  style: const TextStyle(fontSize: 8),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            segment.text,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  isCurrent ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
