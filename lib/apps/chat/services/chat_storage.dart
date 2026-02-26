import '../models/chat.dart';
import '../models/message.dart';
import '../../../core/database/crdt_database.dart';
import '../../../core/sync/services/device_id_service.dart';
import '../../../core/app_bus.dart';
import '../../../core/app_event.dart';

/// Storage service using CRDT database for sync support
class ChatStorage {
  static ChatStorage? _instance;
  static ChatStorage get instance => _instance ??= ChatStorage._();

  ChatStorage._();

  /// Load all chats
  Future<List<Chat>> getAllChats() async {
    print('[ChatStorage] getAllChats called');
    final results = await CrdtDatabase.instance.query('''
      SELECT id, title, created_at, updated_at, is_title_generating
      FROM chats
      WHERE deleted_at IS NULL
      ORDER BY updated_at DESC
    ''');

    print('[ChatStorage] getAllChats found ${results.length} chats');
    if (results.isNotEmpty) {
      print('[ChatStorage] Chat IDs: ${results.map((r) => r['id']).toList()}');
    }

    return results.map((row) {
      return Chat(
        id: row['id'] as String,
        title: row['title'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
        isTitleGenerating: (row['is_title_generating'] as int) == 1,
      );
    }).toList();
  }

  /// Load a specific chat by ID
  Future<Chat?> getChat(String chatId) async {
    print('[ChatStorage] getChat called for: $chatId');
    print('[ChatStorage] CrdtDatabase instance: ${CrdtDatabase.instance}');
    print('[ChatStorage] CrdtDatabase nodeId: ${CrdtDatabase.instance.nodeId}');

    final results = await CrdtDatabase.instance.query('''
      SELECT id, title, created_at, updated_at, is_title_generating
      FROM chats
      WHERE id = ? AND deleted_at IS NULL
    ''', [chatId]);

    print('[ChatStorage] Query returned ${results.length} results');

    if (results.isEmpty) return null;

    final row = results.first;
    return Chat(
      id: row['id'] as String,
      title: row['title'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      isTitleGenerating: (row['is_title_generating'] as int) == 1,
    );
  }

  /// Search chats by title
  Future<List<Chat>> searchChats(String query) async {
    final results = await CrdtDatabase.instance.query('''
      SELECT id, title, created_at, updated_at, is_title_generating
      FROM chats
      WHERE title LIKE ? AND deleted_at IS NULL
      ORDER BY updated_at DESC
      LIMIT 50
    ''', ['%$query%']);

    return results.map((row) {
      return Chat(
        id: row['id'] as String,
        title: row['title'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
        isTitleGenerating: (row['is_title_generating'] as int) == 1,
      );
    }).toList();
  }

  /// Search messages by content
  Future<List<Message>> searchMessages(String query) async {
    final results = await CrdtDatabase.instance.query('''
      SELECT id, chat_id, content, is_user, created_at
      FROM messages
      WHERE content LIKE ? AND deleted_at IS NULL
      ORDER BY created_at DESC
      LIMIT 50
    ''', ['%$query%']);

    return results.map((row) {
      return Message(
        id: row['id'] as String,
        chatId: row['chat_id'] as String,
        content: row['content'] as String,
        isUser: (row['is_user'] as int) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      );
    }).toList();
  }

  /// Create a new chat
  Future<void> createChat(Chat chat) async {
    print('[ChatStorage] createChat called for: ${chat.id}');
    final deviceId = await DeviceIdService.instance.getDeviceId();
    print('[ChatStorage] deviceId: $deviceId');

    await CrdtDatabase.instance.execute('''
      INSERT OR REPLACE INTO chats (
        id, title, created_at, updated_at, is_title_generating, deleted_at, device_id, sync_version
      ) VALUES (?, ?, ?, ?, ?, NULL, ?, 1)
    ''', [
      chat.id,
      chat.title,
      chat.createdAt.millisecondsSinceEpoch,
      chat.updatedAt.millisecondsSinceEpoch,
      chat.isTitleGenerating ? 1 : 0,
      deviceId,
    ]);

    print('[ChatStorage] Chat ${chat.id} inserted into database');

    // Verify it was inserted
    final verifyResults = await CrdtDatabase.instance.query(
      'SELECT * FROM chats WHERE id = ?',
      [chat.id],
    );
    print('[ChatStorage] Verification query returned ${verifyResults.length} results');
    if (verifyResults.isNotEmpty) {
      print('[ChatStorage] Verified chat exists in DB: ${verifyResults.first}');
    }

    await AppBus.instance.emit(AppEvent.create(
      type: 'chat.created',
      appId: 'chat',
      metadata: {
        'chatId': chat.id,
        'title': chat.title,
      },
    ));

    print('[ChatStorage] chat.created event emitted for: ${chat.id}');
  }

  /// Update an existing chat
  Future<void> updateChat(Chat chat) async {
    final deviceId = await DeviceIdService.instance.getDeviceId();

    // Get current sync version
    final existing = await CrdtDatabase.instance.query('''
      SELECT sync_version FROM chats WHERE id = ?
    ''', [chat.id]);

    if (existing.isEmpty) return;

    final syncVersion = (existing.first['sync_version'] as int) + 1;

    await CrdtDatabase.instance.execute('''
      UPDATE chats
      SET title = ?, updated_at = ?, is_title_generating = ?, device_id = ?, sync_version = ?
      WHERE id = ?
    ''', [
      chat.title,
      chat.updatedAt.millisecondsSinceEpoch,
      chat.isTitleGenerating ? 1 : 0,
      deviceId,
      syncVersion,
      chat.id,
    ]);

    await AppBus.instance.emit(AppEvent.create(
      type: 'chat.updated',
      appId: 'chat',
      metadata: {
        'chatId': chat.id,
        'title': chat.title,
      },
    ));
  }

  /// Delete a chat (soft delete)
  Future<void> deleteChat(String chatId) async {
    final deviceId = await DeviceIdService.instance.getDeviceId();
    final now = DateTime.now();

    // Get current sync version
    final existing = await CrdtDatabase.instance.query('''
      SELECT sync_version FROM chats WHERE id = ?
    ''', [chatId]);

    if (existing.isEmpty) return;

    final syncVersion = (existing.first['sync_version'] as int) + 1;

    // Soft delete chat
    await CrdtDatabase.instance.execute('''
      UPDATE chats
      SET deleted_at = ?, updated_at = ?, device_id = ?, sync_version = ?
      WHERE id = ?
    ''', [
      now.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
      deviceId,
      syncVersion,
      chatId,
    ]);

    // Soft delete all messages in the chat
    await CrdtDatabase.instance.execute('''
      UPDATE messages
      SET deleted_at = ?, device_id = ?, sync_version = sync_version + 1
      WHERE chat_id = ? AND deleted_at IS NULL
    ''', [
      now.millisecondsSinceEpoch,
      deviceId,
      chatId,
    ]);

    await AppBus.instance.emit(AppEvent.create(
      type: 'chat.deleted',
      appId: 'chat',
      metadata: {'chatId': chatId},
    ));
  }

  /// Get all messages for a chat
  Future<List<Message>> getMessages(String chatId) async {
    final results = await CrdtDatabase.instance.query('''
      SELECT id, chat_id, content, is_user, created_at
      FROM messages
      WHERE chat_id = ? AND deleted_at IS NULL
      ORDER BY created_at ASC
    ''', [chatId]);

    return results.map((row) {
      return Message(
        id: row['id'] as String,
        chatId: row['chat_id'] as String,
        content: row['content'] as String,
        isUser: (row['is_user'] as int) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      );
    }).toList();
  }

  /// Create a new message
  Future<void> createMessage(Message message) async {
    final deviceId = await DeviceIdService.instance.getDeviceId();

    await CrdtDatabase.instance.execute('''
      INSERT OR REPLACE INTO messages (
        id, chat_id, content, is_user, created_at, deleted_at, device_id, sync_version
      ) VALUES (?, ?, ?, ?, ?, NULL, ?, 1)
    ''', [
      message.id,
      message.chatId,
      message.content,
      message.isUser ? 1 : 0,
      message.createdAt.millisecondsSinceEpoch,
      deviceId,
    ]);

    await AppBus.instance.emit(AppEvent.create(
      type: 'message.created',
      appId: 'chat',
      metadata: {
        'chatId': message.chatId,
        'messageId': message.id,
      },
    ));
  }

  /// Delete all messages in a chat (used when deleting a chat)
  Future<void> deleteMessages(String chatId) async {
    final deviceId = await DeviceIdService.instance.getDeviceId();
    final now = DateTime.now();

    await CrdtDatabase.instance.execute('''
      UPDATE messages
      SET deleted_at = ?, device_id = ?, sync_version = sync_version + 1
      WHERE chat_id = ? AND deleted_at IS NULL
    ''', [
      now.millisecondsSinceEpoch,
      deviceId,
      chatId,
    ]);
  }

  /// Dispose resources
  Future<void> dispose() async {
    // CRDT database is shared, don't close it
  }

  /// Reset for testing
  static void resetInstance() {
    _instance = null;
  }
}
