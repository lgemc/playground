import 'package:flutter/material.dart';
import '../models/file_item.dart';

class FileTile extends StatelessWidget {
  final FileItem file;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool hasDerivatives;

  const FileTile({
    super.key,
    required this.file,
    required this.onTap,
    required this.onLongPress,
    this.hasDerivatives = false,
  });

  IconData _getFileIcon() {
    if (file.isImage) return Icons.image;
    if (file.isVideo) return Icons.video_file;
    if (file.isAudio) return Icons.audio_file;
    if (file.isDocument) return Icons.description;
    final ext = file.extension.toLowerCase();
    if (ext == 'zip' || ext == 'tar' || ext == 'gz') return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getFileIcon(),
                    size: 48,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          file.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (file.isFavorite)
                        const Icon(
                          Icons.star,
                          size: 16,
                          color: Colors.amber,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatSize(file.size),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (hasDerivatives)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
