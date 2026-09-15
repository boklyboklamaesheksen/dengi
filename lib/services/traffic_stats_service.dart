import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single one-hour aggregate of VPN traffic usage.
///
/// Buckets are aligned to wall-clock UTC hours; `startMs` is the UNIX
/// millisecond timestamp of the beginning of the bucket.
@immutable
class TrafficBucket {
  const TrafficBucket({
    required this.startMs,
    required this.rxBytes,
    required this.txBytes,
    required this.sessions,
    required this.onlineSeconds,
  });

  final int startMs;
  final int rxBytes;
  final int txBytes;
  final int sessions;
  final int onlineSeconds;

  int get totalBytes => rxBytes + txBytes;

  TrafficBucket plus({
    int rx = 0,
    int tx = 0,
    int sessions = 0,
    int onlineSeconds = 0,
  }) =>
      TrafficBucket(
        startMs: startMs,
        rxBytes: rxBytes + rx,
        txBytes: txBytes + tx,
        sessions: this.sessions + sessions,
        onlineSeconds: this.onlineSeconds + onlineSeconds,
      );

  Map<String, Object> toJson() => <String, Object>{
        't': startMs,
        'r': rxBytes,
        'u': txBytes,
        's': sessions,
        'o': onlineSeconds,
      };

  static TrafficBucket fromJson(Map<String, dynamic> json) => TrafficBucket(
        startMs: (json['t'] as num).toInt(),
        rxBytes: (json['r'] as num?)?.toInt() ?? 0,
        txBytes: (json['u'] as num?)?.toInt() ?? 0,
        sessions: (json['s'] as num?)?.toInt() ?? 0,
        onlineSeconds: (json['o'] as num?)?.toInt() ?? 0,
      );
}

/// Aggregated totals for a user-selected period.
@immutable
class TrafficSummary {
  const TrafficSummary({
    required this.rxBytes,
    required this.txBytes,
    required this.sessions,
    required this.onlineSeconds,
    required this.buckets,
  });

  final int rxBytes;
  final int txBytes;
  final int sessions;
  final int onlineSeconds;

  /// Hour-level buckets covering the requested period, ordered by time.
  /// Missing hours are present with zero values so charts stay continuous.
  final List<TrafficBucket> buckets;

  int get totalBytes => rxBytes + txBytes;

  bool get isEmpty => totalBytes == 0 && sessions == 0;
}

/// Available pre-set periods.
enum TrafficPeriod { hour, day, week, month, halfYear, year, all }

extension TrafficPeriodExtension on TrafficPeriod {
  Duration? get lookback {
    switch (this) {
      case TrafficPeriod.hour:
        return const Duration(hours: 1);
      case TrafficPeriod.day:
        return const Duration(days: 1);
      case TrafficPeriod.week:
        return const Duration(days: 7);
      case TrafficPeriod.month:
        return const Duration(days: 30);
      case TrafficPeriod.halfYear:
        return const Duration(days: 182);
      case TrafficPeriod.year:
        return const Duration(days: 365);
      case TrafficPeriod.all:
        return null;
    }
  }
}

/// Persists hourly buckets of bytes transferred through the VPN tunnel and
/// exposes summaries for the UI.
///
/// Design notes
/// ------------
/// * We store at most 1 year + 1 day of hourly buckets. Older ones are
///   pruned on every write so SharedPreferences never grows unbounded.
/// * Writes are **throttled**: `addBytes` coalesces multiple bumps into a
///   single persistence round-trip every 10 s, which matters because the
///   metric stream emits deltas several times per second.
/// * The service is a [ChangeNotifier] so the stats screen can rebuild
///   automatically as new samples land.
class TrafficStatsService extends ChangeNotifier {
  TrafficStatsService();

  static const String _prefsKey = 'rabochiy_traffic_buckets_v1';
  static const Duration _retainFor = Duration(days: 366);
  static const Duration _flushThrottle = Duration(seconds: 10);

  final Map<int, TrafficBucket> _buckets = <int, TrafficBucket>{};

  Timer? _flushTimer;
  bool _dirty = false;
  bool _loaded = false;
  int _lastSampleRx = 0;
  int _lastSampleTx = 0;
  int _lastTickMs = 0;

  bool get isLoaded => _loaded;

  /// Loads persisted buckets from disk. Safe to call multiple times.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
        for (final dynamic item in decoded) {
          if (item is Map) {
            final TrafficBucket b =
                TrafficBucket.fromJson(Map<String, dynamic>.from(item));
            _buckets[b.startMs] = b;
          }
        }
      }
    } catch (_) {
      // Corrupt storage — start fresh; no re-raise.
    }
    _pruneOld();
    _loaded = true;
    notifyListeners();
  }

  /// Records a connection *session start* — called once per successful
  /// connect so the stats screen can report "sessions" count.
  void recordSessionStart() {
    _lastSampleRx = 0;
    _lastSampleTx = 0;
    _lastTickMs = DateTime.now().millisecondsSinceEpoch;
    _bump(
      rx: 0,
      tx: 0,
      sessionsDelta: 1,
      onlineDelta: 0,
    );
  }

  /// Called roughly once a second while connected with the cumulative
  /// RX / TX counters from the VPN engine. The service derives a delta and
  /// attributes it to the current wall-clock hour bucket.
  void recordSample({
    required int totalRxBytes,
    required int totalTxBytes,
  }) {
    if (!_loaded) return;

    // Engine counters reset to 0 whenever the tunnel restarts. If we see a
    // smaller value than before, assume a fresh session and reset the
    // delta baseline so we don't subtract anything from the history.
    int rxDelta = totalRxBytes - _lastSampleRx;
    int txDelta = totalTxBytes - _lastSampleTx;
    if (rxDelta < 0 || txDelta < 0) {
      rxDelta = math.max(totalRxBytes, 0);
      txDelta = math.max(totalTxBytes, 0);
    }
    _lastSampleRx = totalRxBytes;
    _lastSampleTx = totalTxBytes;

    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final int onlineDelta = _lastTickMs > 0
        ? ((nowMs - _lastTickMs) ~/ 1000).clamp(0, 3600)
        : 0;
    _lastTickMs = nowMs;

    if (rxDelta <= 0 && txDelta <= 0 && onlineDelta <= 0) return;

    _bump(
      rx: rxDelta,
      tx: txDelta,
      sessionsDelta: 0,
      onlineDelta: onlineDelta,
    );
  }

  /// Forgets the "last seen" counters so the next sample won't contribute
  /// a huge bogus delta. Call on disconnect.
  void resetSession() {
    _lastSampleRx = 0;
    _lastSampleTx = 0;
    _lastTickMs = 0;
  }

  /// Returns an aggregated view for the given period.
  TrafficSummary summaryFor(TrafficPeriod period) {
    if (!_loaded) {
      return const TrafficSummary(
        rxBytes: 0,
        txBytes: 0,
        sessions: 0,
        onlineSeconds: 0,
        buckets: <TrafficBucket>[],
      );
    }

    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final Duration? lookback = period.lookback;
    final int fromMs = lookback == null ? 0 : nowMs - lookback.inMilliseconds;

    int rx = 0;
    int tx = 0;
    int sessions = 0;
    int online = 0;

    final List<TrafficBucket> sorted = _buckets.values
        .where((TrafficBucket b) => b.startMs >= fromMs)
        .toList(growable: false)
      ..sort((TrafficBucket a, TrafficBucket b) => a.startMs.compareTo(b.startMs));

    for (final TrafficBucket b in sorted) {
      rx += b.rxBytes;
      tx += b.txBytes;
      sessions += b.sessions;
      online += b.onlineSeconds;
    }

    return TrafficSummary(
      rxBytes: rx,
      txBytes: tx,
      sessions: sessions,
      onlineSeconds: online,
      buckets: sorted,
    );
  }

  /// Wipes every persisted bucket.
  Future<void> reset() async {
    _buckets.clear();
    _dirty = true;
    await _flushNow();
    notifyListeners();
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    // Best-effort synchronous flush on dispose.
    if (_dirty) {
      unawaited(_flushNow());
    }
    super.dispose();
  }

  // ─── internals ─────────────────────────────────────────────────────────

  void _bump({
    required int rx,
    required int tx,
    required int sessionsDelta,
    required int onlineDelta,
  }) {
    final int hourStartMs = _currentHourStartMs();
    final TrafficBucket existing = _buckets[hourStartMs] ??
        TrafficBucket(
          startMs: hourStartMs,
          rxBytes: 0,
          txBytes: 0,
          sessions: 0,
          onlineSeconds: 0,
        );
    _buckets[hourStartMs] = existing.plus(
      rx: rx,
      tx: tx,
      sessions: sessionsDelta,
      onlineSeconds: onlineDelta,
    );
    _dirty = true;
    notifyListeners();
    _scheduleFlush();
  }

  int _currentHourStartMs() {
    final DateTime now = DateTime.now();
    final DateTime hourStart =
        DateTime(now.year, now.month, now.day, now.hour);
    return hourStart.millisecondsSinceEpoch;
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushThrottle, _flushNow);
  }

  Future<void> _flushNow() async {
    if (!_dirty) return;
    _pruneOld();
    _dirty = false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<Map<String, Object>> serialised = _buckets.values
          .map((TrafficBucket b) => b.toJson())
          .toList(growable: false);
      await prefs.setString(_prefsKey, jsonEncode(serialised));
    } catch (_) {
      // Ignore — we'll try again on the next bump.
    }
  }

  void _pruneOld() {
    final int threshold = DateTime.now()
        .subtract(_retainFor)
        .millisecondsSinceEpoch;
    _buckets.removeWhere((int start, _) => start < threshold);
  }
}

