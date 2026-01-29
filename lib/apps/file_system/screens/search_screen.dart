import 'package:flutter/material.dart';
import '../models/file_item.dart';
import '../services/file_system_storage.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  List<FileItem> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final results = await FileSystemStorage.instance.search(query);
      if (mounted) {
        setState(() {
          _results = results;
          _hasSearched = true;
        });
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
            leading: Icon(file.isFavorite ? Icons.star_border : Icons.star),
            title: Text(
              file.isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
            ),
            onTap: () async {
              Navigator.pop(context);
              await FileSystemStorage.instance.toggleFavorite(file.id);
              _search(_searchController.text);
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
              _search(_searchController.text);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search files...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _search('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: _search,
            autofocus: true,
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : !_hasSearched
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Search for files',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _results.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No results found',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final file = _results[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(
                                  file.isImage
                                      ? Icons.image
                                      : file.isVideo
                                          ? Icons.video_file
                                          : file.isAudio
                                              ? Icons.audio_file
                                              : file.isDocument
                                                  ? Icons.description
                                                  : Icons.insert_drive_file,
                                  color: Theme.of(context).primaryColor,
                                ),
                                title: Text(file.name),
                                subtitle: Text(
                                  file.folderPath.isEmpty
                                      ? 'Root'
                                      : file.folderPath,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                trailing: file.isFavorite
                                    ? const Icon(
                                        Icons.star,
                                        color: Colors.amber,
                                        size: 20,
                                      )
                                    : null,
                                onTap: () {
                                  // TODO: Open file preview
                                },
                                onLongPress: () => _showFileContextMenu(file),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
