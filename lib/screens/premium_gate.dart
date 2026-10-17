import 'package:flutter/material.dart';

import '../models/server_config_model.dart';
import '../providers/app_provider.dart';
import 'premium_screen.dart';

/// The only way to the PRO screen (home header, connect button, server
/// picker), so two paywalls never stack.
abstract final class PremiumGate {
  static bool _open = false;

  static Future<void> open(NavigatorState navigator) async {
    if (_open || !navigator.mounted) return;
    _open = true;
    try {
      await navigator.push<void>(
        MaterialPageRoute<void>(builder: (_) => const PremiumScreen()),
      );
    } finally {
      _open = false;
    }
  }

  /// Paywall for a PRO server picked by a free account. The current tunnel
  /// stays up; after an upgrade the picked server is selected.
  static Future<void> unlockServer(
    NavigatorState navigator,
    AppProvider provider,
    ServerConfig server,
  ) async {
    await open(navigator);
    if (!provider.isLockedForUser(server)) provider.selectServer(server);
  }
}
