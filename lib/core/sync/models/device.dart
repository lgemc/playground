/// Represents a device that can sync with this device
class Device {
  /// Unique identifier for the device
  final String id;

  /// Human-readable name for the device
  final String name;

  /// Device type (e.g., 'android', 'ios', 'windows', 'linux', 'web')
  final String type;

  /// IP address for network communication
  final String? ipAddress;

  /// Port for network communication
  final int? port;

  /// Last time this device was seen/connected
  final DateTime lastSeen;

  /// Whether the device is currently online/available
  final bool isOnline;

  Device({
    required this.id,
    required this.name,
    required this.type,
    this.ipAddress,
    this.port,
    DateTime? lastSeen,
    this.isOnline = true,
  }) : lastSeen = lastSeen ?? DateTime.now();

  /// Create a copy with updated fields
  Device copyWith({
    String? id,
    String? name,
    String? type,
    String? ipAddress,
    int? port,
    DateTime? lastSeen,
    bool? isOnline,
  }) {
    return Device(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'ipAddress': ipAddress,
      'port': port,
      'lastSeen': lastSeen.toIso8601String(),
      'isOnline': isOnline,
    };
  }

  /// Create from JSON
  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      ipAddress: json['ipAddress'] as String?,
      port: json['port'] as int?,
      lastSeen: DateTime.parse(json['lastSeen'] as String),
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }

  @override
  String toString() => 'Device($name, $type, ${isOnline ? "online" : "offline"})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Device && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
