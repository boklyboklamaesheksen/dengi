import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Google Play `UpdateAvailability` codes.
abstract final class PlayUpdateAvailability {
  static const int unknown = 0;
  static const int notAvailable = 1;
  static const int available = 2;
  static const int developerTriggeredInProgress = 3;
}

/// Google Play `InstallStatus` codes.
abstract final class PlayInstallStatus {
  static const int unknown = 0;
  static const int pending = 1;
  static const int downloading = 2;
  static const int installing = 3;
  static const int installed = 4;
  static const int failed = 5;
  static const int canceled = 6;
  static const int requiresUiIntent = 10;
  static const int downloaded = 11;
}

/// Snapshot of Google Play's `AppUpdateInfo`.
@immutable
class PlayUpdateInfo {
  const PlayUpdateInfo({
    required this.updateAvailability,
    required this.installStatus,
    this.availableVersionCode = 0,
    this.updatePriority = 0,
    this.stalenessDays,
    this.flexibleAllowed = false,
    this.immediateAllowed = false,
  });

  factory PlayUpdateInfo.fromMap(Map<dynamic, dynamic> map) {
    int asInt(Object? value) => value is int ? value : 0;
    return PlayUpdateInfo(
      updateAvailability: asInt(map['updateAvailability']),
      installStatus: asInt(map['installStatus']),
      availableVersionCode: asInt(map['availableVersionCode']),
      updatePriority: asInt(map['updatePriority']),
      stalenessDays: map['clientVersionStalenessDays'] as int?,
      flexibleAllowed: map['flexibleAllowed'] == true,
      immediateAllowed: map['immediateAllowed'] == true,
    );
  }

  final int updateAvailability;
  final int installStatus;
  final int availableVersionCode;

  /// 0–5, set per release through the Play Developer API (0 by default).
  final int updatePriority;
  final int? stalenessDays;
  final bool flexibleAllowed;
  final bool immediateAllowed;

  bool get isUpdateAvailable =>
      updateAvailability == PlayUpdateAvailability.available;
  bool get isUpdateInProgress =>
      updateAvailability == PlayUpdateAvailability.developerTriggeredInProgress;
  bool get isDownloaded => installStatus == PlayInstallStatus.downloaded;
  bool get isDownloading =>
      installStatus == PlayInstallStatus.pending ||
      installStatus == PlayInstallStatus.downloading;
}

enum PlayUpdateType { flexible, immediate }

enum PlayUpdateFlowResult {
  accepted,
  canceled,
  failed,
  notAllowed,
  unavailable,
}

/// Dart side of `PlayStoreBridge.kt`: Google Play In-App Review and
/// In-App Updates. Every call degrades to a no-op result off Android, in
/// tests and in builds that were not installed from Google Play.
class PlayStoreBridge {
  PlayStoreBridge({bool? platformSupported})
    : _platformSupportedOverride = platformSupported;

  static const MethodChannel _channel = MethodChannel(
    'app.rabochiy.vpn/play_store',
  );
  static const EventChannel _updateEvents = EventChannel(
    'app.rabochiy.vpn/play_store/update_state',
  );

  final bool? _platformSupportedOverride;
  Stream<int>? _installStatuses;

  bool get isSupported => _platformSupportedOverride ?? Platform.isAndroid;

  /// Runs Google's review flow. `true` means Play finished the flow; the API
  /// never reveals whether the card was actually shown or a review written.
  Future<bool> requestReview() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<String>('requestReview') ==
          'completed';
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// `null` when Play cannot answer (not installed from Play, no Play Store).
  Future<PlayUpdateInfo?> getUpdateInfo() async {
    if (!isSupported) return null;
    try {
      final Map<dynamic, dynamic>? raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getUpdateInfo');
      return raw == null ? null : PlayUpdateInfo.fromMap(raw);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Shows Play's update UI; completes when the user accepts or declines.
  Future<PlayUpdateFlowResult> startUpdate(PlayUpdateType type) async {
    if (!isSupported) return PlayUpdateFlowResult.unavailable;
    try {
      final String? outcome = await _channel.invokeMethod<String>(
        'startUpdate',
        <String, String>{'type': type.name},
      );
      switch (outcome) {
        case 'accepted':
          return PlayUpdateFlowResult.accepted;
        case 'canceled':
          return PlayUpdateFlowResult.canceled;
        case 'not_allowed':
          return PlayUpdateFlowResult.notAllowed;
        case 'unavailable':
          return PlayUpdateFlowResult.unavailable;
        default:
          return PlayUpdateFlowResult.failed;
      }
    } on PlatformException {
      return PlayUpdateFlowResult.failed;
    } on MissingPluginException {
      return PlayUpdateFlowResult.unavailable;
    }
  }

  /// Installs a downloaded flexible update; Play restarts the app.
  Future<bool> completeUpdate() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('completeUpdate') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// [PlayInstallStatus] changes of a flexible update.
  Stream<int> get installStatuses {
    if (!isSupported) return const Stream<int>.empty();
    return _installStatuses ??= _updateEvents
        .receiveBroadcastStream()
        .where((dynamic event) => event is Map)
        .map((dynamic event) {
          final Object? status =
              (event as Map<dynamic, dynamic>)['installStatus'];
          return status is int ? status : PlayInstallStatus.unknown;
        });
  }
}
