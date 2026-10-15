import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import '../config/secret_codec.dart';
import 'api_host_service.dart';
import 'vless_subscription_service.dart';

/// Backend domain updates via Firebase Remote Config.
///
/// Keys (Firebase Console → Remote Config), values in gwenc1 format
/// (see [SecretCodec] and docs/REMOTE_CONFIG.md):
///   - `encrypted_api_url` — backend URL or wildcard template
///     `https://*.api.example.com`, applied through [ApiHostService];
///   - `encrypted_api_fallback_url` — optional reserve address for
///     automatic failover (empty = none);
///   - `encrypted_vless_sub_urls` — VLESS subscription URL(s), applied
///     through [VlessSubscriptionSources] (empty = VLESS servers off).
///
/// The legacy plain-text `api_base_url` key is intentionally NOT read:
/// the Remote Config JSON must not expose a URL used by new versions.
/// Only values whose source is the server (`valueRemote`) are applied, so
/// in-app defaults never overwrite an address received earlier.
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  static const String kEncryptedApiUrl = 'encrypted_api_url';
  static const String kEncryptedApiFallbackUrl = 'encrypted_api_fallback_url';
  static const String kEncryptedVlessSubUrls = 'encrypted_vless_sub_urls';

  /// Per fetchAndActivate call: the SDK occasionally hangs when the ISP
  /// resets the connection, and an unbounded wait risks an ANR.
  static const Duration _hardTimeout = Duration(seconds: 20);

  /// Background re-fetch in a live process: a new domain reaches users who
  /// keep the app (and the VPN) running for days.
  static const Duration _steadyRefreshInterval = Duration(minutes: 10);

  /// Startup attempts; the pause doubles: 3 s, 6 s, 12 s, 24 s.
  static const int _maxBootRetries = 5;

  /// Duration.zero on thousands of devices hits the hourly Firebase quota
  /// (throttling). Console changes still arrive instantly through the
  /// real-time listener, which bypasses this interval.
  static const Duration _minFetchInterval = kDebugMode
      ? Duration.zero
      : Duration(minutes: 5);

  FirebaseRemoteConfig? _rc;
  Timer? _steadyTimer;
  StreamSubscription<RemoteConfigUpdate>? _realtimeSub;
  Future<bool>? _inFlight;
  bool _started = false;
  final Completer<void> _firstFetch = Completer<void>();

  /// Startup initialisation. Never throws: a Remote Config failure must not
  /// break app launch; the restored/default address stays in effect.
  Future<void> initialize() async {
    if (_started) return;
    _started = true;
    if (ApiConfig.hasDevOverride) {
      _completeFirstFetch();
      return;
    }
    try {
      final rc = FirebaseRemoteConfig.instance;
      _rc = rc;

      await rc.setDefaults(<String, dynamic>{
        kEncryptedApiUrl: ApiConfig.defaultBaseUrlEncrypted,
        kEncryptedApiFallbackUrl: '',
        kEncryptedVlessSubUrls: ApiConfig.defaultVlessSubscriptionsEncrypted,
      });
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 30),
          minimumFetchInterval: _minFetchInterval,
        ),
      );

      // Values activated in an earlier session are usable right away.
      _apply(rc);

      await _realtimeSub?.cancel();
      _realtimeSub = rc.onConfigUpdated.listen(
        (_) async {
          try {
            await rc.activate();
            _apply(rc);
          } catch (e) {
            _log('real-time activate failed: ${e.runtimeType}');
          }
        },
        onError: (Object e) => _log('real-time stream error: ${e.runtimeType}'),
      );

      unawaited(_fetchLoop());
    } catch (e) {
      _log('initialize failed: ${e.runtimeType}');
      _completeFirstFetch();
    }
  }

  /// Forces a fetch now. Returns true when the fetch succeeded.
  Future<bool> refresh() => _inFlight ??= _fetchOnce().whenComplete(() {
    _inFlight = null;
  });

  /// Waits (bounded) for the first Remote Config answer on a device that has
  /// never received one, so account creation/login on a fresh install does
  /// not hit a stale baked-in domain. Returns immediately otherwise.
  Future<void> ensureReady({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_rc == null || ApiHostService.instance.hasRemoteSource) return;
    try {
      await _firstFetch.future.timeout(timeout);
    } on TimeoutException {
      // Continue on the default; failover covers a blocked host.
    }
  }

  Future<bool> _fetchOnce() async {
    final rc = _rc;
    if (rc == null) return false;
    try {
      var timedOut = false;
      await rc.fetchAndActivate().timeout(
        _hardTimeout,
        onTimeout: () {
          timedOut = true;
          return false;
        },
      );
      _apply(rc);
      // Throttled still means Firebase answered: stop the boot retries.
      final ok =
          !timedOut &&
          rc.lastFetchStatus != RemoteConfigFetchStatus.failure &&
          rc.lastFetchStatus != RemoteConfigFetchStatus.noFetchYet;
      if (ok) _completeFirstFetch();
      return ok;
    } catch (e) {
      _log('fetch failed: ${e.runtimeType}');
      return false;
    }
  }

  Future<void> _fetchLoop() async {
    var delay = const Duration(seconds: 3);
    for (var attempt = 0; attempt < _maxBootRetries; attempt++) {
      if (await refresh()) break;
      if (attempt < _maxBootRetries - 1) {
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
    _completeFirstFetch();
    _steadyTimer ??= Timer.periodic(
      _steadyRefreshInterval,
      (_) => unawaited(refresh()),
    );
  }

  void _apply(FirebaseRemoteConfig rc) {
    try {
      final api = rc.getValue(kEncryptedApiUrl);
      if (api.source == ValueSource.valueRemote) {
        final decoded = SecretCodec.tryDecode(api.asString());
        if (decoded == null || !ApiHostService.instance.apply(decoded)) {
          _log('ignored invalid $kEncryptedApiUrl');
        }
      }

      final reserve = rc.getValue(kEncryptedApiFallbackUrl);
      if (reserve.source == ValueSource.valueRemote) {
        final decoded = SecretCodec.tryDecode(reserve.asString());
        if (decoded == null || !ApiHostService.instance.applyReserve(decoded)) {
          _log('ignored invalid $kEncryptedApiFallbackUrl');
        }
      }

      final vless = rc.getValue(kEncryptedVlessSubUrls);
      if (vless.source == ValueSource.valueRemote &&
          !VlessSubscriptionSources.instance.apply(vless.asString())) {
        _log('ignored invalid $kEncryptedVlessSubUrls');
      }
    } catch (e) {
      _log('apply failed: ${e.runtimeType}');
    }
  }

  void _completeFirstFetch() {
    if (!_firstFetch.isCompleted) _firstFetch.complete();
  }

  // Never log addresses, not even in debug builds.
  void _log(String message) {
    if (kDebugMode) debugPrint('RemoteConfigService: $message');
  }
}
