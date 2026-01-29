import 'package:flutter/material.dart';

import '../core/app_bus.dart';
import '../core/app_event.dart';
import '../core/app_registry.dart';
import '../widgets/share_sheet.dart';
import 'share_content.dart';

/// Service for managing inter-app content sharing.
/// Apps register as receivers for content types, and content can be shared
/// to compatible apps through a picker UI.
class ShareService {
  static ShareService? _instance;
  static ShareService get instance => _instance ??= ShareService._();

  ShareService._();

  /// Registry of apps and their accepted content types
  final Map<String, List<ShareContentType>> _receivers = {};

  /// Register an app as a receiver for content types
  void registerReceiver(String appId, List<ShareContentType> acceptedTypes) {
    _receivers[appId] = acceptedTypes;
  }

  /// Unregister an app
  void unregisterReceiver(String appId) {
    _receivers.remove(appId);
  }

  /// Get app IDs that can receive a content type
  List<String> getReceiversFor(ShareContentType type) {
    return _receivers.entries
        .where((entry) => entry.value.contains(type))
        .map((entry) => entry.key)
        .toList();
  }

  /// Share content - shows picker if multiple receivers, direct if single
  /// Returns true if sharing was successful, false if cancelled or failed
  Future<bool> share(BuildContext context, ShareContent content) async {
    final receiverIds = getReceiversFor(content.type);

    // Filter out the source app from receivers
    final eligibleReceivers =
        receiverIds.where((id) => id != content.sourceAppId).toList();

    if (eligibleReceivers.isEmpty) {
      // No apps can receive this content type
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No apps available to receive this content'),
          ),
        );
      }
      return false;
    }

    if (eligibleReceivers.length == 1) {
      // Direct share to the only available app
      return shareTo(eligibleReceivers.first, content);
    }

    // Show picker for multiple receivers
    if (!context.mounted) return false;

    final targetAppId = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => ShareSheet(
        content: content,
        receiverIds: eligibleReceivers,
      ),
    );

    if (targetAppId == null) {
      return false; // User cancelled
    }

    return shareTo(targetAppId, content);
  }

  /// Share directly to a specific app (bypasses picker)
  /// Returns true if sharing was successful
  Future<bool> shareTo(String targetAppId, ShareContent content) async {
    final app = AppRegistry.instance.getApp(targetAppId);
    if (app == null) {
      return false;
    }

    // Check if app accepts this content type
    if (!app.acceptedShareTypes.contains(content.type)) {
      return false;
    }

    try {
      // Deliver the content to the app
      await app.onReceiveShare(content);

      // Emit success event to AppBus
      await AppBus.instance.emit(AppEvent.create(
        type: 'share.completed',
        appId: content.sourceAppId,
        metadata: {
          'targetAppId': targetAppId,
          'contentType': content.type.name,
          'contentId': content.id,
        },
      ));

      return true;
    } catch (e) {
      // Emit failure event
      await AppBus.instance.emit(AppEvent.create(
        type: 'share.failed',
        appId: content.sourceAppId,
        metadata: {
          'targetAppId': targetAppId,
          'contentType': content.type.name,
          'contentId': content.id,
          'error': e.toString(),
        },
      ));
      return false;
    }
  }

  /// Reset for testing
  static void resetInstance() {
    _instance = null;
  }
}
