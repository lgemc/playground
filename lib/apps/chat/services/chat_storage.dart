import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/chat.dart';
import '../models/message.dart';

class ChatStorage {
  Database? _database;

  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory('${appDir.path}/data/chat');
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }

    final dbPath = join(dataDir.path, 'chats.db');
    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE chats (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        isTitleGenerating INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        chatId TEXT NOT NULL,
        content TEXT NOT NULL,
        isUser INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (chatId) REFERENCES chats (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_messages_chatId ON messages(chatId)
    ''');
  }

  Future<void> dispose() async {
    await _database?.close();
  }

  // Chat operations
  Future<void> createChat(Chat chat) async {
    await _database!.insert('chats', chat.toMap());
  }

  Future<void> updateChat(Chat chat) async {
    await _database!.update(
      'chats',
      chat.toMap(),
      where: 'id = ?',
      whereArgs: [chat.id],
    );
  }

  Future<void> deleteChat(String chatId) async {
    await _database!.delete(
      'chats',
      where: 'id = ?',
      whereArgs: [chatId],
    );
  }

  Future<List<Chat>> getAllChats() async {
    final List<Map<String, dynamic>> maps = await _database!.query(
      'chats',
      orderBy: 'updatedAt DESC',
    );
    return List.generate(maps.length, (i) => Chat.fromMap(maps[i]));
  }

  Future<Chat?> getChat(String chatId) async {
    final List<Map<String, dynamic>> maps = await _database!.query(
      'chats',
      where: 'id = ?',
      whereArgs: [chatId],
    );
    if (maps.isEmpty) return null;
    return Chat.fromMap(maps.first);
  }

  Future<List<Chat>> searchChats(String keyword) async {
    final List<Map<String, dynamic>> maps = await _database!.query(
      'chats',
      where: 'title LIKE ?',
      whereArgs: ['%$keyword%'],
      orderBy: 'updatedAt DESC',
    );
    return List.generate(maps.length, (i) => Chat.fromMap(maps[i]));
  }

  // Message operations
  Future<void> createMessage(Message message) async {
    print('[ChatStorage] createMessage: id=${message.id}, content="${message.content.length > 50 ? '${message.content.substring(0, 50)}...' : message.content}", isUser=${message.isUser}');
    await _database!.insert('messages', message.toMap());
  }

  Future<List<Message>> getMessages(String chatId) async {
    final List<Map<String, dynamic>> maps = await _database!.query(
      'messages',
      where: 'chatId = ?',
      whereArgs: [chatId],
      orderBy: 'createdAt ASC',
    );
    final messages = List.generate(maps.length, (i) => Message.fromMap(maps[i]));
    print('[ChatStorage] getMessages($chatId): ${messages.length} messages');
    for (final m in messages) {
      print('[ChatStorage]   - id=${m.id}, content="${m.content.length > 50 ? '${m.content.substring(0, 50)}...' : m.content}", isUser=${m.isUser}');
    }
    return messages;
  }

  Future<void> deleteMessages(String chatId) async {
    await _database!.delete(
      'messages',
      where: 'chatId = ?',
      whereArgs: [chatId],
    );
  }
}
