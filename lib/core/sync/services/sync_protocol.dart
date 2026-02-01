import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../models/sync_result.dart';
import 'connection_service.dart';

/// Message types for the sync protocol
enum SyncMessageType {
  handshake,
  handshakeAck,
  syncRequest,
  syncData,
  syncAck,
  blobManifest,  // List of available blob hashes
  blobRequest,   // Request specific blobs
  blobData,      // Blob chunk
  blobComplete,  // Blob transfer complete
  error,
}

/// A message in the sync protocol
class SyncMessage {
  final SyncMessageType type;
  final Map<String, dynamic> payload;

  SyncMessage({
    required this.type,
    required this.payload,
  });

  /// Serialize to bytes
  Uint8List toBytes() {
    final json = {
      'type': type.name,
      'payload': payload,
    };
    final jsonString = jsonEncode(json);
    final jsonBytes = utf8.encode(jsonString);

    // Prefix with length (4 bytes, big-endian)
    final buffer = BytesBuilder();
    buffer.add([
      (jsonBytes.length >> 24) & 0xFF,
      (jsonBytes.length >> 16) & 0xFF,
      (jsonBytes.length >> 8) & 0xFF,
      jsonBytes.length & 0xFF,
    ]);
    buffer.add(jsonBytes);

    return buffer.toBytes();
  }

  /// Deserialize from bytes
  static SyncMessage? tryParse(Uint8List bytes) {
    try {
      final jsonString = utf8.decode(bytes);
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      final typeName = json['type'] as String;
      final type = SyncMessageType.values.firstWhere(
        (t) => t.name == typeName,
        orElse: () => SyncMessageType.error,
      );

      return SyncMessage(
        type: type,
        payload: json['payload'] as Map<String, dynamic>,
      );
    } catch (e) {
      return null;
    }
  }
}

/// Handles the sync protocol for exchanging data between devices
class SyncProtocol {
  final SyncConnection _connection;
  final StreamController<SyncMessage> _messageController =
      StreamController<SyncMessage>.broadcast();
  StreamSubscription<Uint8List>? _dataSubscription;

  final List<int> _buffer = [];
  int? _expectedLength;

  SyncProtocol(this._connection) {
    _dataSubscription = _connection.dataStream.listen(_handleIncomingData);
  }

  void _handleIncomingData(Uint8List data) {
    _buffer.addAll(data);

    while (true) {
      // If we don't know the expected length, try to read it
      if (_expectedLength == null) {
        if (_buffer.length < 4) break;

        _expectedLength = (_buffer[0] << 24) |
            (_buffer[1] << 16) |
            (_buffer[2] << 8) |
            _buffer[3];

        _buffer.removeRange(0, 4);
      }

      // Check if we have the complete message
      if (_buffer.length < _expectedLength!) break;

      // Extract and parse message
      final messageBytes = Uint8List.fromList(_buffer.sublist(0, _expectedLength!));
      _buffer.removeRange(0, _expectedLength!);
      _expectedLength = null;

      final message = SyncMessage.tryParse(messageBytes);
      if (message != null) {
        if (message.type == SyncMessageType.error) {
        } else {
        }
        _messageController.add(message);
      } else {
      }
    }
  }

  /// Stream of incoming messages
  Stream<SyncMessage> get messages => _messageController.stream;

  /// Send a message
  Future<void> send(SyncMessage message) async {
    await _connection.send(message.toBytes());
  }

  /// Perform handshake
  Future<void> handshake(String deviceId, String deviceName) async {
    await send(SyncMessage(
      type: SyncMessageType.handshake,
      payload: {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'protocolVersion': 1,
      },
    ));

    // Wait for acknowledgment with extended timeout
    final ack = await messages
        .firstWhere((msg) => msg.type == SyncMessageType.handshakeAck)
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('Handshake ACK timeout');
          },
        );


    if (ack.payload['status'] != 'ok') {
      throw Exception('Handshake failed: ${ack.payload['error']}');
    }
  }

  /// Request sync for an app
  Future<void> requestSync(String appId, DateTime? lastSyncTime) async {
    await send(SyncMessage(
      type: SyncMessageType.syncRequest,
      payload: {
        'appId': appId,
        'lastSyncTime': lastSyncTime?.toIso8601String(),
      },
    ));
  }

  /// Send sync data (entities)
  Future<void> sendSyncData(
    String appId,
    List<Map<String, dynamic>> entities, {
    bool waitForAck = true,
  }) async {
    // Send in batches to avoid large messages
    const batchSize = 100;

    for (var i = 0; i < entities.length; i += batchSize) {
      final end = (i + batchSize < entities.length) ? i + batchSize : entities.length;
      final batch = entities.sublist(i, end);

      await send(SyncMessage(
        type: SyncMessageType.syncData,
        payload: {
          'appId': appId,
          'entities': batch,
          'batchIndex': i ~/ batchSize,
          'totalBatches': (entities.length / batchSize).ceil(),
        },
      ));

      // Wait for acknowledgment with extended timeout (optional)
      if (waitForAck) {
        await messages
            .firstWhere((msg) => msg.type == SyncMessageType.syncAck)
            .timeout(const Duration(seconds: 60));
      }
    }
  }

  /// Acknowledge sync data
  Future<void> acknowledgeSync(int batchIndex) async {
    await send(SyncMessage(
      type: SyncMessageType.syncAck,
      payload: {
        'batchIndex': batchIndex,
        'status': 'ok',
      },
    ));
  }

  /// Send error message
  Future<void> sendError(String error) async {
    await send(SyncMessage(
      type: SyncMessageType.error,
      payload: {
        'error': error,
      },
    ));
  }

  /// Send blob manifest (list of available hashes)
  Future<void> sendBlobManifest(List<String> hashes) async {
    await send(SyncMessage(
      type: SyncMessageType.blobManifest,
      payload: {
        'hashes': hashes,
      },
    ));
  }

  /// Request blobs by hash
  Future<void> requestBlobs(List<String> hashes) async {
    await send(SyncMessage(
      type: SyncMessageType.blobRequest,
      payload: {
        'hashes': hashes,
      },
    ));
  }

  /// Send blob data in chunks
  Future<void> sendBlob(String hash, String relativePath, List<int> data) async {
    const chunkSize = 64 * 1024; // 64KB chunks
    final totalChunks = (data.length / chunkSize).ceil();

    for (var i = 0; i < totalChunks; i++) {
      final start = i * chunkSize;
      final end = (start + chunkSize < data.length) ? start + chunkSize : data.length;
      final chunk = data.sublist(start, end);

      await send(SyncMessage(
        type: SyncMessageType.blobData,
        payload: {
          'hash': hash,
          'relativePath': relativePath,
          'chunkIndex': i,
          'totalChunks': totalChunks,
          'data': chunk,
        },
      ));
    }

    // Send completion message
    await send(SyncMessage(
      type: SyncMessageType.blobComplete,
      payload: {
        'hash': hash,
        'relativePath': relativePath,
      },
    ));
  }

  /// Dispose
  Future<void> dispose() async {
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    await _messageController.close();
  }
}

/// High-level sync coordinator
class SyncCoordinator {
  final SyncProtocol _protocol;

  SyncCoordinator(this._protocol);

  /// Sync an app (as initiator)
  Future<SyncResult> syncApp(
    String appId,
    DateTime? lastSyncTime,
    Future<List<Map<String, dynamic>>> Function(DateTime? since) getChanges,
    Future<void> Function(List<Map<String, dynamic>> entities) applyChanges,
  ) async {
    final startTime = DateTime.now();
    var entitiesSent = 0;
    var entitiesReceived = 0;

    try {
      // Request sync
      await _protocol.requestSync(appId, lastSyncTime);

      // Get local changes
      final localChanges = await getChanges(lastSyncTime);
      entitiesSent = localChanges.length;

      // Send local changes (don't wait for ACK to avoid consuming messages from stream)
      await _protocol.sendSyncData(appId, localChanges, waitForAck: false);

      // Receive remote changes
      final remoteEntities = <Map<String, dynamic>>[];

      await for (final message in _protocol.messages.timeout(
        const Duration(seconds: 30),
        onTimeout: (sink) {
          sink.close();
        },
      )) {
        if (message.type == SyncMessageType.syncData) {
          if (message.payload['appId'] == appId) {
            final entities = (message.payload['entities'] as List)
                .cast<Map<String, dynamic>>();
            remoteEntities.addAll(entities);

            // Acknowledge
            await _protocol.acknowledgeSync(message.payload['batchIndex'] as int);

            // Check if this was the last batch
            final batchIndex = message.payload['batchIndex'] as int;
            final totalBatches = message.payload['totalBatches'] as int;
            if (batchIndex == totalBatches - 1) {
              break;
            }
          }
        } else if (message.type == SyncMessageType.error) {
          throw Exception('Sync error: ${message.payload['error']}');
        }
      }

      entitiesReceived = remoteEntities.length;

      // Apply remote changes
      await applyChanges(remoteEntities);

      return SyncResult.success(
        entitiesSent: entitiesSent,
        entitiesReceived: entitiesReceived,
        startedAt: startTime,
      );
    } catch (e) {
      return SyncResult.failure(
        error: e.toString(),
        startedAt: startTime,
      );
    }
  }

  /// Handle sync as responder
  Future<void> handleSyncRequest(
    SyncMessage request,
    Future<List<Map<String, dynamic>>> Function(String appId, DateTime? since) getChanges,
    Future<void> Function(String appId, List<Map<String, dynamic>> entities) applyChanges,
  ) async {
    try {
      final appId = request.payload['appId'] as String;
      final lastSyncTimeStr = request.payload['lastSyncTime'] as String?;
      final lastSyncTime = lastSyncTimeStr != null
          ? DateTime.parse(lastSyncTimeStr)
          : null;


      // Get and send local changes FIRST (before receiving)
      final localChanges = await getChanges(appId, lastSyncTime);
      await _protocol.sendSyncData(appId, localChanges, waitForAck: false);

      // Now listen for incoming data
      final remoteEntities = <Map<String, dynamic>>[];


      // Use a subscription instead of await-for to have better control
      bool receivedAllData = false;
      final subscription = _protocol.messages.timeout(
        const Duration(seconds: 5),
        onTimeout: (sink) {
          receivedAllData = true;
          sink.close();
        },
      ).listen((message) async {

        if (message.type == SyncMessageType.syncData) {
          if (message.payload['appId'] == appId) {
            final entities = (message.payload['entities'] as List)
                .cast<Map<String, dynamic>>();
            remoteEntities.addAll(entities);

            // Acknowledge
            await _protocol.acknowledgeSync(message.payload['batchIndex'] as int);

            // Check if this was the last batch
            final batchIndex = message.payload['batchIndex'] as int;
            final totalBatches = message.payload['totalBatches'] as int;
            if (batchIndex == totalBatches - 1) {
              receivedAllData = true;
            }
          }
        } else if (message.type == SyncMessageType.syncAck) {
        } else {
          receivedAllData = true;
        }
      });

      // Wait for completion or timeout
      await subscription.asFuture().catchError((_) => null);
      await subscription.cancel();

      // Apply remote changes
      await applyChanges(appId, remoteEntities);
    } catch (e) {
      await _protocol.sendError(e.toString());
    }
  }

  /// Sync blobs after metadata sync
  Future<void> syncBlobs(
    Future<List<String>> Function() getMissingHashes,
    Future<List<int>?> Function(String hash) getBlobByHash,
    Future<String?> Function(String hash) getRelativePathByHash,
    Future<void> Function(String hash, List<int> data, String relativePath) storeBlob,
  ) async {
    try {
      // Get list of hashes we need
      final neededHashes = await getMissingHashes();

      if (neededHashes.isEmpty) {
        print('[BlobSync] No blobs needed');
        return;
      }

      print('[BlobSync] Requesting ${neededHashes.length} blobs');
      await _protocol.requestBlobs(neededHashes);

      // Listen for incoming blobs
      final blobBuffers = <String, List<List<int>>>{};
      final blobMetadata = <String, Map<String, dynamic>>{};

      await for (final message in _protocol.messages.timeout(
        const Duration(seconds: 60),
        onTimeout: (sink) => sink.close(),
      )) {
        if (message.type == SyncMessageType.blobData) {
          final hash = message.payload['hash'] as String;
          final relativePath = message.payload['relativePath'] as String;
          final chunkIndex = message.payload['chunkIndex'] as int;
          final data = (message.payload['data'] as List).cast<int>();

          blobBuffers.putIfAbsent(hash, () => []);
          blobMetadata[hash] = {'relativePath': relativePath};

          // Ensure we have space for this chunk
          while (blobBuffers[hash]!.length <= chunkIndex) {
            blobBuffers[hash]!.add([]);
          }
          blobBuffers[hash]![chunkIndex] = data;

        } else if (message.type == SyncMessageType.blobComplete) {
          final hash = message.payload['hash'] as String;
          final relativePath = blobMetadata[hash]?['relativePath'] as String;

          // Assemble chunks
          final completeBlob = <int>[];
          for (final chunk in blobBuffers[hash]!) {
            completeBlob.addAll(chunk);
          }

          // Store blob
          await storeBlob(hash, completeBlob, relativePath);
          print('[BlobSync] Received blob: $hash ($relativePath)');

          // Clean up
          blobBuffers.remove(hash);
          blobMetadata.remove(hash);

          // Check if all blobs received
          if (blobBuffers.isEmpty) {
            break;
          }
        }
      }
    } catch (e) {
      print('[BlobSync] Error: $e');
    }
  }

  /// Handle blob requests (responder side)
  Future<void> handleBlobRequest(
    SyncMessage request,
    Future<List<int>?> Function(String hash) getBlobByHash,
    Future<String?> Function(String hash) getRelativePathByHash,
  ) async {
    try {
      final hashes = (request.payload['hashes'] as List).cast<String>();

      print('[BlobSync] Sending ${hashes.length} blobs');

      for (final hash in hashes) {
        final blob = await getBlobByHash(hash);
        final relativePath = await getRelativePathByHash(hash);

        if (blob != null && relativePath != null) {
          await _protocol.sendBlob(hash, relativePath, blob);
        }
      }
    } catch (e) {
      print('[BlobSync] Error sending blobs: $e');
    }
  }
}
