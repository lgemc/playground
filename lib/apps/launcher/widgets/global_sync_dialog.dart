import 'package:flutter/material.dart';
import '../../../core/sync/models/device.dart';
import '../../../main.dart';

/// Dialog for syncing all syncable apps across devices
class GlobalSyncDialog extends StatefulWidget {
  const GlobalSyncDialog({super.key});

  @override
  State<GlobalSyncDialog> createState() => _GlobalSyncDialogState();
}

class _GlobalSyncDialogState extends State<GlobalSyncDialog> {
  List<Device> _devices = [];
  bool _isScanning = true;
  bool _isSyncing = false;
  String? _syncStatus;
  final Map<String, bool> _appSyncStatus = {};

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    if (!mounted) return;

    setState(() {
      _isScanning = true;
    });

    final syncService = SyncServiceProvider.instance;
    if (syncService == null) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
      });
      return;
    }

    // Wait a bit for devices to respond
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // Get devices from discovery service
    setState(() {
      _devices = syncService.discoveryService.devices;
      _isScanning = false;
    });
  }

  Future<void> _syncDatabase(Device device) async {
    setState(() {
      _isSyncing = true;
      _syncStatus = 'Syncing database...';
    });

    final syncService = SyncServiceProvider.instance;
    if (syncService == null) {
      setState(() {
        _syncStatus = 'Sync service not available';
        _isSyncing = false;
      });
      return;
    }

    try {
      // Sync the entire CRDT database (single sync, all tables)
      final result = await syncService.syncApp('crdt_database', device);

      if (!mounted) return;

      setState(() {
        _isSyncing = false;
        if (result.success) {
          _syncStatus = 'Sync completed! Sent: ${result.entitiesSent}, Received: ${result.entitiesReceived}';
        } else {
          _syncStatus = 'Sync failed: ${result.error}';
        }
      });

      // Auto-close after success
      if (result.success) {
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSyncing = false;
        _syncStatus = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sync All Apps'),
      content: SizedBox(
        width: 400,
        child: _isSyncing
            ? _buildSyncingView()
            : _isScanning
                ? _buildScanningView()
                : _buildDeviceList(),
      ),
      actions: _isSyncing
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              if (!_isScanning)
                TextButton(
                  onPressed: _startDiscovery,
                  child: const Text('Rescan'),
                ),
            ],
    );
  }

  Widget _buildScanningView() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Scanning for devices...'),
      ],
    );
  }

  Widget _buildDeviceList() {
    if (_devices.isEmpty) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.devices_other, size: 48, color: Colors.grey),
          SizedBox(height: 16),
          Text('No devices found'),
          SizedBox(height: 8),
          Text(
            'Make sure other devices are on the same network',
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Found ${_devices.length} device(s)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Will sync entire CRDT database',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        ..._devices.map((device) => ListTile(
              leading: const Icon(Icons.devices),
              title: Text(device.name),
              subtitle: Text(device.id.substring(0, 8)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _syncDatabase(device),
            )),
      ],
    );
  }

  Widget _buildSyncingView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 16),
        if (_syncStatus != null)
          Text(
            _syncStatus!,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
      ],
    );
  }
}
