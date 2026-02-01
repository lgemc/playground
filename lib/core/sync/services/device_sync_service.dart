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

    // Handle incoming connections
    _connectionService.incomingConnections.listen(_handleIncomingConnection);
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
    // Check if already connected
    if (_activeSessions.containsKey(device.id)) {
      final existing = _activeSessions[device.id]!;
      if (existing.isActive) {
        return existing;
      }
    }

    // Establish connection
    final connection = await _connectionService.connectToDevice(device);

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

      // Connect to device
      final session = await connectToDevice(device);

      // Create protocol handler
      final protocol = SyncProtocol(session.connection);

      // Perform handshake
      final myDeviceId = await _deviceIdService.getDeviceId();
      await protocol.handshake(myDeviceId, 'My Device');

      // Get last sync time for this app with this device
      final lastSyncTime = await _getLastSyncTime(appId, device.id);

      // Create sync coordinator
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

      // Perform blob sync for file_system when syncing crdt_database
      if (appId == 'crdt_database' && result.success) {
        print('[Sync] Checking if file blobs need syncing...');
        await _syncFileBlobs(coordinator);
        print('[Sync] Blob sync check completed');
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
        (hash) => storage.getBlobByHash(hash),
        (hash) => storage.getRelativePathByHash(hash),
        (hash, data, relativePath) => storage.storeBlobByHash(hash, data, relativePath),
      );
    } catch (e) {
      print('[Sync] Blob sync error: $e');
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
    print('[Sync] 📥 Incoming connection from ${connection.device.ipAddress}');

    if (_getChangesCallback == null || _applyChangesCallback == null) {
      print('[Sync] ❌ Callbacks not set, closing connection');
      await connection.close();
      return;
    }

    try {
      final protocol = SyncProtocol(connection);
      print('[Sync] Waiting for handshake...');

      // Wait for handshake with extended timeout
      final handshakeMsg = await protocol.messages
          .firstWhere((msg) => msg.type == SyncMessageType.handshake)
          .timeout(const Duration(seconds: 30));

      print('[Sync] ✅ Handshake received');

      // Send acknowledgment
      await protocol.send(SyncMessage(
        type: SyncMessageType.handshakeAck,
        payload: {'status': 'ok'},
      ));
      print('[Sync] Sent handshake ack');

      // Listen for sync requests with timeout to prevent hanging
      final coordinator = SyncCoordinator(protocol);

      // Handle ONE sync per connection - simpler and more reliable
      print('[Sync] Listening for sync requests...');

      try {
        String? syncedAppId;
        await for (final message in protocol.messages.timeout(
          const Duration(seconds: 60),
          onTimeout: (sink) {
            print('[Sync] ⚠️  Timeout waiting for messages');
            sink.close();
          },
        )) {
          print('[Sync] Received message: ${message.type}');

          if (message.type == SyncMessageType.syncRequest) {
            syncedAppId = message.payload['appId'] as String;
            print('[Sync] Processing syncRequest for appId: $syncedAppId');
            await coordinator.handleSyncRequest(
              message,
              (appId, since) => _getChangesCallback!(appId, since),
              (appId, entities) => _applyChangesCallback!(appId, entities),
            );
            print('[Sync] ✅ handleSyncRequest completed');

            // Don't break - continue listening for blob requests
            if (syncedAppId == 'crdt_database') {
              print('[Sync] Metadata sync done, waiting for blob requests...');
            }
          } else if (message.type == SyncMessageType.blobRequest && syncedAppId == 'crdt_database') {
            print('[Sync] Received blob request, processing...');
            final storage = FileSystemStorage.instance;
            await coordinator.handleBlobRequest(
              message,
              (hash) => storage.getBlobByHash(hash),
              (hash) => storage.getRelativePathByHash(hash),
            );
            print('[Sync] Blob request handled, closing connection');
            break; // Done with blob sync
          }
        }
        print('[Sync] Message loop ended');
      } catch (e) {
        print('[Sync] Error in incoming connection handler: $e');
      } finally {
        // Always clean up
        print('[Sync] Cleaning up connection');
        await protocol.dispose();
        await connection.close();
      }
    } catch (e) {
      print('[Sync] Error in _handleIncomingConnection: $e');
      await connection.close();
    }
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
