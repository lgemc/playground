import 'package:flutter/material.dart';
import '../models/file_item.dart';
import '../services/file_system_storage.dart';
import '../widgets/file_tile.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<FileItem> _favorites = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);
    try {
      final favorites = await FileSystemStorage.instance.getFavorites();
      if (mounted) {
        setState(() => _favorites = favorites);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showFileContextMenu(FileItem file) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.star_border),
            title: const Text('Remove from Favorites'),
            onTap: () async {
              Navigator.pop(context);
              await FileSystemStorage.instance.toggleFavorite(file.id);
              _loadFavorites();
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Show in Folder'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Navigate to file location
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Delete'),
            onTap: () async {
              Navigator.pop(context);
              await FileSystemStorage.instance.deleteFile(file.id);
              _loadFavorites();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.star_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No favorite files',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Long press on a file to add it to favorites',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.9,
      ),
      itemCount: _favorites.length,
      itemBuilder: (context, index) {
        final file = _favorites[index];
        return FileTile(
          file: file,
          onTap: () {
            // TODO: Open file preview
          },
          onLongPress: () => _showFileContextMenu(file),
        );
      },
    );
  }
}
