import 'package:flutter/material.dart';
import '../../shared/lms.dart';
import 'package:url_launcher/url_launcher.dart';

class ViewerSubSectionScreen extends StatefulWidget {
  final String courseId;
  final String moduleId;
  final String subSectionId;

  const ViewerSubSectionScreen({
    super.key,
    required this.courseId,
    required this.moduleId,
    required this.subSectionId,
  });

  @override
  State<ViewerSubSectionScreen> createState() => _ViewerSubSectionScreenState();
}

class _ViewerSubSectionScreenState extends State<ViewerSubSectionScreen> {
  final _storage = LmsStorageService.instance;
  LessonSubSection? _subSection;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubSection();
  }

  Future<void> _loadSubSection() async {
    setState(() => _isLoading = true);
    final course = await _storage.getCourse(widget.courseId);
    final module = course?.modules.firstWhere((m) => m.id == widget.moduleId);
    final subSection = module?.subSections.firstWhere(
      (s) => s.id == widget.subSectionId,
    );
    setState(() {
      _subSection = subSection;
      _isLoading = false;
    });
  }

  Future<void> _openActivity(Activity activity) async {
    if (activity is ResourceFileActivity) {
      try {
        final filePath = await FileSystemBridge.instance.getFilePathById(activity.fileId);
        if (filePath != null) {
          final uri = Uri.file(filePath);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          } else {
            throw 'Could not open file';
          }
        } else {
          throw 'File not found';
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error opening file: $e')),
          );
        }
      }
    }
  }

  IconData _getActivityIcon(Activity activity) {
    if (activity is ResourceFileActivity) {
      switch (activity.resourceType) {
        case ResourceType.lecture:
          return Icons.description;
        case ResourceType.audio:
          return Icons.audiotrack;
        case ResourceType.video:
          return Icons.video_library;
        case ResourceType.document:
          return Icons.insert_drive_file;
        case ResourceType.other:
          return Icons.attachment;
      }
    }
    return Icons.assignment;
  }

  Color _getActivityColor(Activity activity) {
    if (activity is ResourceFileActivity) {
      switch (activity.resourceType) {
        case ResourceType.lecture:
          return Colors.blue;
        case ResourceType.audio:
          return Colors.purple;
        case ResourceType.video:
          return Colors.red;
        case ResourceType.document:
          return Colors.green;
        case ResourceType.other:
          return Colors.grey;
      }
    }
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_subSection == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Section not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_subSection!.name),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _subSection!.activities.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.attachment, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No activities yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('This section has no activities'),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _subSection!.activities.length,
              itemBuilder: (context, index) {
                final activity = _subSection!.activities[index];
                final icon = _getActivityIcon(activity);
                final color = _getActivityColor(activity);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.2),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    title: Text(
                      activity.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (activity.description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            activity.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (activity is ResourceFileActivity) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.label,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                activity.resourceType.name.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    trailing: const Icon(Icons.play_arrow),
                    onTap: () => _openActivity(activity),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
