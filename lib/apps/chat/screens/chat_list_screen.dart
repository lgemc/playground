import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../services/chat_storage.dart';
import 'chat_detail_screen.dart';
import 'package:uuid/uuid.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({Key? key}) : super(key: key);

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<Chat> _chats = [];
  List<Chat> _filteredChats = [];
  final TextEditingController _searchController = TextEditingController();
  final Uuid _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _loadChats();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    final chats = await ChatStorage.instance.getAllChats();
    setState(() {
      _chats = chats;
      _filteredChats = chats;
    });
  }

  void _onSearchChanged() {
    final keyword = _searchController.text;
    if (keyword.isEmpty) {
      setState(() {
        _filteredChats = _chats;
      });
    } else {
      _performSearch(keyword);
    }
  }

  Future<void> _performSearch(String keyword) async {
    final results = await ChatStorage.instance.searchChats(keyword);
    setState(() {
      _filteredChats = results;
    });
  }

  Future<void> _createNewChat() async {
    final now = DateTime.now();
    final chat = Chat(
      id: _uuid.v4(),
      title: 'Generating title...',
      createdAt: now,
      updatedAt: now,
      isTitleGenerating: true,
    );

    await ChatStorage.instance.createChat(chat);
    await _loadChats();

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatDetailScreen(
            chat: chat,
            onChatUpdated: _loadChats,
          ),
        ),
      );
    }
  }

  Future<void> _restartChat(Chat chat) async {
    await ChatStorage.instance.deleteMessages(chat.id);

    final restartedChat = chat.copyWith(
      title: 'Generating title...',
      updatedAt: DateTime.now(),
      isTitleGenerating: true,
    );

    await ChatStorage.instance.updateChat(restartedChat);
    await _loadChats();

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatDetailScreen(
            chat: restartedChat,
            onChatUpdated: _loadChats,
          ),
        ),
      );
    }
  }

  Future<void> _deleteChat(Chat chat) async {
    await ChatStorage.instance.deleteChat(chat.id);
    await _loadChats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search chats...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: _filteredChats.isEmpty
                ? Center(
                    child: Text(
                      _chats.isEmpty
                          ? 'No chats yet. Create one!'
                          : 'No chats found',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredChats.length,
                    itemBuilder: (context, index) {
                      final chat = _filteredChats[index];
                      return Dismissible(
                        key: Key(chat.id),
                        background: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 20),
                          color: Colors.blue,
                          child: const Icon(Icons.refresh, color: Colors.white),
                        ),
                        secondaryBackground: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async {
                          if (direction == DismissDirection.endToStart) {
                            return await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Chat'),
                                content: Text(
                                    'Are you sure you want to delete "${chat.title}"?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    style: TextButton.styleFrom(
                                        foregroundColor: Colors.red),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            return await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Restart Chat'),
                                content: const Text(
                                    'This will clear all messages. Are you sure?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    style: TextButton.styleFrom(
                                        foregroundColor: Colors.blue),
                                    child: const Text('Restart'),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                        onDismissed: (direction) {
                          if (direction == DismissDirection.endToStart) {
                            _deleteChat(chat);
                          } else {
                            _restartChat(chat);
                          }
                        },
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.chat_bubble_outline),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    chat.title,
                                    style: TextStyle(
                                      fontStyle: chat.isTitleGenerating
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                    ),
                                  ),
                                ),
                                if (chat.isTitleGenerating)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              'Updated: ${_formatDate(chat.updatedAt)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatDetailScreen(
                                    chat: chat,
                                    onChatUpdated: _loadChats,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewChat,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
