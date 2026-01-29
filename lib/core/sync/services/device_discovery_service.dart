import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/device.dart';
import 'device_id_service.dart';

/// Service for discovering other devices on the local network using UDP broadcast
class DeviceDiscoveryService {
  static const int _discoveryPort = 7653;
  static const int _syncPort = 7654;
  static const _multicastChannel = MethodChannel('playground.sync/multicast');

  final DeviceIdService _deviceIdService;
  final NetworkInfo _networkInfo = NetworkInfo();

  RawDatagramSocket? _listenSocket;  // For receiving broadcasts
  RawDatagramSocket? _sendSocket;    // For sending broadcasts (unused on Android)
  ServerSocket? _syncSocket;

  final _devicesController = StreamController<List<Device>>.broadcast();
  final Map<String, Device> _discoveredDevices = {};

  Timer? _broadcastTimer;
  bool _isDiscovering = false;
  bool _multicastLockAcquired = false;

  DeviceDiscoveryService(this._deviceIdService);

  /// Stream of discovered devices
  Stream<List<Device>> get devicesStream => _devicesController.stream;

  /// Get currently discovered devices
  List<Device> get devices => _discoveredDevices.values.toList();

  /// Start advertising this device on the network
  Future<void> startAdvertising() async {
    if (_listenSocket != null) return;

    try {
      // Acquire multicast lock on Android
      if (Platform.isAndroid && !_multicastLockAcquired) {
        try {
          await _multicastChannel.invokeMethod('acquire');
          _multicastLockAcquired = true;
          print('Multicast lock acquired on Android');
        } catch (e) {
          print('Failed to acquire multicast lock: $e');
        }
      }

      // Get device info
      final myDeviceId = await _deviceIdService.getDeviceId();
      final myDeviceName = await _getDeviceName();
      final myIpAddress = await _getLocalIpAddress();

      if (myIpAddress == null) {
        print('Cannot advertise: no local IP address found');
        return;
      }

      // Create separate sockets for listening and sending
      // Listen socket: bound to discovery port, reuses address for multiple instances
      // Note: reusePort can cause packet distribution issues on Linux
      // Using reuseAddress only to allow quick rebind after restart
      _listenSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
        reusePort: false,  // Disabled to ensure all broadcasts are received
      );

      _listenSocket!.broadcastEnabled = true;
      print('Listen socket bound to ${_listenSocket!.address.address}:${_listenSocket!.port}, broadcast enabled: ${_listenSocket!.broadcastEnabled}');

      // Listen for all broadcast messages (both discovery requests and announcements)
      _listenSocket!.listen((event) async {
        if (event == RawSocketEvent.read) {
          final datagram = _listenSocket!.receive();
          if (datagram != null) {
            try {
              final message = utf8.decode(datagram.data);
              print('[$myDeviceName] Received broadcast from ${datagram.address.address}:${datagram.port}: $message');
              final data = jsonDecode(message) as Map<String, dynamic>;

              // Skip our own messages early
              if (data['deviceId'] == myDeviceId) {
                print('[$myDeviceName] Skipping own announcement');
                return;
              }

              // Respond to discovery requests
              if (data['type'] == 'discovery_request') {
                print('[$myDeviceName] Responding to discovery request');
                _sendAdvertisement(myDeviceId, myDeviceName, myIpAddress);
              }
              // Process device announcements
              else if (data['type'] == 'device_announcement') {
                print('[$myDeviceName] Processing device announcement from ${data['name']}');
                await _processDeviceAnnouncement(data);
              }
            } catch (e) {
              print('[$myDeviceName] Error processing broadcast: $e');
            }
          }
        }
      });

      // Send socket: Use ephemeral port (0) for all platforms
      final sendPort = 0;

      _sendSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        sendPort,
        reuseAddress: true,
      );

      // Enable broadcast AFTER binding
      _sendSocket!.broadcastEnabled = true;

      // Verify broadcast is enabled
      if (!_sendSocket!.broadcastEnabled) {
        print('WARNING: Broadcast could not be enabled on send socket!');
      }

      print('Send socket bound to ${_sendSocket!.address.address}:${_sendSocket!.port}, broadcast: ${_sendSocket!.broadcastEnabled}');

      // Start sync server
      _syncSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _syncPort,
        shared: true,
      );

      print('Advertising device: $myDeviceName ($myDeviceId) at $myIpAddress:$_syncPort');

      // Periodic advertisement
      _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _sendAdvertisement(myDeviceId, myDeviceName, myIpAddress);
      });

      // Initial advertisement
      _sendAdvertisement(myDeviceId, myDeviceName, myIpAddress);
    } catch (e) {
      print('Error starting advertising: $e');
      rethrow;
    }
  }

  void _sendAdvertisement(String deviceId, String deviceName, String ipAddress) {
    try {
      // Check if socket is still valid
      if (_sendSocket == null) {
        print('Send socket is null, cannot send advertisement');
        return;
      }

      final announcement = jsonEncode({
        'type': 'device_announcement',
        'deviceId': deviceId,
        'name': deviceName,
        'ipAddress': ipAddress,
        'port': _syncPort,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final data = utf8.encode(announcement);

      // Use send socket for all platforms
      // The listen socket on Android can't send (Operation not permitted)
      final socketToUse = _sendSocket;

      // Verify socket is valid
      if (socketToUse == null) {
        print('ERROR: Socket is null!');
        return;
      }

      // Send to both broadcast addresses to ensure delivery
      // 255.255.255.255 - limited broadcast
      int? bytes1;
      try {
        bytes1 = socketToUse.send(
          data,
          InternetAddress('255.255.255.255'),
          _discoveryPort,
        );
        if (bytes1 == 0) {
          print('ERROR: Failed to send to 255.255.255.255 - returned $bytes1 bytes');
        }
      } catch (e) {
        print('ERROR sending to 255.255.255.255: $e');
      }

      // Subnet broadcast (e.g., 192.168.0.255 for 192.168.0.x)
      final subnetBroadcast = _getSubnetBroadcast(ipAddress);
      int? bytes2;
      if (subnetBroadcast != null) {
        try {
          bytes2 = socketToUse.send(
            data,
            InternetAddress(subnetBroadcast),
            _discoveryPort,
          );
          if (bytes2 == 0) {
            print('ERROR: Failed to send to $subnetBroadcast - returned $bytes2 bytes');
          }
        } catch (e) {
          print('ERROR sending to $subnetBroadcast: $e');
        }
      }

      print('Sent advertisement: $bytes1 bytes to 255.255.255.255:$_discoveryPort, $bytes2 bytes to $subnetBroadcast:$_discoveryPort');
    } catch (e) {
      print('Error sending advertisement: $e');
      // On Android, if app is backgrounded, socket may become invalid
      // Cancel timer to prevent repeated errors
      if (Platform.isAndroid && e.toString().contains('Operation not permitted')) {
        _broadcastTimer?.cancel();
        _broadcastTimer = null;
      }
    }
  }

  String? _getSubnetBroadcast(String ipAddress) {
    // For typical home networks (192.168.x.x), calculate broadcast address
    final parts = ipAddress.split('.');
    if (parts.length == 4 && parts[0] == '192' && parts[1] == '168') {
      return '${parts[0]}.${parts[1]}.${parts[2]}.255';
    }
    return null;
  }

  /// Stop advertising this device
  Future<void> stopAdvertising() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _listenSocket?.close();
    _listenSocket = null;
    _sendSocket?.close();
    _sendSocket = null;
    await _syncSocket?.close();
    _syncSocket = null;

    // Release multicast lock on Android
    if (Platform.isAndroid && _multicastLockAcquired) {
      try {
        await _multicastChannel.invokeMethod('release');
        _multicastLockAcquired = false;
        print('Multicast lock released on Android');
      } catch (e) {
        print('Failed to release multicast lock: $e');
      }
    }
  }

  /// Start discovering other devices on the network
  Future<void> startDiscovery() async {
    if (_isDiscovering) return;
    _isDiscovering = true;

    // Start advertising first (this also sets up the socket listener)
    await startAdvertising();

    // Send discovery request to find existing devices
    await _sendDiscoveryRequest();

    // Periodic cleanup of stale devices
    Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_isDiscovering) return;
      _cleanupStaleDevices();
    });
  }

  Future<void> _sendDiscoveryRequest() async {
    try {
      final request = jsonEncode({
        'type': 'discovery_request',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final data = utf8.encode(request);
      _sendSocket?.send(
        data,
        InternetAddress('255.255.255.255'),
        _discoveryPort,
      );
    } catch (e) {
      print('Error sending discovery request: $e');
    }
  }

  Future<void> _processDeviceAnnouncement(Map<String, dynamic> data) async {
    try {
      final deviceId = data['deviceId'] as String?;
      final deviceName = data['name'] as String?;
      final ipAddress = data['ipAddress'] as String?;
      final port = data['port'] as int?;

      // Skip if missing required fields
      if (deviceId == null || ipAddress == null || port == null) return;

      // Skip if it's this device
      final myDeviceId = await _deviceIdService.getDeviceId();
      if (deviceId == myDeviceId) return;

      final device = Device(
        id: deviceId,
        name: deviceName ?? 'Unknown Device',
        ipAddress: ipAddress,
        port: port,
        lastSeen: DateTime.now(),
        isOnline: true,
        type: 'unknown',
      );

      _discoveredDevices[deviceId] = device;
      _devicesController.add(_discoveredDevices.values.toList());
    } catch (e) {
      // Ignore invalid announcements
    }
  }

  void _cleanupStaleDevices() {
    final now = DateTime.now();
    _discoveredDevices.removeWhere((id, device) {
      final timeSinceLastSeen = now.difference(device.lastSeen);
      return timeSinceLastSeen.inSeconds > 30;
    });
    _devicesController.add(_discoveredDevices.values.toList());
  }

  /// Stop discovering devices
  Future<void> stopDiscovery() async {
    _isDiscovering = false;
    _discoveredDevices.clear();
    _devicesController.add([]);
  }

  Future<String?> _getLocalIpAddress() async {
    try {
      final wifiIP = await _networkInfo.getWifiIP();
      if (wifiIP != null) return wifiIP;

      // Fallback: try to get from network interfaces
      for (final interface in await NetworkInterface.list()) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              addr.address.startsWith('192.168.')) {
            return addr.address;
          }
        }
      }

      return null;
    } catch (e) {
      print('Error getting local IP: $e');
      return null;
    }
  }

  Future<String> _getDeviceName() async {
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        final result = await Process.run('hostname', []);
        return result.stdout.toString().trim();
      } else if (Platform.isWindows) {
        return Platform.environment['COMPUTERNAME'] ?? 'Windows Device';
      }
      return 'Unknown Device';
    } catch (e) {
      return 'Unknown Device';
    }
  }

  /// Dispose and clean up resources
  Future<void> dispose() async {
    await stopDiscovery();
    await stopAdvertising();
    await _devicesController.close();
  }
}
