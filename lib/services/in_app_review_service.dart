import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'play_store_bridge.dart';
import 'vpn_service.dart';

/// When the Google Play review card may be requested.
@immutable
class ReviewPromptPolicy {
  const ReviewPromptPolicy({
    this.minGoodSessions = 2,
    this.goodSessionBytes = 10 * 1024 * 1024,
    this.heavySessionBytes = 50 * 1024 * 1024,
    this.afterDisconnectWindow = const Duration(minutes: 1),
    this.retryInterval = const Duration(days: 60),
    this.maxAttempts = 3,
  });

  /// VPN sessions that each carried at least [goodSessionBytes] (rx + tx).
  final int minGoodSessions;
  final int goodSessionBytes;

  /// One session this large is enough on its own (users who never
  /// disconnect would otherwise wait forever for a second session).
  final int heavySessionBytes;

  /// How long after the user ends a good session it still counts.
  final Duration afterDisconnectWindow;

  /// Gap between attempts. Play applies its own quota on top (it may not
  /// show the card if asked more than about once a month).
  final Duration retryInterval;
  final int maxAttempts;
}

/// Decides when to ask Google Play for its in-app review card.
///
/// Google's rules: nothing may be asked before the card (no "Do you like
/// the app?"), it must not be opened from a button, nothing may be offered
/// for a rating, and the API never reveals whether the card was shown.
/// So the card is only requested right after the VPN has clearly worked:
/// the live (or just ended) session carried real traffic and the user has
/// had [ReviewPromptPolicy.minGoodSessions] such sessions. `PlayPromptsHost`
/// additionally waits for a calm moment on the VPN tab.
class InAppReviewService {
  InAppReviewService({
    PlayStoreBridge? bridge,
    DateTime Function()? now,
    this.policy = const ReviewPromptPolicy(),
  }) : _bridge = bridge ?? PlayStoreBridge(),
       _now = now ?? DateTime.now;

  static const String _goodSessionsKey = 'rabochiy_review_good_sessions_v1';
  static const String _attemptsKey = 'rabochiy_review_attempts_v1';
  static const String _lastAttemptKey = 'rabochiy_review_last_attempt_ms_v1';

  final PlayStoreBridge _bridge;
  final DateTime Function() _now;
  final ReviewPromptPolicy policy;

  bool _loaded = false;
  bool _disposed = false;
  int _goodSessions = 0;
  int _attempts = 0;
  int? _lastAttemptMs;

  // Live or last VPN session, fed by AppProvider.
  bool _sessionActive = false;
  bool _sessionGood = false;
  bool _sessionCountable = true;
  bool _sessionFailed = false;
  int _sessionBytes = 0;
  DateTime? _sessionEndedAt;

  bool _requestedThisRun = false;
  bool _inFlight = false;

  bool get isLoaded => _loaded;
  int get goodSessions => _goodSessions;
  int get attempts => _attempts;

  Future<void> load() async {
    if (_loaded || _disposed) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      _goodSessions = prefs.getInt(_goodSessionsKey) ?? 0;
      _attempts = prefs.getInt(_attemptsKey) ?? 0;
      _lastAttemptMs = prefs.getInt(_lastAttemptKey);
    } catch (_) {
      // Storage unavailable: behave like a fresh install.
    }
    _loaded = true;
  }

  /// Every VPN status change, in order. [restored]: a session that was
  /// already running before this app instance started (the previous one
  /// may have counted it, so it never counts again).
  void onVpnStatus(VpnStatus status, {bool restored = false}) {
    switch (status) {
      case VpnStatus.connected:
        _sessionActive = true;
        _sessionGood = false;
        _sessionCountable = !restored;
        _sessionFailed = false;
        _sessionBytes = 0;
        _sessionEndedAt = null;
      case VpnStatus.disconnected:
        if (_sessionActive) {
          _sessionActive = false;
          _sessionEndedAt = _now();
        }
      case VpnStatus.error:
        _sessionActive = false;
        _sessionFailed = true;
        _sessionEndedAt = null;
      case VpnStatus.connecting:
        // A new attempt ends the "just finished a good session" moment.
        _sessionEndedAt = null;
      case VpnStatus.disconnecting:
        break;
    }
  }

  /// [sessionBytes]: rx + tx carried by the live session so far.
  void onSessionTraffic(int sessionBytes) {
    if (!_sessionActive || _disposed) return;
    _sessionBytes = sessionBytes;
    // Before load() the stored count is unknown; the next sample counts it.
    if (_sessionGood || !_loaded || sessionBytes < policy.goodSessionBytes) {
      return;
    }
    _sessionGood = true;
    if (!_sessionCountable) return;
    _goodSessions++;
    unawaited(_saveInt(_goodSessionsKey, _goodSessions));
  }

  /// Logout / account deletion: the current session is no longer a moment
  /// to ask. Stored counters are kept (reviews belong to the Play account).
  void forgetSession() {
    _sessionActive = false;
    _sessionGood = false;
    _sessionBytes = 0;
    _sessionEndedAt = null;
  }

  /// Whether the VPN side makes this a good moment; the caller checks the UI.
  bool shouldRequestReview(VpnStatus status) {
    if (!_loaded || _disposed || _requestedThisRun || _inFlight) return false;
    if (_attempts >= policy.maxAttempts) return false;
    final DateTime now = _now();
    final int? lastAttempt = _lastAttemptMs;
    if (lastAttempt != null &&
        now.millisecondsSinceEpoch - lastAttempt <
            policy.retryInterval.inMilliseconds) {
      return false;
    }
    if (!_sessionGood) return false;
    if (_goodSessions < policy.minGoodSessions &&
        _sessionBytes < policy.heavySessionBytes) {
      return false;
    }
    switch (status) {
      case VpnStatus.connected:
        return _sessionActive;
      case VpnStatus.disconnected:
        final DateTime? endedAt = _sessionEndedAt;
        return !_sessionActive &&
            !_sessionFailed &&
            endedAt != null &&
            now.difference(endedAt) <= policy.afterDisconnectWindow;
      case VpnStatus.connecting:
      case VpnStatus.disconnecting:
      case VpnStatus.error:
        return false;
    }
  }

  /// Asks Play for the review card, at most once per app run.
  Future<void> requestReview() async {
    if (_inFlight || _requestedThisRun || _disposed) return;
    _inFlight = true;
    _requestedThisRun = true;
    try {
      final bool launched = await _bridge.requestReview();
      if (!launched || _disposed) return;
      final int nowMs = _now().millisecondsSinceEpoch;
      _attempts++;
      _lastAttemptMs = nowMs;
      await _saveInt(_attemptsKey, _attempts);
      await _saveInt(_lastAttemptKey, nowMs);
    } finally {
      _inFlight = false;
    }
  }

  void dispose() {
    _disposed = true;
  }

  Future<void> _saveInt(String key, int value) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, value);
    } catch (_) {
      // Best effort: the worst case is one extra prompt attempt later.
    }
  }
}
