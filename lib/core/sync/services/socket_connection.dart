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

  final Map<String, SocketConnection> _activeConnections = {};

  @override
  Future<void> startListening(int port) async {
    if (_serverSocket != null) return;

    _serverSocket = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      port,
      shared: true,
    );

    _serverSocket!.listen((socket) {
      // For incoming connections, we need to receive device info first
      _handleIncomingConnection(socket);
    });
  }

  void _handleIncomingConnection(Socket socket) {
    // Buffer for receiving device info
    final buffer = <int>[];
    late StreamSubscription subscription;

    subscription = socket.listen(
      (data) {
        buffer.addAll(data);

        // Check if we received the handshake (newline-terminated JSON)
        final index = buffer.indexOf(10); // '\n'
        if (index != -1) {
          // Parse device info
          final json = String.fromCharCodes(buffer.sublist(0, index));
          subscription.cancel();

          try {
            final deviceData = _parseDeviceInfo(json);
            final device = Device(
              id: deviceData['id'] as String,
              name: deviceData['name'] as String,
              type: deviceData['type'] as String,
              ipAddress: socket.remoteAddress.address,
              port: deviceData['port'] != null ? int.tryParse(deviceData['port'] as String) : null,
            );

            final connection = SocketConnection(socket, device);
            _activeConnections[device.id] = connection;
            _incomingController.add(connection);

            // Send handshake response
            socket.writeln('OK');
          } catch (e) {
            socket.close();
          }
        }
      },
      onError: (error) {
        subscription.cancel();
        socket.close();
      },
      cancelOnError: true,
    );
  }

  Map<String, dynamic> _parseDeviceInfo(String json) {
    // Simple JSON parsing for device info
    // In production, use dart:convert
    final result = <String, dynamic>{};
    final cleaned = json.trim().replaceAll('{', '').replaceAll('}', '');
    for (final pair in cleaned.split(',')) {
      final parts = pair.split(':');
      if (parts.length == 2) {
        final key = parts[0].trim().replaceAll('"', '');
        final value = parts[1].trim().replaceAll('"', '');
        result[key] = value;
      }
    }
    return result;
  }

  @override
  Future<void> stopListening() async {
    await _serverSocket?.close();
    _serverSocket = null;
  }

  @override
  Future<SyncConnection> connectToDevice(Device device) async {
    // Check if already connected
    if (_activeConnections.containsKey(device.id)) {
      final existing = _activeConnections[device.id]!;
      if (existing.isConnected) {
        return existing;
      }
    }

    if (device.ipAddress == null || device.port == null) {
      throw ArgumentError('Device must have ipAddress and port');
    }

    // Connect via TCP
    final socket = await Socket.connect(
      device.ipAddress!,
      device.port!,
      timeout: const Duration(seconds: 10),
    );

    // Send device handshake including port for future reconnections
    final handshake = '{"id":"${device.id}","name":"${device.name}","type":"${device.type}","port":"${device.port}"}';
    socket.writeln(handshake);

    // Wait for acknowledgment
    final completer = Completer<void>();
    late StreamSubscription subscription;

    subscription = socket.listen(
      (data) {
        final response = String.fromCharCodes(data).trim();
        if (response == 'OK') {
          subscription.cancel();
          completer.complete();
        }
      },
      onError: (error) {
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      cancelOnError: true,
    );

    try {
      await completer.future.timeout(const Duration(seconds: 5));
    } catch (e) {
      await socket.close();
      rethrow;
    }

    final connection = SocketConnection(socket, device);
    _activeConnections[device.id] = connection;

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
