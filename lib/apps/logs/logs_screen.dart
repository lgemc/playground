import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/logger.dart';
import '../../core/logs_storage.dart';
import 'widgets/log_item.dart';
import 'widgets/metadata_sidebar.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  List<LogEntry> _logs = [];
  Map<String, String> _apps = {};
  String? _selectedAppId;
  LogSeverity? _selectedSeverity;
  LogEntry? _selectedLog;
  bool _isLoading = true;
  StreamSubscription<LogEntry>? _logSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToLogs();
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      await LogsStorage.instance.init();

      final apps = await LogsStorage.instance.getApps();
      final logs = await LogsStorage.instance.getLogs(
        appId: _selectedAppId,
        severity: _selectedSeverity,
        limit: 500,
      );

      setState(() {
        _apps = apps;
        _logs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _subscribeToLogs() {
    _logSubscription = LogsStorage.instance.logStream.listen((entry) {
      if (_selectedAppId != null && entry.appId != _selectedAppId) return;
      if (_selectedSeverity != null && entry.severity != _selectedSeverity) return;

      setState(() {
        _logs.insert(0, entry);
        if (!_apps.containsKey(entry.appId)) {
          _apps[entry.appId] = entry.appName;
        }
      });
    });
  }

  void _onAppFilterChanged(String? appId) {
    setState(() {
      _selectedAppId = appId;
      _selectedLog = null;
    });
    _loadData();
  }

  void _onSeverityFilterChanged(LogSeverity? severity) {
    setState(() {
      _selectedSeverity = severity;
      _selectedLog = null;
    });
    _loadData();
  }

  void _onLogSelected(LogEntry log) {
    setState(() => _selectedLog = log);
  }

  void _onCloseSidebar() {
    setState(() => _selectedLog = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildFilters(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _logs.isEmpty
                        ? _buildEmptyState()
                        : _buildLogsList(),
              ),
            ],
          ),
          if (_selectedLog != null)
            GestureDetector(
              onTap: _onCloseSidebar,
              child: Container(
                color: Colors.black.withOpacity(0.3),
              ),
            ),
          MetadataSidebar(
            log: _selectedLog,
            onClose: _onCloseSidebar,
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: _selectedAppId,
              decoration: const InputDecoration(
                labelText: 'App',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All Apps'),
                ),
                ..._apps.entries.map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    )),
              ],
              onChanged: _onAppFilterChanged,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<LogSeverity?>(
              value: _selectedSeverity,
              decoration: const InputDecoration(
                labelText: 'Severity',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All Severities'),
                ),
                ...LogSeverity.values.map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s.name.toUpperCase()),
                    )),
              ],
              onChanged: _onSeverityFilterChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No logs found',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Logs will appear here as apps emit them',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList() {
    return ListView.builder(
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        final log = _logs[index];
        return LogItem(
          log: log,
          isSelected: _selectedLog?.id == log.id,
          onTap: () => _onLogSelected(log),
        );
      },
    );
  }
}
