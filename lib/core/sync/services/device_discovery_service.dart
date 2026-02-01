import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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

  final _devicesController = StreamController<List<Device>>.broadcast();
  final Map<String, Device> _discoveredDevices = {};

  Timer? _broadcastTimer;
  bool _isDiscovering = false;
  bool _multicastLockAcquired = false;

  int _actualSyncPort = _syncPort;

  DeviceDiscoveryService(this._deviceIdService);

  /// Stream of discovered devices
  Stream<List<Device>> get devicesStream => _devicesController.stream;

  /// Get currently discovered devices
  List<Device> get devices => _discoveredDevices.values.toList();

  /// Set the actual sync port being used
  void setSyncPort(int port) {
    _actualSyncPort = port;
  }

  /// Start advertising this device on the network
  Future<void> startAdvertising() async {
    if (_listenSocket != null) return;

    try {
      // Acquire multicast lock on Android
      if (Platform.isAndroid && !_multicastLockAcquired) {
        try {
          await _multicastChannel.invokeMethod('acquire');
          _multicastLockAcquired = true;
          // Small delay to ensure lock is fully active
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          rethrow;
        }
      }

      // Get device info
      final myDeviceId = await _deviceIdService.getDeviceId();
      final myDeviceName = await _getDeviceName();
      final myIpAddress = await _getLocalIpAddress();

      if (myIpAddress == null) {
        return;
      }

      // Create separate sockets for listening and sending
      // Listen socket: bound to discovery port, reuses address for multiple instances
      _listenSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
        reusePort: false,  // reusePort not supported on all Android versions
      );

      _listenSocket!.broadcastEnabled = true;

      // On Android, use the listen socket for sending too
      if (Platform.isAndroid) {
        _sendSocket = _listenSocket;
      }

      // Listen for all broadcast messages (both discovery requests and announcements)
      _listenSocket!.listen((event) async {
        if (event == RawSocketEvent.read) {
          final datagram = _listenSocket!.receive();
          if (datagram != null) {
            try {
              final message = utf8.decode(datagram.data);
              final data = jsonDecode(message) as Map<String, dynamic>;

              // Skip our own messages early
              if (data['deviceId'] == myDeviceId) {
                return;
              }

              // Respond to discovery requests
              if (data['type'] == 'discovery_request') {
                _sendAdvertisement(myDeviceId, myDeviceName, myIpAddress);
              }
              // Process device announcements
              else if (data['type'] == 'device_announcement') {
                await _processDeviceAnnouncement(data);
              }
            } catch (e) {
            }
          }
        }
      });

      // Send socket: Only create separate socket on non-Android platforms
      if (!Platform.isAndroid) {
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
        }

      }


      // Periodic advertisement
      _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _sendAdvertisement(myDeviceId, myDeviceName, myIpAddress);
      });

      // Initial advertisement
      _sendAdvertisement(myDeviceId, myDeviceName, myIpAddress);
    } catch (e) {
      rethrow;
    }
  }

  void _sendAdvertisement(String deviceId, String deviceName, String ipAddress) {
    try {
      final announcement = jsonEncode({
        'type': 'device_announcement',
        'deviceId': deviceId,
        'name': deviceName,
        'ipAddress': ipAddress,
        'port': _actualSyncPort,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final data = utf8.encode(announcement);

      if (Platform.isAndroid) {
        // Use native Android method for broadcasting
        _sendBroadcastNative(data, '255.255.255.255');
        final subnetBroadcast = _getSubnetBroadcast(ipAddress);
        if (subnetBroadcast != null) {
          _sendBroadcastNative(data, subnetBroadcast);
        }
      } else {
        // Use Dart socket for non-Android platforms
        if (_sendSocket == null) {
          return;
        }

        final socketToUse = _sendSocket!;

        // Send to both broadcast addresses
        int? bytes1;
        try {
          bytes1 = socketToUse.send(
            data,
            InternetAddress('255.255.255.255'),
            _discoveryPort,
          );
          if (bytes1 == 0) {
          }
        } catch (e) {
        }

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
            }
          } catch (e) {
          }
        }

      }
    } catch (e) {
    }
  }

  void _sendBroadcastNative(List<int> data, String address) async {
    try {
      final bytes = await _multicastChannel.invokeMethod<int>('sendBroadcast', {
        'data': Uint8List.fromList(data),
        'address': address,
        'port': _discoveryPort,
      });
    } catch (e) {
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

    // On Android, _sendSocket is the same as _listenSocket, so don't close it again
    if (!Platform.isAndroid) {
      _sendSocket?.close();
    }
    _sendSocket = null;

    // Release multicast lock on Android
    if (Platform.isAndroid && _multicastLockAcquired) {
      try {
        await _multicastChannel.invokeMethod('release');
        _multicastLockAcquired = false;
      } catch (e) {
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
      final myDeviceId = await _deviceIdService.getDeviceId();

      final request = jsonEncode({
        'type': 'discovery_request',
        'deviceId': myDeviceId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final data = utf8.encode(request);

      if (_sendSocket != null) {
        _sendSocket!.send(
          data,
          InternetAddress('255.255.255.255'),
          _discoveryPort,
        );
      } else {
      }
    } catch (e) {
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
