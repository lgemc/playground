import 'package:flutter/material.dart';
import '../../shared/lms.dart';

class ActivityListTile extends StatelessWidget {
  final Activity activity;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ActivityListTile({
    super.key,
    required this.activity,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(activity.id),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          onDelete();
          return false;
        } else {
          onEdit();
          return false;
        }
      },
      background: Container(
        color: Colors.blue,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        child: ListTile(
          leading: Icon(_getActivityIcon(), color: Colors.deepPurple),
          title: Text(activity.name),
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
                FutureBuilder<String?>(
                  future: _getFileName(activity as ResourceFileActivity),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      return Row(
                        children: [
                          const Icon(Icons.attachment, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              snapshot.data!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ],
          ),
          trailing: const Icon(Icons.drag_handle),
        ),
      ),
    );
  }

  IconData _getActivityIcon() {
    if (activity is ResourceFileActivity) {
      final resourceActivity = activity as ResourceFileActivity;
      switch (resourceActivity.resourceType) {
        case ResourceType.lecture:
          return Icons.school;
        case ResourceType.audio:
          return Icons.audiotrack;
        case ResourceType.video:
          return Icons.videocam;
        case ResourceType.document:
          return Icons.description;
        case ResourceType.other:
          return Icons.insert_drive_file;
      }
    }
    return Icons.quiz;
  }

  Future<String?> _getFileName(ResourceFileActivity activity) async {
    if (activity.fileId == null) return null;
    final file = await FileSystemBridge.instance.getFileById(activity.fileId!);
    return file?.name;
  }
}
