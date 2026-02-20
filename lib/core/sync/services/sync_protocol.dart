import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
    print('[Protocol] Sending handshake...');
    await send(SyncMessage(
      type: SyncMessageType.handshake,
      payload: {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'protocolVersion': 1,
      },
    ));
    print('[Protocol] Handshake sent, waiting for ACK...');

    // Wait for acknowledgment with extended timeout
    final ack = await messages
        .firstWhere((msg) => msg.type == SyncMessageType.handshakeAck)
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            print('[Protocol] ❌ Handshake ACK timeout!');
            throw TimeoutException('Handshake ACK timeout');
          },
        );

    print('[Protocol] Received handshake ACK');

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

    // Always send at least one batch, even if empty
    final totalBatches = entities.isEmpty ? 1 : (entities.length / batchSize).ceil();

    if (entities.isEmpty) {
      // Send empty batch
      await send(SyncMessage(
        type: SyncMessageType.syncData,
        payload: {
          'appId': appId,
          'entities': [],
          'batchIndex': 0,
          'totalBatches': 1,
        },
      ));
      return;
    }

    for (var i = 0; i < entities.length; i += batchSize) {
      final end = (i + batchSize < entities.length) ? i + batchSize : entities.length;
      final batch = entities.sublist(i, end);

      await send(SyncMessage(
        type: SyncMessageType.syncData,
        payload: {
          'appId': appId,
          'entities': batch,
          'batchIndex': i ~/ batchSize,
          'totalBatches': totalBatches,
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
    print('[Protocol] Sending blobRequest for ${hashes.length} hashes');
    await send(SyncMessage(
      type: SyncMessageType.blobRequest,
      payload: {
        'hashes': hashes,
      },
    ));
    print('[Protocol] blobRequest sent');
  }

  /// Send blob data by streaming from disk in chunks (base64-encoded)
  Future<void> sendBlobFromPath(String hash, String relativePath, String absolutePath) async {
    const chunkSize = 256 * 1024; // 256KB chunks
    final file = File(absolutePath);
    final fileSize = await file.length();
    final totalChunks = fileSize == 0 ? 1 : (fileSize / chunkSize).ceil();

    final raf = await file.open(mode: FileMode.read);
    try {
      for (var i = 0; i < totalChunks; i++) {
        final remaining = fileSize - (i * chunkSize);
        final bytesToRead = remaining < chunkSize ? remaining.toInt() : chunkSize;
        final chunk = bytesToRead > 0 ? await raf.read(bytesToRead) : Uint8List(0);

        await send(SyncMessage(
          type: SyncMessageType.blobData,
          payload: {
            'hash': hash,
            'relativePath': relativePath,
            'chunkIndex': i,
            'totalChunks': totalChunks,
            'data': base64Encode(chunk), // base64 instead of List<int> (3-4x less overhead)
          },
        ));
      }
    } finally {
      await raf.close();
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
      print('[SyncCoordinator] Sending syncRequest for appId: $appId');
      await _protocol.requestSync(appId, lastSyncTime);
      print('[SyncCoordinator] syncRequest sent, waiting for messages...');

      // Start listening for remote changes BEFORE sending ours (to avoid race condition)
      final remoteEntities = <Map<String, dynamic>>[];
      bool sendingOurData = false;
      List<Map<String, dynamic>>? localChanges;

      await for (final message in _protocol.messages.timeout(
        const Duration(seconds: 30),
        onTimeout: (sink) {
          print('[SyncCoordinator] ⚠️  Timeout waiting for messages');
          sink.close();
        },
      )) {
        print('[SyncCoordinator] Received message type: ${message.type}');

        // Send our data on first iteration (after we've started listening)
        if (!sendingOurData) {
          sendingOurData = true;
          print('[SyncCoordinator] Calling getChanges...');
          localChanges = await getChanges(lastSyncTime);
          entitiesSent = localChanges.length;
          print('[SyncCoordinator] Got $entitiesSent local changes, sending...');
          await _protocol.sendSyncData(appId, localChanges, waitForAck: false);
          print('[SyncCoordinator] Local changes sent');
        }

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
      print('[Sync] Waiting for syncData messages for appId: $appId');
      StreamSubscription? subscription;

      final completer = Completer<void>();

      subscription = _protocol.messages.timeout(
        const Duration(seconds: 30), // Increased timeout for debugging
        onTimeout: (sink) {
          print('[Sync] ⚠️  Timeout waiting for syncData! Received ${remoteEntities.length} entities');
          receivedAllData = true;
          sink.close();
        },
      ).listen(
        (message) async {
          print('[Sync] Received message type: ${message.type}');

          if (message.type == SyncMessageType.syncData) {
            if (message.payload['appId'] == appId) {
              final entities = (message.payload['entities'] as List)
                  .cast<Map<String, dynamic>>();
              print('[Sync] Received ${entities.length} entities in batch');
              remoteEntities.addAll(entities);

              // Acknowledge
              await _protocol.acknowledgeSync(message.payload['batchIndex'] as int);

              // Check if this was the last batch
              final batchIndex = message.payload['batchIndex'] as int;
              final totalBatches = message.payload['totalBatches'] as int;
              print('[Sync] Batch $batchIndex of $totalBatches');
              if (batchIndex == totalBatches - 1) {
                print('[Sync] ✅ Received all batches: ${remoteEntities.length} total entities');
                receivedAllData = true;
                // Don't cancel here - complete the completer instead
                completer.complete();
              }
            }
          } else if (message.type == SyncMessageType.syncAck) {
            print('[Sync] Received syncAck');
          } else if (message.type == SyncMessageType.handshake || message.type == SyncMessageType.handshakeAck) {
            print('[Sync] Ignoring ${message.type} (handled by outer loop)');
            // Ignore handshake messages - they're handled by the outer connection loop
          } else {
            print('[Sync] Unexpected message: ${message.type}, stopping');
            receivedAllData = true;
            completer.complete();
          }
        },
        onDone: () {
          print('[Sync] Subscription completed (onDone)');
          if (!completer.isCompleted) completer.complete();
        },
        onError: (error) {
          print('[Sync] Subscription error: $error');
          if (!completer.isCompleted) completer.complete();
        },
      );

      // Wait for either completion or timeout
      await completer.future.timeout(
        const Duration(seconds: 35),
        onTimeout: () {
          print('[Sync] Completer timeout!');
        },
      );

      print('[Sync] Cancelling subscription...');
      await subscription.cancel();
      print('[Sync] handleSyncRequest subscription canceled');

      // Apply remote changes
      await applyChanges(appId, remoteEntities);
    } catch (e) {
      await _protocol.sendError(e.toString());
    }
  }

  /// Sync blobs after metadata sync.
  /// Chunks are written to temp files incrementally (no full file in RAM).
  /// [storeBlob] receives the temp file path; caller must not delete it (syncBlobs cleans up).
  Future<void> syncBlobs(
    Future<List<String>> Function() getMissingHashes,
    Future<String?> Function(String hash) getAbsolutePathByHash,
    Future<String?> Function(String hash) getRelativePathByHash,
    Future<void> Function(String hash, String tempFilePath, String relativePath) storeBlob,
  ) async {
    final blobSinks = <String, IOSink>{};
    final blobTempPaths = <String, String>{};
    final blobRelPaths = <String, String>{};

    Future<void> cleanupTempFiles() async {
      for (final sink in blobSinks.values) {
        try { await sink.close(); } catch (_) {}
      }
      for (final path in blobTempPaths.values) {
        try { await File(path).delete(); } catch (_) {}
      }
      blobSinks.clear();
      blobTempPaths.clear();
      blobRelPaths.clear();
    }

    try {
      // Get list of hashes we need
      final neededHashes = await getMissingHashes();

      if (neededHashes.isEmpty) {
        print('[BlobSync] No blobs needed');
        return;
      }

      print('[BlobSync] Requesting ${neededHashes.length} blobs');
      await _protocol.requestBlobs(neededHashes);

      final receivedHashes = <String>{};
      final failedHashes = <String>{};

      await for (final message in _protocol.messages.timeout(
        const Duration(seconds: 120),
        onTimeout: (sink) {
          print('[BlobSync] ⚠️ Timeout! Received ${receivedHashes.length}/${neededHashes.length} blobs, ${failedHashes.length} failed');
          sink.close();
        },
      )) {
        if (message.type == SyncMessageType.blobData) {
          final hash = message.payload['hash'] as String;
          final relativePath = message.payload['relativePath'] as String;
          final chunkData = base64Decode(message.payload['data'] as String);

          // Open temp file on first chunk
          if (!blobSinks.containsKey(hash)) {
            final tempPath = '${Directory.systemTemp.path}/blob_${hash.substring(0, 16)}.tmp';
            blobTempPaths[hash] = tempPath;
            blobRelPaths[hash] = relativePath;
            blobSinks[hash] = File(tempPath).openWrite();
          }

          blobSinks[hash]!.add(chunkData);

        } else if (message.type == SyncMessageType.blobComplete) {
          final hash = message.payload['hash'] as String;
          final relativePath = blobRelPaths[hash] ?? (message.payload['relativePath'] as String? ?? '');
          final tempPath = blobTempPaths[hash];

          if (tempPath != null) {
            // Flush and close the sink before reading
            await blobSinks[hash]?.flush();
            await blobSinks[hash]?.close();
            blobSinks.remove(hash);

            try {
              await storeBlob(hash, tempPath, relativePath);
              print('[BlobSync] Received blob: $hash ($relativePath)');
            } finally {
              try { await File(tempPath).delete(); } catch (_) {}
              blobTempPaths.remove(hash);
              blobRelPaths.remove(hash);
            }
          }

          receivedHashes.add(hash);
          print('[BlobSync] Progress: ${receivedHashes.length}/${neededHashes.length} blobs received');
          if (receivedHashes.length >= neededHashes.length) {
            print('[BlobSync] ✅ All blobs received!');
            break;
          }
        } else if (message.type == SyncMessageType.error) {
          final errorType = message.payload['type'] as String?;
          if (errorType == 'blob_not_found') {
            final hash = message.payload['hash'] as String;
            print('[BlobSync] ⚠️ Blob not available on remote: $hash');
            failedHashes.add(hash);
            receivedHashes.add(hash);

            print('[BlobSync] Progress: ${receivedHashes.length}/${neededHashes.length} (${failedHashes.length} unavailable)');
            if (receivedHashes.length >= neededHashes.length) {
              print('[BlobSync] ✅ Sync complete (some blobs unavailable)');
              break;
            }
          }
        }
      }

      if (failedHashes.isNotEmpty) {
        print('[BlobSync] ⚠️ ${failedHashes.length} blobs were not available on remote device');
      }

      print('[BlobSync] Blob sync completed. Received ${receivedHashes.length} blobs');
    } catch (e) {
      print('[BlobSync] Error: $e');
    } finally {
      await cleanupTempFiles();
    }
  }

  /// Handle blob requests (responder side) — streams files from disk, no full file in RAM
  Future<void> handleBlobRequest(
    SyncMessage request,
    Future<String?> Function(String hash) getAbsolutePathByHash,
    Future<String?> Function(String hash) getRelativePathByHash,
  ) async {
    try {
      final hashes = (request.payload['hashes'] as List).cast<String>();

      print('[BlobSync] Received request for ${hashes.length} blobs');
      print('[BlobSync] Hashes: $hashes');

      int sentCount = 0;
      int notFoundCount = 0;

      for (final hash in hashes) {
        print('[BlobSync] Looking up blob: $hash');
        final absolutePath = await getAbsolutePathByHash(hash);
        final relativePath = await getRelativePathByHash(hash);

        if (absolutePath != null && relativePath != null) {
          final fileSize = await File(absolutePath).length();
          print('[BlobSync] Sending blob: $hash ($relativePath, $fileSize bytes)');
          await _protocol.sendBlobFromPath(hash, relativePath, absolutePath);
          print('[BlobSync] Blob sent: $hash');
          sentCount++;
        } else {
          print('[BlobSync] ⚠️ Blob not found: $hash');
          await _protocol.send(SyncMessage(
            type: SyncMessageType.error,
            payload: {
              'error': 'Blob not found: $hash',
              'hash': hash,
              'type': 'blob_not_found',
            },
          ));
          notFoundCount++;
        }
      }
      print('[BlobSync] Sent $sentCount blobs, $notFoundCount not found');
    } catch (e) {
      print('[BlobSync] Error sending blobs: $e');
    }
  }
}
