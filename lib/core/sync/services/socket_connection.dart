import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../models/device.dart';
import 'connection_service.dart';

/// TCP socket-based connection implementation
class SocketConnection implements SyncConnection {
  final Socket _socket;
  @override
  final Device device;

  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>.broadcast();

  bool _isConnected = true;

  SocketConnection(this._socket, this.device) {
    _socket.listen(
      (data) {
        _dataController.add(Uint8List.fromList(data));
      },
      onError: (error) {
        _isConnected = false;
        _dataController.addError(error);
      },
      onDone: () {
        _isConnected = false;
        _dataController.close();
      },
    );
  }

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  @override
  Future<void> send(Uint8List data) async {
    if (!_isConnected) {
      throw StateError('Connection is not active');
    }
    _socket.add(data);
    await _socket.flush();
  }

  @override
  Future<void> close() async {
    _isConnected = false;
    await _socket.close();
    await _dataController.close();
  }
}

/// TCP socket-based connection service implementation
class SocketConnectionService implements ConnectionService {
  ServerSocket? _serverSocket;
  final StreamController<SyncConnection> _incomingController =
      StreamController<SyncConnection>.broadcast();

  final Map<String, SyncConnection> _activeConnections = {};

  String? _myDeviceId;
  String? _myDeviceName;

  /// Get the actual port being used for listening
  int? get listeningPort => _serverSocket?.port;

  @override
  Future<void> startListening(int port) async {
    if (_serverSocket != null) {
      return;
    }


    try {
      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );
    } on SocketException catch (e) {
      // If port is already in use, try with a random port
      if (e.osError?.errorCode == 98 || e.message.contains('Address already in use')) {
        _serverSocket = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          0, // 0 = random available port
          shared: true,
        );
      } else {
        rethrow;
      }
    }


    print('[Socket] Server listening on ${_serverSocket!.address.address}:${_serverSocket!.port}');

    _serverSocket!.listen((socket) {
      print('[Socket] 🔌 New socket connection from ${socket.remoteAddress.address}:${socket.remotePort}');
      // For incoming connections, we need to receive device info first
      _handleIncomingConnection(socket);
    });
  }

  void _handleIncomingConnection(Socket socket) {
    // Create a placeholder device - will be identified via sync protocol handshake
    final device = Device(
      id: 'unknown-${socket.remoteAddress.address}',
      name: 'Unknown Device',
      type: 'unknown',
      ipAddress: socket.remoteAddress.address,
      port: socket.remotePort,
    );

    // Create connection immediately - no socket-level handshake needed
    final connection = SocketConnection(socket, device);
    _incomingController.add(connection);
  }

  @override
  Future<void> stopListening() async {
    await _serverSocket?.close();
    _serverSocket = null;
  }

  /// Set this device's identity for handshakes
  void setDeviceInfo(String deviceId, String deviceName) {
    _myDeviceId = deviceId;
    _myDeviceName = deviceName;
  }

  @override
  Future<SyncConnection> connectToDevice(Device device) async {
    // Check if already connected
    if (_activeConnections.containsKey(device.id)) {
      final existing = _activeConnections[device.id]!;
      if (existing.isConnected) {
        return existing;
      } else {
        // Remove stale connection
        _activeConnections.remove(device.id);
      }
    }

    if (device.ipAddress == null || device.port == null) {
      throw ArgumentError('Device must have ipAddress and port');
    }

    if (_myDeviceId == null || _myDeviceName == null) {
      throw StateError('Device info not set. Call setDeviceInfo() first.');
    }

    // Connect via TCP with extended timeout
    final socket = await Socket.connect(
      device.ipAddress!,
      device.port!,
      timeout: const Duration(seconds: 10),
    );


    // Create connection immediately - handshake happens at protocol level
    final connection = SocketConnection(socket, device);
    _activeConnections[device.id] = connection;

    // Clean up when connection closes
    connection.dataStream.listen(
      null,
      onDone: () => _activeConnections.remove(device.id),
      cancelOnError: true,
    );

    return connection;
  }

  @override
  Stream<SyncConnection> get incomingConnections => _incomingController.stream;

  @override
  Future<void> dispose() async {
    await stopListening();

    // Close all active connections
    for (final connection in _activeConnections.values) {
      await connection.close();
    }
    _activeConnections.clear();

    await _incomingController.close();
  }
}

