import 'package:flutter/material.dart';
import '../../core/sub_app.dart';
import '../../core/app_registry.dart';
import '../../services/config_service.dart';
import 'screens/database_migration_screen.dart';

/// Settings app for viewing and modifying configurations
class SettingsApp extends SubApp {
  @override
  String get id => 'settings';

  @override
  String get name => 'Settings';

  @override
  IconData get icon => Icons.settings;

  @override
  Color get themeColor => Colors.blue;

  @override
  Widget build(BuildContext context) {
    return const SettingsScreen();
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedScope = 'global';
  String? _selectedAppId;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedScope == 'global'
            ? 'Settings - Global'
            : 'Settings - $_selectedAppId'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      drawer: isWide ? null : Drawer(child: _buildScopeSelector()),
      body: isWide
          ? Row(
              children: [
                SizedBox(
                  width: 200,
                  child: _buildScopeSelector(),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _buildConfigList(),
                ),
              ],
            )
          : _buildConfigList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddConfigDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddConfigDialog(BuildContext context) {
    final keyController = TextEditingController();
    final valueController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_selectedScope == 'global'
            ? 'Add Global Configuration'
            : 'Add Configuration for $_selectedAppId'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: 'Key',
                hintText: 'e.g., llm.api_key',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: valueController,
              decoration: const InputDecoration(
                labelText: 'Value',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final key = keyController.text.trim();
              final value = valueController.text;
              if (key.isNotEmpty) {
                await ConfigService.instance.set(
                  key,
                  value,
                  appId: _selectedAppId,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  setState(() {});
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeSelector() {
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.public),
          title: const Text('Global'),
          selected: _selectedScope == 'global',
          onTap: () {
            setState(() {
              _selectedScope = 'global';
              _selectedAppId = null;
            });
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.upload),
          title: const Text('Database Migration'),
          subtitle: const Text('Add spaced repetition'),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const DatabaseMigrationScreen(),
              ),
            );
          },
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Apps',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ),
        ...AppRegistry.instance.apps.map((app) {
          final isSelected = _selectedScope == 'app' && _selectedAppId == app.id;
          return ListTile(
            leading: Icon(app.icon),
            title: Text(app.name),
            selected: isSelected,
            onTap: () {
              setState(() {
                _selectedScope = 'app';
                _selectedAppId = app.id;
              });
            },
          );
        }),
      ],
    );
  }

  Widget _buildConfigList() {
    final configs = _selectedScope == 'global'
        ? ConfigService.instance.getAll()
        : ConfigService.instance.getAll(appId: _selectedAppId);

    if (configs.isEmpty) {
      return const Center(
        child: Text(
          'No configuration values',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: configs.length,
      itemBuilder: (context, index) {
        final entry = configs.entries.elementAt(index);
        final key = entry.key;
        final value = entry.value;
        final isDefault = _selectedScope == 'global'
            ? ConfigService.instance.isDefault(key)
            : ConfigService.instance.isDefault(key, appId: _selectedAppId);

        return _ConfigTile(
          configKey: key,
          value: value,
          isDefault: isDefault,
          appId: _selectedAppId,
          onChanged: () => setState(() {}),
        );
      },
    );
  }
}

class _ConfigTile extends StatelessWidget {
  final String configKey;
  final String value;
  final bool isDefault;
  final String? appId;
  final VoidCallback onChanged;

  const _ConfigTile({
    required this.configKey,
    required this.value,
    required this.isDefault,
    required this.appId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Row(
        children: [
          Expanded(child: Text(configKey)),
          if (!isDefault)
            Chip(
              label: const Text('Modified'),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              labelStyle: const TextStyle(fontSize: 10),
            ),
        ],
      ),
      subtitle: Text(
        value,
        style: TextStyle(
          color: isDefault ? Colors.grey : Theme.of(context).colorScheme.primary,
          fontWeight: isDefault ? FontWeight.normal : FontWeight.bold,
        ),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) {
          switch (action) {
            case 'edit':
              _showEditDialog(context);
            case 'reset':
              _resetConfig(context);
            case 'delete':
              _deleteConfig(context);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          if (!isDefault)
            const PopupMenuItem(value: 'reset', child: Text('Reset to default')),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      onTap: () => _showEditDialog(context),
    );
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: value);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit $configKey'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Value',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await ConfigService.instance.set(
                configKey,
                controller.text,
                appId: appId,
              );
              if (context.mounted) {
                Navigator.pop(context);
                onChanged();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _resetConfig(BuildContext context) async {
    await ConfigService.instance.reset(configKey, appId: appId);
    onChanged();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset $configKey to default')),
      );
    }
  }

  void _deleteConfig(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete configuration'),
        content: Text('Delete $configKey? This will remove both the user override and default value.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ConfigService.instance.delete(configKey, appId: appId);
      onChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $configKey')),
        );
      }
    }
  }
}
