import 'package:flutter/material.dart';

class FolderBreadcrumb extends StatelessWidget {
  final String currentPath;
  final Function(String) onNavigate;

  const FolderBreadcrumb({
    super.key,
    required this.currentPath,
    required this.onNavigate,
  });

  List<Map<String, String>> _buildBreadcrumbs() {
    final breadcrumbs = <Map<String, String>>[];

    // Always add root
    breadcrumbs.add({'name': 'Home', 'path': ''});

    if (currentPath.isEmpty) {
      return breadcrumbs;
    }

    // Split path and build progressive paths
    final parts = currentPath.split('/').where((p) => p.isNotEmpty).toList();
    String progressivePath = '';

    for (var i = 0; i < parts.length; i++) {
      progressivePath += '${parts[i]}/';
      breadcrumbs.add({
        'name': parts[i],
        'path': progressivePath,
      });
    }

    return breadcrumbs;
  }

  @override
  Widget build(BuildContext context) {
    final breadcrumbs = _buildBreadcrumbs();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey[100],
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < breadcrumbs.length; i++) ...[
              InkWell(
                onTap: () => onNavigate(breadcrumbs[i]['path']!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Text(
                    breadcrumbs[i]['name']!,
                    style: TextStyle(
                      color: i == breadcrumbs.length - 1
                          ? Theme.of(context).primaryColor
                          : Colors.grey[700],
                      fontWeight: i == breadcrumbs.length - 1
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
              if (i < breadcrumbs.length - 1)
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Colors.grey[600],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
