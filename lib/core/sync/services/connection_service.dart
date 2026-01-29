import 'dart:async';
import 'dart:typed_data';
import '../models/device.dart';

/// Represents an active connection to another device
abstract class SyncConnection {
  /// The device this connection is connected to
  Device get device;

  /// Whether this connection is currently open
  bool get isConnected;

  /// Stream of incoming data
  Stream<Uint8List> get dataStream;

  /// Send data to the connected device
  Future<void> send(Uint8List data);

  /// Close this connection
  Future<void> close();
}

/// Abstract interface for device-to-device connections
/// Implementations can use different transport mechanisms (TCP, WebRTC, etc.)
abstract class ConnectionService {
  /// Start listening for incoming connections
  Future<void> startListening(int port);

  /// Stop listening for incoming connections
  Future<void> stopListening();

  /// Connect to a device
  Future<SyncConnection> connectToDevice(Device device);

  /// Stream of incoming connections
  Stream<SyncConnection> get incomingConnections;

  /// Dispose and clean up resources
  Future<void> dispose();
}

/// Represents a sync session with a device
class SyncSession {
  final Device device;
  final SyncConnection connection;
  final DateTime startedAt;

  SyncSession({
    required this.device,
    required this.connection,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  bool get isActive => connection.isConnected;

  Future<void> close() async {
    await connection.close();
  }
}
