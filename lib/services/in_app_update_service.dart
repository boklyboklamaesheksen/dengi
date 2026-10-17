import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'play_store_bridge.dart';

/// The Play update UI [InAppUpdateService] wants to show next.
enum UpdateOffer { none, flexible, immediate }

/// Google Play In-App Updates.
///
/// * Flexible (default): Play's own "Update available" dialog inside the
///   app. The download runs in the background while the VPN keeps working;
///   afterwards `PlayPromptsHost` shows a "Restart" snackbar.
/// * Immediate (full screen, blocks the app until updated): only for
///   releases published with in-app update priority >= [immediatePriority]
///   (set through the Play Developer API; Play Console uploads get 0).
class InAppUpdateService {
  InAppUpdateService({PlayStoreBridge? bridge, DateTime Function()? now})
    : _bridge = bridge ?? PlayStoreBridge(),
      _now = now ?? DateTime.now;

  static final InAppUpdateService instance = InAppUpdateService();

  static const int immediatePriority = 4;

  /// After "No thanks" the flexible dialog stays quiet this long.
  static const Duration declineCooldown = Duration(days: 3);

  static const String _declinedAtKey = 'rabochiy_update_declined_at_ms_v1';
  static const String _flowTypeKey = 'rabochiy_update_flow_type_v1';

  final PlayStoreBridge _bridge;
  final DateTime Function() _now;

  /// A flexible update is downloaded and waits for [completeUpdate].
  final ValueNotifier<bool> readyToInstall = ValueNotifier<bool>(false);

  PlayUpdateInfo? _info;
  bool _prefsLoaded = false;
  int? _declinedAtMs;
  String? _flowType;
  bool _refreshing = false;
  bool _flowInFlight = false;
  bool _offeredThisRun = false;
  bool _downloading = false;
  StreamSubscription<int>? _installStatusSub;

  /// What should be shown next, judged from the last [refresh].
  UpdateOffer get pendingOffer {
    final PlayUpdateInfo? info = _info;
    if (info == null ||
        !info.isUpdateAvailable ||
        _offeredThisRun ||
        _flowInFlight) {
      return UpdateOffer.none;
    }
    if (info.updatePriority >= immediatePriority && info.immediateAllowed) {
      return UpdateOffer.immediate;
    }
    if (!info.flexibleAllowed) return UpdateOffer.none;
    final int? declinedAt = _declinedAtMs;
    if (declinedAt != null &&
        _now().millisecondsSinceEpoch - declinedAt <
            declineCooldown.inMilliseconds) {
      return UpdateOffer.none;
    }
    return UpdateOffer.flexible;
  }

  /// The review card waits while any update UI is pending or running.
  bool get blocksReview =>
      _offeredThisRun ||
      _flowInFlight ||
      _downloading ||
      readyToInstall.value ||
      pendingOffer != UpdateOffer.none;

  /// Reads the update state from Play. Call on start and on every resume.
  Future<void> refresh() async {
    if (_refreshing || !_bridge.isSupported) return;
    _refreshing = true;
    try {
      await _loadPrefs();
      final PlayUpdateInfo? info = await _bridge.getUpdateInfo();
      _info = info;
      if (info == null) return;
      _downloading = info.isDownloading;
      readyToInstall.value = info.isDownloaded;
      if (info.isDownloading || info.isDownloaded) _listenToInstallStatus();

      if (info.isUpdateInProgress &&
          !info.isDownloaded &&
          _flowType == PlayUpdateType.immediate.name &&
          !_flowInFlight) {
        // The user accepted an immediate update, then left Play's screen.
        _offeredThisRun = true;
        await _runFlow(PlayUpdateType.immediate);
      } else if (!info.isUpdateInProgress &&
          !info.isDownloading &&
          !info.isDownloaded) {
        await _saveFlowType(null);
      }
    } finally {
      _refreshing = false;
    }
  }

  /// Shows Play's own UI for [pendingOffer] (at most once per app run).
  Future<void> showPendingOffer() async {
    final UpdateOffer offer = pendingOffer;
    if (offer == UpdateOffer.none) return;
    _offeredThisRun = true;
    final PlayUpdateType type = offer == UpdateOffer.immediate
        ? PlayUpdateType.immediate
        : PlayUpdateType.flexible;
    final PlayUpdateFlowResult result = await _runFlow(type);
    if (type == PlayUpdateType.flexible &&
        result == PlayUpdateFlowResult.canceled) {
      final int nowMs = _now().millisecondsSinceEpoch;
      _declinedAtMs = nowMs;
      await _saveInt(_declinedAtKey, nowMs);
    }
  }

  /// Installs the downloaded flexible update; Play restarts the app.
  Future<void> completeUpdate() async {
    if (!readyToInstall.value) return;
    if (!await _bridge.completeUpdate()) {
      // The download may have expired or failed: re-read the real state.
      await refresh();
    }
  }

  Future<PlayUpdateFlowResult> _runFlow(PlayUpdateType type) async {
    _flowInFlight = true;
    try {
      await _saveFlowType(type.name);
      // Google: register the progress listener before a flexible flow.
      if (type == PlayUpdateType.flexible) _listenToInstallStatus();
      final PlayUpdateFlowResult result = await _bridge.startUpdate(type);
      if (type == PlayUpdateType.flexible &&
          result == PlayUpdateFlowResult.accepted) {
        _downloading = true;
      }
      return result;
    } finally {
      _flowInFlight = false;
    }
  }

  void _listenToInstallStatus() {
    _installStatusSub ??= _bridge.installStatuses.listen((int status) {
      _downloading =
          status == PlayInstallStatus.pending ||
          status == PlayInstallStatus.downloading;
      if (status == PlayInstallStatus.downloaded) {
        readyToInstall.value = true;
      } else if (status == PlayInstallStatus.installed ||
          status == PlayInstallStatus.failed ||
          status == PlayInstallStatus.canceled) {
        readyToInstall.value = false;
      }
    }, onError: (Object _) {});
  }

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _declinedAtMs = prefs.getInt(_declinedAtKey);
      _flowType = prefs.getString(_flowTypeKey);
    } catch (_) {
      // Storage unavailable: no cooldown, no flow to resume.
    }
    _prefsLoaded = true;
  }

  Future<void> _saveFlowType(String? type) async {
    if (_flowType == type) return;
    _flowType = type;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (type == null) {
        await prefs.remove(_flowTypeKey);
      } else {
        await prefs.setString(_flowTypeKey, type);
      }
    } catch (_) {}
  }

  Future<void> _saveInt(String key, int value) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, value);
    } catch (_) {}
  }
}
