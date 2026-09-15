import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../config/api_config.dart';

/// Dynamic backend-domain updates via Firebase Remote Config.
///
/// Flow (same pattern as the vlees app):
///   1. Register defaults (matching [ApiConfig]) as a fallback for the case
///      when Firebase is unreachable on first launch (no network yet).
///   2. Fetch + activate fresh values from Firebase.
///   3. Copy them into [ApiConfig], which the rest of the code reads.
///
/// Remote Config keys (Firebase Console → Run → Remote Config):
///   - `api_base_url` → [ApiConfig.baseUrl]
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  /// Key names kept in one place to avoid typos.
  static const String kApiBaseUrl = 'api_base_url';

  /// Hard timeout for the whole fetchAndActivate call. If Firebase hangs
  /// (provider resets the connection) we must not stall startup longer
  /// than this — otherwise we risk an ANR.
  static const Duration _hardTimeout = Duration(seconds: 5);

  FirebaseRemoteConfig? _rc;

  /// Startup initialisation. Never rethrows — a Remote Config failure must
  /// not crash app launch; defaults from [ApiConfig] stay in effect.
  Future<void> initialize() async {
    try {
      final rc = FirebaseRemoteConfig.instance;
      _rc = rc;

      // Defaults = the baked-in domain (fallback).
      await rc.setDefaults(<String, dynamic>{kApiBaseUrl: ApiConfig.baseUrl});
      _apply(rc);

      await rc.setConfigSettings(
        RemoteConfigSettings(
          // How long we wait for Firebase before falling back to defaults.
          fetchTimeout: const Duration(seconds: 10),
          // How often the app is allowed to actually hit the network for
          // fresh values. 15 minutes: a blocked domain is picked up quickly
          // while the fetch spam stays minimal. Use Duration.zero to debug.
          minimumFetchInterval: const Duration(minutes: 15),
        ),
      );

      // Fetch + activate with the hard timeout. Firebase.fetchAndActivate()
      // occasionally hangs when the provider drops the connection
      // (Connection closed by peer) — without this wrapper the app can
      // freeze at startup and hit an ANR.
      await rc.fetchAndActivate().timeout(
        _hardTimeout,
        onTimeout: () {
          if (kDebugMode) {
            debugPrint(
              'RemoteConfigService: fetchAndActivate timed out '
              'after $_hardTimeout',
            );
          }
          return false;
        },
      );

      // Copy into ApiConfig so all consumers read the live domain.
      _apply(rc);
    } catch (e, s) {
      // No network / Firebase unreachable — keep running on ApiConfig defaults.
      if (kDebugMode) {
        debugPrint('RemoteConfigService.initialize failed: $e\n$s');
      }
    }
  }

  /// Force-refresh values while the app is running (e.g. a "refresh
  /// servers" button). Returns true when new values were activated.
  Future<bool> refresh() async {
    final rc = _rc;
    if (rc == null) return false;
    try {
      final activated = await rc.fetchAndActivate().timeout(
        _hardTimeout,
        onTimeout: () => false,
      );
      _apply(rc);
      return activated;
    } catch (e) {
      if (kDebugMode) debugPrint('RemoteConfigService.refresh failed: $e');
      return false;
    }
  }

  void _apply(FirebaseRemoteConfig rc) {
    final api = rc.getString(kApiBaseUrl);

    ApiConfig.applyRemoteBaseUrl(api);

    if (kDebugMode) {
      debugPrint('RemoteConfig applied → api=${ApiConfig.baseUrl}');
    }
  }
}
