import 'package:flutter/material.dart';
import '../core/sync/models/device.dart';
import '../main.dart';

/// Widget for discovering and syncing with other devices
class SyncWidget extends StatefulWidget {
  final String appId;
  final String appName;

  const SyncWidget({
    super.key,
    required this.appId,
    required this.appName,
  });

  @override
  State<SyncWidget> createState() => _SyncWidgetState();
}

class _SyncWidgetState extends State<SyncWidget> {
  List<Device> _devices = [];
  bool _isDiscovering = false;
  bool _isSyncing = false;
  String? _syncStatus;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    final syncService = SyncServiceProvider.instance;
    if (syncService == null) return;

    setState(() {
      _isDiscovering = true;
    });

    try {
      // Listen to device stream
      syncService.devicesStream.listen((devices) {
        if (mounted) {
          setState(() {
            _devices = devices;
          });
        }
      });

      // Initial discovery
      final devices = await syncService.discoverDevices();
      if (mounted) {
        setState(() {
          _devices = devices;
          _isDiscovering = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDiscovering = false;
          _syncStatus = 'Discovery failed: $e';
        });
      }
    }
  }

  Future<void> _syncWithDevice(Device device) async {
    final syncService = SyncServiceProvider.instance;
    if (syncService == null) return;

    setState(() {
      _isSyncing = true;
      _syncStatus = 'Syncing with ${device.name}...';
    });

    try {
      final result = await syncService.syncApp(widget.appId, device);

      if (mounted) {
        setState(() {
          _isSyncing = false;
          if (result.success) {
            _syncStatus = 'Synced successfully! '
                '${result.entitiesSent} sent, ${result.entitiesReceived} received';
          } else {
            _syncStatus = 'Sync failed: ${result.error}';
          }
        });

        // Show success/error snackbar
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_syncStatus!),
              backgroundColor: result.success ? Colors.green : Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncStatus = 'Sync error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sync ${widget.appName}'),
        actions: [
          if (_isDiscovering)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _startDiscovery,
              tooltip: 'Refresh devices',
            ),
        ],
      ),
      body: Column(
        children: [
          if (_syncStatus != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(
                _syncStatus!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.devices,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isDiscovering
                              ? 'Discovering devices...'
                              : 'No devices found',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Make sure other devices are on the same network',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return ListTile(
                        leading: const Icon(Icons.phone_android),
                        title: Text(device.name),
                        subtitle: Text('${device.ipAddress ?? "unknown"}:${device.port ?? 0}'),
                        trailing: _isSyncing
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : ElevatedButton.icon(
                                onPressed: () => _syncWithDevice(device),
                                icon: const Icon(Icons.sync),
                                label: const Text('Sync'),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
