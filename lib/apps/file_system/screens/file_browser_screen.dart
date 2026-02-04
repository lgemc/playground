import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../models/file_item.dart';
import '../models/folder_item.dart';
import '../services/file_system_storage.dart';
import '../widgets/file_tile.dart';
import '../widgets/folder_tile.dart';
import '../widgets/folder_breadcrumb.dart';
import 'favorites_screen.dart';
import 'search_screen.dart';
import 'pdf_reader_screen.dart';
import 'file_derivatives_screen.dart';
import '../../video_viewer/screens/video_player_screen.dart';
import '../widgets/folder_picker_dialog.dart';
import '../../../services/share_service.dart';
import '../../../services/share_content.dart';
import '../../../services/shared_files_service.dart';
import '../../../services/generators/auto_title_generator.dart';

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  String _currentPath = '';
  List<FolderItem> _folders = [];
  List<FileItem> _files = [];
  bool _isLoading = false;
  int _selectedTab = 0;
  List<FileSystemEntity> _sharedFiles = [];
  final Map<String, bool> _fileHasDerivatives = {};

  @override
  void initState() {
    super.initState();
    _loadContents();
    _initSharedFiles();
  }

  Future<void> _initSharedFiles() async {
    // Initialize shared files service
    await SharedFilesService().initialize(
      onFilesReceived: (List<String> filePaths) async {
        // When files are received, add them to the file system
        for (final filePath in filePaths) {
          final file = File(filePath);
          if (await file.exists()) {
            await FileSystemStorage.instance.addFile(file, 'shared/');
          }
        }
        // Navigate to shared folder and reload
        setState(() => _currentPath = 'shared/');
        _loadContents();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Received ${filePaths.length} file(s)'),
            ),
          );
        }
      },
    );

    // Load existing shared files
    _loadSharedFiles();
  }

  Future<void> _loadSharedFiles() async {
    final files = await SharedFilesService().getSharedFiles();
    setState(() => _sharedFiles = files);
  }

  Future<void> _loadContents() async {
    setState(() => _isLoading = true);
    try {
      final folders = await FileSystemStorage.instance.getFoldersInPath(_currentPath);
      final files = await FileSystemStorage.instance.getFilesInFolder(_currentPath);

      // Check derivatives for each file
      _fileHasDerivatives.clear();
      for (final file in files) {
        final hasDerivatives =
            await FileSystemStorage.instance.hasDerivatives(file.id);
        _fileHasDerivatives[file.id] = hasDerivatives;
      }

      setState(() {
        _folders = folders;
        _files = files;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _navigateTo(String path) async {
    setState(() => _currentPath = path);
    await _loadContents();
  }

  void _goUp() {
    if (_currentPath.isEmpty) return;
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      _navigateTo('');
    } else {
      final parentPath = parts.sublist(0, parts.length - 1).join('/');
      _navigateTo(parentPath.isEmpty ? '' : '$parentPath/');
    }
  }

  Future<void> _addFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      await FileSystemStorage.instance.addFile(file, _currentPath);
      _loadContents();
    }
  }

  Future<void> _createFolder() async {
    final nameController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Folder name',
            hintText: 'Enter folder name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      await FileSystemStorage.instance.createFolder(
        nameController.text,
        _currentPath,
      );
      _loadContents();
    }
  }

  void _showFileContextMenu(FileItem file) {
    // Check if file can be auto-titled (PDF or Markdown)
    final canAutoTitle = file.name.toLowerCase().endsWith('.pdf') ||
        file.name.toLowerCase().endsWith('.md');

    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(file.isFavorite ? Icons.star_border : Icons.star),
            title: Text(
              file.isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
            ),
            onTap: () async {
              Navigator.pop(context);
              await FileSystemStorage.instance.toggleFavorite(file.id);
              _loadContents();
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('Generate Derivatives'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FileDerivativesScreen(file: file),
                ),
              );
            },
          ),
          if (canAutoTitle)
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename with AI'),
              onTap: () {
                Navigator.pop(context);
                _renameWithAI(file);
              },
            ),
          ListTile(
            leading: const Icon(Icons.drive_file_move),
            title: const Text('Move'),
            onTap: () {
              Navigator.pop(context);
              _moveFile(file);
            },
          ),
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('Share'),
            onTap: () {
              Navigator.pop(context);
              _shareFile(file);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Rename'),
            onTap: () {
              Navigator.pop(context);
              _renameFile(file);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Delete'),
            onTap: () async {
              Navigator.pop(context);
              await FileSystemStorage.instance.deleteFile(file.id);
              _loadContents();
            },
          ),
        ],
      ),
    );
  }

  void _showFolderContextMenu(FolderItem folder) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Rename'),
            onTap: () {
              Navigator.pop(context);
              _renameFolder(folder);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Delete'),
            onTap: () async {
              Navigator.pop(context);
              try {
                await FileSystemStorage.instance.deleteFolder(folder.path);
                _loadContents();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString()}')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _renameFile(FileItem file) async {
    final nameController = TextEditingController(text: file.name);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename File'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'New name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      await FileSystemStorage.instance.renameFile(file.id, nameController.text);
      _loadContents();
    }
  }

  Future<void> _renameWithAI(FileItem file) async {
    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Generating title with AI...'),
          ],
        ),
      ),
    );

    try {
      // Create derivative using the auto-title generator
      final generator = AutoTitleGenerator();

      // Check if generator can process this file
      if (!generator.canProcess(file)) {
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This file type is not supported for AI renaming'),
            ),
          );
        }
        return;
      }

      // Generate the title
      final derivativeContent = await generator.generate(file);

      // Parse the proposed title from markdown content
      final lines = derivativeContent.split('\n');
      String? proposedTitle;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line == '# Proposed Title' && i + 2 < lines.length) {
          proposedTitle = lines[i + 2].trim();
          break;
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (proposedTitle == null || proposedTitle.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to generate title')),
          );
        }
        return;
      }

      // Show confirmation dialog
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Apply AI-Generated Title'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Rename file?', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              Text('From: ${file.name}',
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              Text('To: $proposedTitle.${file.extension}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        final extension = file.extension;
        final newName = extension.isNotEmpty
            ? '$proposedTitle.$extension'
            : proposedTitle;

        await FileSystemStorage.instance.renameFile(file.id, newName);
        _loadContents();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File renamed to $newName')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog if still open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate title: $e')),
        );
      }
    }
  }

  Future<void> _moveFile(FileItem file) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final targetPath = await FolderPickerDialog.show(
      context,
      currentFolderPath: file.folderPath,
      fileName: file.name,
    );

    if (targetPath != null) {
      await FileSystemStorage.instance.moveFile(file.id, targetPath);
      _loadContents();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'Moved to ${targetPath.isEmpty ? "Home" : targetPath}',
          ),
        ),
      );
    }
  }

  Future<void> _shareFile(FileItem file) async {
    final content = ShareContent.file(
      sourceAppId: 'file_system',
      path: file.relativePath,
      name: file.name,
      mimeType: file.mimeType,
    );

    // Add fileId to the data payload
    content.data['fileId'] = file.id;

    await ShareService.instance.share(context, content);
  }

  Future<void> _openFile(FileItem file) async {
    // Check if file has derivatives
    final hasDerivatives =
        await FileSystemStorage.instance.hasDerivatives(file.id);

    if (hasDerivatives) {
      // Navigate to derivatives view
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FileDerivativesScreen(file: file),
          ),
        );
      }
    } else {
      // Open file directly (existing behavior)
      _openFileDirect(file);
    }
  }

  void _openFileDirect(FileItem file) {
    final filePath = FileSystemStorage.instance.getAbsolutePath(file);
    final physicalFile = File(filePath);

    // Check if file exists on disk (metadata may be synced but content not yet)
    if (!physicalFile.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File not downloaded yet. Content sync coming soon!'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final ext = file.extension.toLowerCase();

    // Check if it's a PDF file
    if (ext == 'pdf') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PdfReaderScreen(
            filePath: filePath,
            fileName: file.name,
          ),
        ),
      );
    } else if (ext == 'mp4' || ext == 'mkv' || ext == 'avi' ||
               ext == 'mov' || ext == 'webm' || ext == 'flv' ||
               ext == 'm4v' || ext == '3gp') {
      // Video files
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            filePath: filePath,
            fileName: file.name,
          ),
        ),
      );
    } else {
      // For other files, show a message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot open ${file.extension} files yet')),
      );
    }
  }

  Future<void> _renameFolder(FolderItem folder) async {
    final nameController = TextEditingController(text: folder.name);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Folder'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'New name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      await FileSystemStorage.instance.renameFolder(
        folder.path,
        nameController.text,
      );
      _loadContents();
    }
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('New Folder'),
            onTap: () {
              Navigator.pop(context);
              _createFolder();
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_upload),
            title: const Text('Add File'),
            onTap: () {
              Navigator.pop(context);
              _addFile();
            },
          ),
          if (_sharedFiles.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.folder_shared),
              title: Text('View Shared Files (${_sharedFiles.length})'),
              onTap: () {
                Navigator.pop(context);
                _navigateTo('shared/');
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBrowserTab() {
    return Column(
      children: [
        FolderBreadcrumb(
          currentPath: _currentPath,
          onNavigate: _navigateTo,
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _folders.isEmpty && _files.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.folder_open,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No files or folders',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.9,
                      ),
                      itemCount: _folders.length + _files.length,
                      itemBuilder: (context, index) {
                        if (index < _folders.length) {
                          final folder = _folders[index];
                          return FolderTile(
                            folder: folder,
                            onTap: () => _navigateTo(folder.path),
                            onLongPress: () => _showFolderContextMenu(folder),
                          );
                        } else {
                          final file = _files[index - _folders.length];
                          return FileTile(
                            file: file,
                            onTap: () => _openFile(file),
                            onLongPress: () => _showFileContextMenu(file),
                            hasDerivatives: _fileHasDerivatives[file.id] ?? false,
                          );
                        }
                      },
                    ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_selectedTab) {
      case 0:
        body = _buildBrowserTab();
        break;
      case 1:
        body = const FavoritesScreen();
        break;
      case 2:
        body = const SearchScreen();
        break;
      default:
        body = _buildBrowserTab();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('File System'),
        leading: _currentPath.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _goUp,
              )
            : null,
      ),
      body: body,
      floatingActionButton: _selectedTab == 0
          ? FloatingActionButton(
              onPressed: _showAddMenu,
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTab,
        onTap: (index) => setState(() => _selectedTab = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Browse',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.star),
            label: 'Favorites',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
        ],
      ),
    );
  }
}
