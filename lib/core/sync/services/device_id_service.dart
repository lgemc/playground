import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;

/// Service for managing the current device's unique identifier
class DeviceIdService {
  static DeviceIdService? _instance;
  static DeviceIdService get instance => _instance ??= DeviceIdService._();

  DeviceIdService._();

  String? _deviceId;
  String? _deviceName;

  /// Get the unique device ID, creating one if it doesn't exist
  Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    final appDir = await getApplicationDocumentsDirectory();
    final deviceFile = File(p.join(appDir.path, 'data', 'device_id.txt'));

    if (await deviceFile.exists()) {
      _deviceId = await deviceFile.readAsString();
    } else {
      // Generate new device ID
      _deviceId = const Uuid().v4();
      await deviceFile.parent.create(recursive: true);
      await deviceFile.writeAsString(_deviceId!);
    }

    return _deviceId!;
  }

  /// Get a human-readable device name
  Future<String> getDeviceName() async {
    if (_deviceName != null) return _deviceName!;

    // Try to get system hostname
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        final result = await Process.run('hostname', []);
        if (result.exitCode == 0) {
          _deviceName = (result.stdout as String).trim();
          return _deviceName!;
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('hostname', []);
        if (result.exitCode == 0) {
          _deviceName = (result.stdout as String).trim();
          return _deviceName!;
        }
      }
    } catch (_) {
      // Fall through to default
    }

    // Default name based on platform
    final platform = _getPlatformName();
    _deviceName = '$platform Device';
    return _deviceName!;
  }

  /// Get the platform type
  String getPlatformType() {
    return _getPlatformName();
  }

  String _getPlatformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }
}
