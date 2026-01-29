import 'package:flutter/material.dart';
import '../models/folder_item.dart';
import '../services/file_system_storage.dart';

class FolderPickerDialog extends StatefulWidget {
  final String currentFolderPath;
  final String fileName;

  const FolderPickerDialog({
    super.key,
    required this.currentFolderPath,
    required this.fileName,
  });

  static Future<String?> show(
    BuildContext context, {
    required String currentFolderPath,
    required String fileName,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => FolderPickerDialog(
        currentFolderPath: currentFolderPath,
        fileName: fileName,
      ),
    );
  }

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  String _selectedPath = '';
  List<FolderItem> _folders = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoading = true);
    try {
      final folders =
          await FileSystemStorage.instance.getFoldersInPath(_selectedPath);
      setState(() => _folders = folders);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _navigateTo(String path) {
    setState(() => _selectedPath = path);
    _loadFolders();
  }

  void _goUp() {
    if (_selectedPath.isEmpty) return;
    final parts = _selectedPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      _navigateTo('');
    } else {
      final parentPath = parts.sublist(0, parts.length - 1).join('/');
      _navigateTo(parentPath.isEmpty ? '' : '$parentPath/');
    }
  }

  List<String> get _pathParts {
    if (_selectedPath.isEmpty) return [];
    return _selectedPath.split('/').where((p) => p.isNotEmpty).toList();
  }

  bool get _canMoveHere {
    return _selectedPath != widget.currentFolderPath;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Move "${widget.fileName}"'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Breadcrumb navigation
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => _navigateTo(''),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          'Home',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: _selectedPath.isEmpty
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                    for (var i = 0; i < _pathParts.length; i++) ...[
                      const Icon(Icons.chevron_right, size: 16),
                      InkWell(
                        onTap: () {
                          final path =
                              '${_pathParts.sublist(0, i + 1).join('/')}/';
                          _navigateTo(path);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            _pathParts[i],
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: i == _pathParts.length - 1
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(),
            // Current selection indicator
            if (_selectedPath != widget.currentFolderPath)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder,
                      size: 20,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Move to: ${_selectedPath.isEmpty ? "Home" : _selectedPath}',
                        style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_selectedPath == widget.currentFolderPath)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'File is already in this folder',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Folder list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _folders.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.folder_open,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No subfolders',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _folders.length,
                          itemBuilder: (context, index) {
                            final folder = _folders[index];
                            final isCurrentFolder =
                                folder.path == widget.currentFolderPath;
                            return ListTile(
                              leading: Icon(
                                Icons.folder,
                                color: isCurrentFolder
                                    ? Colors.grey
                                    : Theme.of(context).colorScheme.primary,
                              ),
                              title: Text(
                                folder.name,
                                style: TextStyle(
                                  color: isCurrentFolder ? Colors.grey : null,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                size: 20,
                              ),
                              onTap: () => _navigateTo(folder.path),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        if (_selectedPath.isNotEmpty)
          TextButton(
            onPressed: _goUp,
            child: const Text('Go Up'),
          ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canMoveHere ? () => Navigator.pop(context, _selectedPath) : null,
          child: const Text('Move Here'),
        ),
      ],
    );
  }
}
