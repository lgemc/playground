import 'dart:async';
import '../models/device.dart';
import '../models/sync_conflict.dart';
import '../models/sync_result.dart';
import '../database/sync_database.dart';
import 'device_discovery_service.dart';
import 'device_id_service.dart';
import 'connection_service.dart';
import 'socket_connection.dart';
import 'sync_protocol.dart';
import '../../../apps/file_system/services/file_system_storage.dart';

/// Callback for getting changes from an app
typedef GetChangesCallback = Future<List<Map<String, dynamic>>> Function(
  String appId,
  DateTime? since,
);

/// Callback for applying changes to an app
typedef ApplyChangesCallback = Future<void> Function(
  String appId,
  List<Map<String, dynamic>> entities,
);

/// Main orchestrator for device-to-device sync operations
class DeviceSyncService {
  final DeviceIdService _deviceIdService;
  final DeviceDiscoveryService _discoveryService;
  final ConnectionService _connectionService;
  final SyncDatabase _syncDatabase;

  final StreamController<SyncConflict> _conflictsController =
      StreamController<SyncConflict>.broadcast();

  final Map<String, SyncSession> _activeSessions = {};

  GetChangesCallback? _getChangesCallback;
  ApplyChangesCallback? _applyChangesCallback;

  DeviceSyncService({
    required DeviceIdService deviceIdService,
    required SyncDatabase syncDatabase,
  })  : _deviceIdService = deviceIdService,
        _syncDatabase = syncDatabase,
        _discoveryService = DeviceDiscoveryService(deviceIdService),
        _connectionService = SocketConnectionService();

  /// Get the discovery service
  DeviceDiscoveryService get discoveryService => _discoveryService;

  /// Set the callback for getting changes from apps
  void setGetChangesCallback(GetChangesCallback callback) {
    _getChangesCallback = callback;
  }

  /// Set the callback for applying changes to apps
  void setApplyChangesCallback(ApplyChangesCallback callback) {
    _applyChangesCallback = callback;
  }

  /// Start the sync service (discovery and listening for connections)
  Future<void> start() async {
    // Get this device's info
    final myDeviceId = await _deviceIdService.getDeviceId();
    final myDeviceName = await _deviceIdService.getDeviceName();

    // Set device info for connection service if it's SocketConnectionService
    final connectionService = _connectionService;
    if (connectionService is SocketConnectionService) {
      connectionService.setDeviceInfo(myDeviceId, myDeviceName);
    }

    // Start listening for incoming connections
    await _connectionService.startListening(7654);

    // Set the actual port in discovery service
    if (connectionService is SocketConnectionService) {
      final actualPort = connectionService.listeningPort;
      if (actualPort != null) {
        _discoveryService.setSyncPort(actualPort);
      }
    }

    // Start advertising this device
    await _discoveryService.startAdvertising();

    // Start discovering other devices
    await _discoveryService.startDiscovery();

    // Handle incoming connections with error handling
    print('[Sync] Setting up incoming connection listener...');
    _connectionService.incomingConnections.listen(
      _handleIncomingConnection,
      onError: (error, stackTrace) {
        print('[Sync] ❌ Error in incoming connection listener: $error');
        print('[Sync] Stack trace: $stackTrace');
      },
      onDone: () {
        print('[Sync] ⚠️  Incoming connection stream closed!');
      },
      cancelOnError: false, // Keep listening even if one connection errors
    );
    print('[Sync] ✅ Incoming connection listener active');
  }

  /// Stop the sync service
  Future<void> stop() async {
    await _discoveryService.stopDiscovery();
    await _discoveryService.stopAdvertising();
    await _connectionService.stopListening();

    // Close all active sessions
    for (final session in _activeSessions.values) {
      await session.close();
    }
    _activeSessions.clear();
  }

  /// Discover devices on the local network
  Future<List<Device>> discoverDevices() async {
    return _discoveryService.devices;
  }

  /// Stream of discovered devices
  Stream<List<Device>> get devicesStream => _discoveryService.devicesStream;

  /// Connect to a device
  Future<SyncSession> connectToDevice(Device device) async {
    // Always create a new connection for now (session reuse has issues with timeout)
    // TODO: Implement proper connection health checking

    print('[Sync] Establishing NEW connection to ${device.ipAddress}:${device.port}');

    // Establish connection
    final connection = await _connectionService.connectToDevice(device);

    print('[Sync] Connection established!');

    // Create session
    final session = SyncSession(
      device: device,
      connection: connection,
    );

    _activeSessions[device.id] = session;

    return session;
  }

  /// Sync a specific app with a device
  Future<SyncResult> syncApp(String appId, Device device) async {
    print('[Sync] syncApp called with appId: "$appId"');

    if (_getChangesCallback == null || _applyChangesCallback == null) {
      throw StateError(
        'Callbacks not set. Call setGetChangesCallback and setApplyChangesCallback first.',
      );
    }

    try {
      print('[Sync] Connecting to device...');
      // Connect to device
      final session = await connectToDevice(device);
      print('[Sync] Connected! Creating protocol handler...');

      // Create protocol handler
      final protocol = SyncProtocol(session.connection);
      print('[Sync] Protocol created. Performing handshake...');

      // Perform handshake
      final myDeviceId = await _deviceIdService.getDeviceId();
      await protocol.handshake(myDeviceId, 'My Device');
      print('[Sync] ✅ Handshake completed!');

      // Get last sync time for this app with this device
      final lastSyncTime = await _getLastSyncTime(appId, device.id);
      print('[Sync] Last sync time: $lastSyncTime');

      // Create sync coordinator
      print('[Sync] Creating coordinator...');
      final coordinator = SyncCoordinator(protocol);

      // Perform metadata sync
      final result = await coordinator.syncApp(
        appId,
        lastSyncTime,
        (since) => _getChangesCallback!(appId, since),
        (entities) => _applyChangesCallback!(appId, entities),
      );

      // Update last sync time
      if (result.success) {
        await _updateLastSyncTime(appId, device.id);
      }

      // Clean up deleted folders and ensure physical folders exist after metadata sync
      if (appId == 'crdt_database' && result.success) {
        print('[Sync] Cleaning up deleted folders...');
        try {
          await FileSystemStorage.instance.cleanupDeletedFolders();
          print('[Sync] ✅ Deleted folders cleaned up');
        } catch (e) {
          print('[Sync] ❌ Error cleaning deleted folders: $e');
        }

        print('[Sync] Ensuring physical folders exist...');
        try {
          await FileSystemStorage.instance.ensurePhysicalFoldersExist();
          print('[Sync] ✅ Physical folders ensured');
        } catch (e) {
          print('[Sync] ❌ Error ensuring physical folders: $e');
        }
      }

      // Perform bidirectional blob sync for file_system when syncing crdt_database
      if (appId == 'crdt_database' && result.success) {
        // Step 1: Wait for responder's blob request (if any)
        print('[Sync] Step 1: Waiting for responder blob request...');
        try {
          bool receivedResponderRequest = false;
          await for (final message in protocol.messages.timeout(
            const Duration(seconds: 10),
            onTimeout: (sink) {
              print('[Sync] No blob request from responder (timeout after 10s)');
              sink.close();
            },
          )) {
            print('[Sync] Initiator received message: ${message.type}');

            if (message.type == SyncMessageType.blobRequest) {
              print('[Sync] Received blob request from responder, handling...');
              final storage = FileSystemStorage.instance;

              // Try to handle as file blob first, then derivative blob
              await coordinator.handleBlobRequest(
                message,
                (hash) async {
                  // Try file first, then derivative
                  final filePath = await storage.getAbsolutePathByHash(hash);
                  if (filePath != null) return filePath;
                  return await storage.getDerivativeAbsolutePathByHash(hash);
                },
                (hash) async {
                  // Try file first, then derivative
                  final relPath = await storage.getRelativePathByHash(hash);
                  if (relPath != null) return relPath;
                  return await storage.getDerivativeRelativePathByHash(hash);
                },
              );
              print('[Sync] Sent blobs to responder');
              receivedResponderRequest = true;
              break;
            } else if (message.type == SyncMessageType.syncData ||
                       message.type == SyncMessageType.syncAck) {
              print('[Sync] Ignoring ${message.type} (stale message)');
            } else {
              print('[Sync] Unexpected message: ${message.type}, stopping');
              break;
            }
          }

          if (!receivedResponderRequest) {
            print('[Sync] Responder did not need any blobs');
          }
        } catch (e) {
          print('[Sync] Error handling responder blob request: $e');
        }

        // Step 2: Request our own file blobs from responder
        print('[Sync] Step 2: Checking if initiator needs file blobs...');
        await _syncFileBlobs(coordinator);
        print('[Sync] File blob sync completed');

        // Step 3: Sync derivative blobs (both directions)
        print('[Sync] Step 3: Starting derivative blob sync...');

        // First, regenerate missing hashes for existing derivatives
        print('[Sync] Regenerating missing derivative hashes...');
        await FileSystemStorage.instance.regenerateDerivativeHashes();

        await _syncDerivativeBlobs(coordinator);
        print('[Sync] Derivative blob sync completed');

        print('[Sync] Bidirectional blob sync (files + derivatives) completed');
      }

      // Clean up
      await protocol.dispose();

      return result;
    } catch (e) {
      return SyncResult.failure(
        error: e.toString(),
      );
    }
  }

  /// Sync file blobs after metadata sync (initiator side)
  Future<void> _syncFileBlobs(SyncCoordinator coordinator) async {
    try {
      final storage = FileSystemStorage.instance;

      await coordinator.syncBlobs(
        () => storage.getMissingBlobHashes(),
        (hash) => storage.getAbsolutePathByHash(hash),
        (hash) => storage.getRelativePathByHash(hash),
        (hash, tempFilePath, relativePath) => storage.storeBlobByPath(hash, tempFilePath, relativePath),
      );
    } catch (e) {
      print('[Sync] Blob sync error: $e');
    }
  }

  /// Sync derivative blobs after metadata sync (initiator side)
  Future<void> _syncDerivativeBlobs(SyncCoordinator coordinator) async {
    try {
      final storage = FileSystemStorage.instance;

      await coordinator.syncBlobs(
        () => storage.getMissingDerivativeHashes(),
        (hash) => storage.getDerivativeAbsolutePathByHash(hash),
        (hash) => storage.getDerivativeRelativePathByHash(hash),
        (hash, tempFilePath, relativePath) => storage.storeDerivativeBlob(hash, tempFilePath, relativePath),
      );
    } catch (e) {
      print('[Sync] Derivative blob sync error: $e');
    }
  }


  /// Sync all apps with a device
  Future<List<SyncResult>> syncAllApps(Device device, List<String> appIds) async {
    final results = <SyncResult>[];

    for (final appId in appIds) {
      final result = await syncApp(appId, device);
      results.add(result);

      // Stop if any sync fails
      if (!result.success) break;
    }

    return results;
  }

  /// Handle incoming connection from another device
  Future<void> _handleIncomingConnection(SyncConnection connection) async {
    final timestamp = DateTime.now().toIso8601String();
    print('[Sync] 📥 [$timestamp] NEW incoming connection from ${connection.device.ipAddress}');

    if (_getChangesCallback == null || _applyChangesCallback == null) {
      print('[Sync] ❌ Callbacks not set, closing connection');
      await connection.close();
      return;
    }

    try {
      final protocol = SyncProtocol(connection);
      final coordinator = SyncCoordinator(protocol);

      print('[Sync] Listening for messages...');

      try {
        String? syncedAppId;
        bool handshakeCompleted = false;

        await for (final message in protocol.messages) {
          print('[Sync] Received message: ${message.type}');
          print('[Sync] Is handshake? ${message.type == SyncMessageType.handshake}');
          print('[Sync] handshakeCompleted? $handshakeCompleted');
          print('[Sync] syncedAppId: $syncedAppId');

          if (message.type == SyncMessageType.handshake) {
            if (!handshakeCompleted) {
              print('[Sync] ✅ Handshake received');
              handshakeCompleted = true;
            } else {
              print('[Sync] ⚠️  Duplicate handshake (connection reused)');
            }
            // Always send ACK (connection might be reused)
            await protocol.send(SyncMessage(
              type: SyncMessageType.handshakeAck,
              payload: {'status': 'ok'},
            ));
            print('[Sync] Sent handshake ack');
            continue;
          }

          if (message.type == SyncMessageType.syncRequest) {
            syncedAppId = message.payload['appId'] as String;
            print('[Sync] Processing syncRequest for appId: $syncedAppId');
            await coordinator.handleSyncRequest(
              message,
              (appId, since) => _getChangesCallback!(appId, since),
              (appId, entities) => _applyChangesCallback!(appId, entities),
            );
            print('[Sync] ✅ handleSyncRequest completed');

            // Clean up deleted folders and ensure physical folders exist after metadata sync
            if (syncedAppId == 'crdt_database') {
              print('[Sync] Cleaning up deleted folders...');
              try {
                await FileSystemStorage.instance.cleanupDeletedFolders();
                print('[Sync] ✅ Deleted folders cleaned up');
              } catch (e) {
                print('[Sync] ❌ Error cleaning deleted folders: $e');
              }

              print('[Sync] Ensuring physical folders exist...');
              try {
                await FileSystemStorage.instance.ensurePhysicalFoldersExist();
                print('[Sync] ✅ Physical folders ensured');
              } catch (e) {
                print('[Sync] ❌ Error ensuring physical folders: $e');
              }
            }

            // Don't break - connection stays open for more syncs or blob requests
            if (syncedAppId == 'crdt_database') {
              print('[Sync] Metadata sync done, checking if responder needs file blobs...');

              // Perform file blob sync using coordinator
              final storage = FileSystemStorage.instance;
              final neededFileHashes = await storage.getMissingBlobHashes();
              if (neededFileHashes.isNotEmpty) {
                print('[Sync] Responder needs ${neededFileHashes.length} file blobs, starting sync...');
                try {
                  await coordinator.syncBlobs(
                    () => storage.getMissingBlobHashes(),
                    (hash) => storage.getAbsolutePathByHash(hash),
                    (hash) => storage.getRelativePathByHash(hash),
                    (hash, tempFilePath, relativePath) => storage.storeBlobByPath(hash, tempFilePath, relativePath),
                  );
                  print('[Sync] Responder file blob sync completed successfully');
                } catch (e) {
                  print('[Sync] Responder file blob sync error: $e');
                }
              } else {
                print('[Sync] Responder has all file blobs');
              }

              // Perform derivative blob sync
              print('[Sync] Checking if responder needs derivative blobs...');

              // First regenerate missing hashes
              print('[Sync] Regenerating missing derivative hashes...');
              await storage.regenerateDerivativeHashes();

              final neededDerivativeHashes = await storage.getMissingDerivativeHashes();
              if (neededDerivativeHashes.isNotEmpty) {
                print('[Sync] Responder needs ${neededDerivativeHashes.length} derivative blobs, starting sync...');
                try {
                  await coordinator.syncBlobs(
                    () => storage.getMissingDerivativeHashes(),
                    (hash) => storage.getDerivativeAbsolutePathByHash(hash),
                    (hash) => storage.getDerivativeRelativePathByHash(hash),
                    (hash, tempFilePath, relativePath) => storage.storeDerivativeBlob(hash, tempFilePath, relativePath),
                  );
                  print('[Sync] Responder derivative blob sync completed successfully');
                } catch (e) {
                  print('[Sync] Responder derivative blob sync error: $e');
                }
              } else {
                print('[Sync] Responder has all derivative blobs');
              }

              // After blob sync, continue listening for more requests
              print('[Sync] Responder ready for more messages...');
            } else {
              print('[Sync] Sync done, ready for next sync request...');
            }
          } else if (message.type == SyncMessageType.blobRequest) {
            print('[Sync] Received blobRequest! syncedAppId=$syncedAppId');
            if (syncedAppId != 'crdt_database') {
              print('[Sync] ⚠️ Ignoring blob request for non-crdt_database app');
              continue;
            }
            print('[Sync] Processing blob request...');
            final storage = FileSystemStorage.instance;

            // Try to handle as file blob first, then derivative blob
            await coordinator.handleBlobRequest(
              message,
              (hash) async {
                // Try file first, then derivative
                final filePath = await storage.getAbsolutePathByHash(hash);
                if (filePath != null) return filePath;
                return await storage.getDerivativeAbsolutePathByHash(hash);
              },
              (hash) async {
                // Try file first, then derivative
                final relPath = await storage.getRelativePathByHash(hash);
                if (relPath != null) return relPath;
                return await storage.getDerivativeRelativePathByHash(hash);
              },
            );
            print('[Sync] Blob request handled, ready for next sync...');
            // Don't break - keep connection alive for more syncs
          } else {
            print('[Sync] ⚠️ Unhandled message type: ${message.type}');
          }
        }
        print('[Sync] Message loop ended');
      } catch (e) {
        print('[Sync] Error in incoming connection handler: $e');
      } finally {
        // Always clean up
        print('[Sync] Cleaning up connection');
        await protocol.dispose();
        print('[Sync] About to close connection');
        await connection.close();
        print('[Sync] Connection closed');
      }
    } catch (e) {
      print('[Sync] Error in _handleIncomingConnection: $e');
      await connection.close();
    }
    print('[Sync] _handleIncomingConnection ended');
  }

  /// Get the last sync time for an app with a device
  Future<DateTime?> _getLastSyncTime(String appId, String deviceId) async {
    final state = await _syncDatabase.getSyncState(deviceId, appId);
    return state?.lastSyncAt;
  }

  /// Update the last sync time for an app with a device
  Future<void> _updateLastSyncTime(String appId, String deviceId) async {
    await _syncDatabase.upsertSyncState(
      SyncStateCompanion.insert(
        appId: appId,
        deviceId: deviceId,
        lastEntityId: '',
        lastSyncAt: DateTime.now(),
        lastSyncVersion: 0,
      ),
    );
  }

  /// Get last sync times for all apps
  Future<Map<String, DateTime>> getLastSyncTimes() async {
    final states = await _syncDatabase.getAllSyncStates();

    final result = <String, DateTime>{};
    for (final state in states) {
      result[state.appId] = state.lastSyncAt;
    }

    return result;
  }

  /// Stream of conflicts that need resolution
  Stream<SyncConflict> get conflicts => _conflictsController.stream;

  /// Resolve a conflict manually
  Future<void> resolveConflict(
    SyncConflict conflict,
    ConflictResolution resolution,
  ) async {
    // Resolve using the conflict's own resolution logic
    conflict.resolve(resolution);

    // The resolved entity should be saved by the app-specific callback
    // This is a placeholder - actual implementation depends on app integration
  }

  /// Dispose and clean up resources
  Future<void> dispose() async {
    await stop();
    await _discoveryService.dispose();
    await _connectionService.dispose();
    await _conflictsController.close();
  }
}
