import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../models/server_config_model.dart';
import 'gw_engine_service.dart';

/// VPN connection status shared by all protocol engines.
enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

/// Snapshot delivered on the engine status stream. The provider reads
/// `state`, `download`, `upload`, `downloadSpeed`, `uploadSpeed`.
class EngineStatus {
  final String state;          // "CONNECTED" | "DISCONNECTED" | "CONNECTING" | "ERROR"
  final int duration;          // seconds since connect
  final int downloadSpeed;     // bytes / second
  final int uploadSpeed;       // bytes / second
  final int download;          // cumulative bytes for the live session
  final int upload;            // cumulative bytes for the live session

  const EngineStatus({
    required this.state,
    required this.duration,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.download,
    required this.upload,
  });

  factory EngineStatus.empty() => const EngineStatus(
        state: 'DISCONNECTED',
        duration: 0,
        downloadSpeed: 0,
        uploadSpeed: 0,
        download: 0,
        upload: 0,
      );

  factory EngineStatus.fromMap(Map<dynamic, dynamic> map) {
    return EngineStatus(
      state: (map['state'] ?? 'DISCONNECTED').toString(),
      duration: _toInt(map['duration']),
      downloadSpeed: _toInt(map['downloadSpeed']),
      uploadSpeed: _toInt(map['uploadSpeed']),
      download: _toInt(map['download']),
      upload: _toInt(map['upload']),
    );
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.isFinite ? v.toInt() : 0;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

/// Bridge between Flutter and the native Zapret VPN engine.
///
/// On Android the native side hosts the AmneziaWG backend
/// (`AwgManager` / `libwg-go.so`) for `ServerProtocol.awg`, plus the
/// separate GW SSH-tunnel engine for `ServerProtocol.gw` and the Xray-core
/// engine (`XrayVpnService`) for `ServerProtocol.vless`.
///
/// Communication is done via two channels:
///  - **MethodChannel** `rabochiy_vpn/engine` — synchronous control
///    (initialize / connect / disconnect / pingServer / requestPermission).
///  - **EventChannel** `rabochiy_vpn/engine/status` — push status updates
///    and traffic counters (1 Hz).
class VpnService {
  /// [platformSupported] overrides the `Platform.isAndroid` probe so the
  /// bridge logic can be exercised from `flutter test` on any host.
  VpnService({
    bool? platformSupported,
    this.gwConnectTimeout = const Duration(seconds: 120),
    this.gwStopTimeout = const Duration(seconds: 5),
  }) : _platformSupportedOverride = platformSupported;

  /// Upper bound for a GW connect; the engine's own four SSH attempts take
  /// about 105 s against a dead node.
  final Duration gwConnectTimeout;

  /// How long a GW disconnect waits for the engine's DISCONNECTED.
  final Duration gwStopTimeout;

  static const MethodChannel _control = MethodChannel('rabochiy_vpn/engine');
  static const EventChannel _events = EventChannel('rabochiy_vpn/engine/status');

  final bool? _platformSupportedOverride;

  /// Bumped by every connect / disconnect / cancel. A connect attempt
  /// captures the value and ignores its own late result once the counter
  /// has moved on — the native AWG connect now blocks until the first
  /// handshake (or a timeout), so a cancel or server switch routinely
  /// overlaps an in-flight attempt.
  int _connectGeneration = 0;

  VpnStatus _status = VpnStatus.disconnected;
  ServerConfig? _currentConfig;

  /// Engine whose events drive [status]. Unlike [_currentConfig] it stays
  /// set while a GW tunnel is still stopping: the GW engine reports
  /// DISCONNECTED from a worker thread after `disconnect` has returned, and
  /// dropping that event left the UI on "Disconnecting…" forever.
  ServerProtocol? _engine;

  /// Pending GW connect: true on the engine's CONNECTED, false on its
  /// DISCONNECTED/ERROR once it has started this attempt.
  Completer<bool>? _gwOutcome;
  bool _gwAttemptStarted = false;

  /// Completed by the GW engine's DISCONNECTED/ERROR while stopping.
  Completer<void>? _gwStopped;

  /// Engine found running by [initialize]: the UI was recreated (app swiped
  /// from recents, activity destroyed) while the tunnel stayed up.
  ServerProtocol? _restoredEngine;
  ServerProtocol? get restoredEngine => _restoredEngine;
  String? _errorMessage;
  StreamSubscription<dynamic>? _eventsSub;
  StreamSubscription<String>? _gwEventsSub;
  bool _disposed = false;

  // GW engine reports cumulative counters ~1 Hz; derive byte/s speeds
  // from the deltas (the AWG path gets them natively).
  int _gwLastRx = 0;
  int _gwLastTx = 0;
  int? _gwLastTrafficTime;

  final _statusController = StreamController<VpnStatus>.broadcast();
  Stream<VpnStatus> get statusStream => _statusController.stream;

  final _engineStatusController = StreamController<EngineStatus>.broadcast();
  Stream<EngineStatus> get engineStatusStream => _engineStatusController.stream;

  VpnStatus get status => _status;
  ServerConfig? get currentConfig => _currentConfig;
  String? get errorMessage => _errorMessage;

  Function(VpnStatus)? onStatusChanged;

  /// Whether the platform exposes a real native engine. Used so the
  /// rest of the app behaves gracefully on iOS/desktop where the bridge
  /// is not (yet) implemented.
  bool get _isPlatformSupported =>
      _platformSupportedOverride ?? Platform.isAndroid;

  Future<bool> initialize() async {
    if (_disposed) return false;
    if (!_isPlatformSupported) {
      // Non-Android platforms: streams stay open but no engine is wired.
      return false;
    }
    try {
      final Object? snapshot = await _control.invokeMethod<Object?>(
        'initialize',
      );
      if (_disposed) return false;
      _bindEventStream();
      _restoreFrom(snapshot);
      return true;
    } on MissingPluginException {
      // Native bridge not yet registered (build still in progress); the
      // caller treats this as a no-op rather than a fatal error.
      _errorMessage = 'engine_not_ready';
      return false;
    } on PlatformException catch (e) {
      // Surface the native error verbatim — operators usually need
      // exactly the Charon / GoBackend message to diagnose Atlas / DNS
      // issues. The localised fallback wraps it with `errorGeneric`.
      _errorMessage = e.message ?? e.code;
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    }
  }

  void _restoreFrom(Object? snapshot) {
    if (snapshot is! Map || _status != VpnStatus.disconnected) return;
    final ServerProtocol? protocol = switch (snapshot['protocol']) {
      'awg' => ServerProtocol.awg,
      'vless' => ServerProtocol.vless,
      'gw' => ServerProtocol.gw,
      _ => null,
    };
    final VpnStatus? status = switch (snapshot['state']) {
      'CONNECTED' => VpnStatus.connected,
      'CONNECTING' => VpnStatus.connecting,
      _ => null,
    };
    if (protocol == null || status == null) return;
    _restoredEngine = protocol;
    _engine = protocol;
    if (protocol == ServerProtocol.gw) {
      GwEngineService.instance.bind();
      _gwEventsSub ??= GwEngineService.instance.statusStream.listen(
        _handleGwEvent,
      );
    }
    _updateStatus(status);
  }

  Future<bool> connect(
    ServerConfig config, {
    List<String>? blockedApps,
    List<String>? excludedApps,
    List<String>? allowedApps,
  }) async {
    if (_disposed) return false;
    if (!_isPlatformSupported) {
      _errorMessage = 'platform_unsupported';
      _updateStatus(VpnStatus.error);
      return false;
    }
    if (_status == VpnStatus.connected || _status == VpnStatus.connecting) {
      await disconnect();
    }
    if (_disposed) return false;
    final int gen = ++_connectGeneration;
    bool stale() => _disposed || gen != _connectGeneration;
    try {
      _updateStatus(VpnStatus.connecting);
      _errorMessage = null;
      _currentConfig = config;

      // One permission flow for every engine: the GW engine used to ask on
      // its own and never reported a refusal, leaving "connecting" forever.
      final granted = await _requestPermission();
      if (stale()) return false;
      if (!granted) {
        _errorMessage = 'vpn_permission_denied';
        _updateStatus(VpnStatus.disconnected);
        return false;
      }

      if (config.protocol == ServerProtocol.gw) {
        return await _connectGw(
          config,
          excludedApps: excludedApps,
          allowedApps: allowedApps,
          stale: stale,
        );
      }

      _engine = config.protocol;
      final connected = await _control.invokeMethod<bool>('connect', <String, dynamic>{
        'protocol': config.protocol.apiName,
        'remark': config.cleanName,
        'address': config.address,
        'port': config.port,
        'username': config.username,
        'password': config.password,
        'caFile': config.caFile,
        'awgConfig': config.awgConfig,
        if (config.protocol == ServerProtocol.vless)
          'vlessUri': config.originalUrl,
        'country': config.country,
        if (blockedApps != null && blockedApps.isNotEmpty)
          'blockedApps': blockedApps,
      });
      if (stale()) return false;
      if (connected != true) {
        _errorMessage = 'engine_not_ready';
        _updateStatus(VpnStatus.error);
        return false;
      }
      return true;
    } on MissingPluginException {
      if (stale()) return false;
      _errorMessage = 'engine_not_ready';
      _updateStatus(VpnStatus.error);
      return false;
    } on PlatformException catch (e) {
      if (stale()) return false;
      // Native AWG engine gave up waiting for the first handshake: the
      // tunnel was torn down there, so the server (not the engine) is the
      // problem. Keep the stable code so the UI can localise it.
      _errorMessage = e.code == 'AWG_HANDSHAKE_TIMEOUT'
          ? 'awg_handshake_timeout'
          : (e.message ?? e.code);
      _updateStatus(VpnStatus.error);
      return false;
    } catch (e) {
      if (stale()) return false;
      _errorMessage = e.toString();
      _updateStatus(VpnStatus.error);
      return false;
    }
  }

  /// GW engine: starts the tunnel and waits for its verdict, like the AWG
  /// and VLESS paths, so a dead node ends in an error instead of silently
  /// falling back to "not connected".
  Future<bool> _connectGw(
    ServerConfig config, {
    List<String>? excludedApps,
    List<String>? allowedApps,
    required bool Function() stale,
  }) async {
    _engine = ServerProtocol.gw;
    _gwLastRx = 0;
    _gwLastTx = 0;
    _gwLastTrafficTime = null;
    final outcome = Completer<bool>();
    _gwOutcome = outcome;
    _gwAttemptStarted = false;
    GwEngineService.instance.bind();
    _gwEventsSub ??= GwEngineService.instance.statusStream.listen(
      _handleGwEvent,
    );
    final ok = await GwEngineService.instance.connect(
      config,
      excludedApps: excludedApps,
      allowedApps: allowedApps,
    );
    if (stale()) return false;
    if (!ok) {
      _abandonGwConnect();
      _engine = null;
      _errorMessage = 'engine_not_ready';
      _updateStatus(VpnStatus.error);
      return false;
    }
    var timedOut = false;
    final connected = await outcome.future.timeout(
      gwConnectTimeout,
      onTimeout: () {
        timedOut = true;
        return false;
      },
    );
    if (identical(_gwOutcome, outcome)) _gwOutcome = null;
    if (stale()) return false;
    if (connected) return true;
    // The engine already stopped unless our own limit fired first.
    if (timedOut) unawaited(GwEngineService.instance.disconnect());
    _engine = null;
    _errorMessage = 'awg_handshake_timeout';
    _updateStatus(VpnStatus.error);
    return false;
  }

  void _abandonGwConnect() {
    final pending = _gwOutcome;
    _gwOutcome = null;
    if (pending != null && !pending.isCompleted) pending.complete(false);
  }

  bool get _gwInvolved =>
      _engine == ServerProtocol.gw ||
      _currentConfig?.protocol == ServerProtocol.gw;

  /// Cancels an in-flight connection attempt. Safe to call in any
  /// state: it simply tears the tunnel down (native side rolls back a
  /// half-raised handshake) and parks the UI in `disconnected`.
  Future<void> cancelConnect() async {
    final int gen = ++_connectGeneration;
    _abandonGwConnect();
    if (!_isPlatformSupported) {
      _updateStatus(VpnStatus.disconnected);
      return;
    }
    final bool gw = _gwInvolved;
    // Immediate feedback; the button ignores taps while disconnecting.
    _updateStatus(VpnStatus.disconnecting);
    if (gw) {
      // No tunnel exists before CONNECTED; the engine stops in the background.
      await GwEngineService.instance.disconnect();
    } else {
      try {
        await _control.invokeMethod<void>('disconnect');
      } on MissingPluginException {
        // Bridge gone — nothing else to do; state is parked below.
      } on PlatformException {
        // Native engines tolerate a disconnect in any state.
      }
    }
    if (_disposed || gen != _connectGeneration) return;
    if (gw) _engine = null;
    _currentConfig = null;
    _errorMessage = null;
    _updateStatus(VpnStatus.disconnected);
  }

  Future<bool> disconnect() async {
    final int gen = ++_connectGeneration;
    _abandonGwConnect();
    if (!_isPlatformSupported) return true;
    final bool engineActive =
        _status == VpnStatus.connected ||
        _status == VpnStatus.connecting ||
        _status == VpnStatus.disconnecting;
    try {
      _updateStatus(VpnStatus.disconnecting);
      if (_gwInvolved) {
        final stopped = Completer<void>();
        _gwStopped = stopped;
        await GwEngineService.instance.disconnect();
        if (engineActive) {
          await stopped.future.timeout(gwStopTimeout, onTimeout: () {});
        }
        if (identical(_gwStopped, stopped)) _gwStopped = null;
        // A newer connect/disconnect owns the state now.
        if (_disposed || gen != _connectGeneration) return true;
        _engine = null;
        _currentConfig = null;
        _updateStatus(VpnStatus.disconnected);
        return true;
      }
      await _control.invokeMethod<void>('disconnect');
      _currentConfig = null;
      return true;
    } on MissingPluginException {
      _updateStatus(VpnStatus.disconnected);
      return true;
    } on PlatformException catch (e) {
      _errorMessage = e.message ?? e.code;
      _updateStatus(VpnStatus.disconnected);
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      _updateStatus(VpnStatus.disconnected);
      return false;
    }
  }

  /// Best-effort latency probe. Returns `null` when unsupported so the
  /// UI can fall back to the TCP-handshake heuristic in `AppProvider`.
  Future<int?> pingServer(ServerConfig config) async {
    if (!_isPlatformSupported) return null;
    try {
      final raw = await _control.invokeMethod<int>('pingServer', {
        'protocol': config.protocol.apiName,
        'address': config.address,
        'port': config.port,
      });
      return raw;
    } catch (_) {
      return null;
    }
  }

  /// Asks for the system VPN consent before a series of connects (auto-pick)
  /// so the dialog never eats into a server's time budget. Platforms without
  /// a native engine have nothing to grant; their connect reports that.
  Future<bool> ensurePermission() async {
    if (_disposed) return false;
    if (!_isPlatformSupported) return true;
    return _requestPermission();
  }

  Future<bool> _requestPermission() async {
    try {
      final granted =
          await _control.invokeMethod<bool>('requestPermission') ?? false;
      return granted;
    } on MissingPluginException {
      // Without the bridge we cannot prepare the VPN service. Treat as
      // denied so the caller surfaces a clean error.
      return false;
    } on PlatformException {
      return false;
    }
  }

  void _bindEventStream() {
    _eventsSub?.cancel();
    _eventsSub = _events.receiveBroadcastStream().listen(
      (dynamic raw) {
        if (_disposed || raw is! Map || _engine == ServerProtocol.gw) {
          return;
        }
        final status = EngineStatus.fromMap(raw);
        _engineStatusController.add(status);

        switch (status.state.toUpperCase()) {
          case 'CONNECTED':
            _updateStatus(VpnStatus.connected);
            break;
          case 'DISCONNECTED':
            _updateStatus(VpnStatus.disconnected);
            break;
          case 'CONNECTING':
            _updateStatus(VpnStatus.connecting);
            break;
          case 'DISCONNECTING':
            _updateStatus(VpnStatus.disconnecting);
            break;
          case 'ERROR':
            _updateStatus(VpnStatus.error);
            break;
        }
      },
      onError: (Object err) {
        _errorMessage = err.toString();
        _updateStatus(VpnStatus.error);
      },
      cancelOnError: false,
    );
  }

  /// GW engine events (STATE:/TRAFFIC:) are folded into the same
  /// status/engine pipelines the AWG path uses.
  void _handleGwEvent(String event) {
    if (_disposed || _engine != ServerProtocol.gw) return;
    final status = GwEngineService.statusFromEvent(event);
    if (status != null) {
      final bool down =
          status == VpnStatus.disconnected || status == VpnStatus.error;
      final stopped = _gwStopped;
      if (down && stopped != null && !stopped.isCompleted) stopped.complete();
      final pending = _gwOutcome;
      if (pending != null && !pending.isCompleted) {
        switch (status) {
          case VpnStatus.connected:
            pending.complete(true);
          case VpnStatus.connecting:
            _gwAttemptStarted = true;
            return;
          case VpnStatus.disconnected:
          case VpnStatus.error:
            // Before CONNECTING this is the engine's previous state, replayed
            // on subscribe, not the outcome of this attempt.
            if (_gwAttemptStarted) pending.complete(false);
            return;
          case VpnStatus.disconnecting:
            return;
        }
      }
      _updateStatus(status);
      if (status == VpnStatus.connected) {
        _engineStatusController.add(const EngineStatus(
          state: 'CONNECTED',
          duration: 0,
          downloadSpeed: 0,
          uploadSpeed: 0,
          download: 0,
          upload: 0,
        ));
      } else if (status == VpnStatus.disconnected) {
        _engineStatusController.add(EngineStatus.empty());
      }
      return;
    }
    if (event.startsWith('TRAFFIC:')) {
      final parts = event.split(':');
      final up = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
      final down = int.tryParse(parts.length > 2 ? parts[2] : '') ?? 0;

      final now = DateTime.now().millisecondsSinceEpoch;
      int dSpeed = 0;
      int uSpeed = 0;
      if (_gwLastTrafficTime != null &&
          down >= _gwLastRx &&
          up >= _gwLastTx) {
        final dt = (now - _gwLastTrafficTime!) / 1000.0;
        if (dt > 0) {
          dSpeed = ((down - _gwLastRx) / dt).round();
          uSpeed = ((up - _gwLastTx) / dt).round();
        }
      }
      _gwLastRx = down;
      _gwLastTx = up;
      _gwLastTrafficTime = now;

      _engineStatusController.add(EngineStatus(
        state: 'CONNECTED',
        duration: 0,
        downloadSpeed: dSpeed,
        uploadSpeed: uSpeed,
        download: down,
        upload: up,
      ));
    }
  }

  void _updateStatus(VpnStatus newStatus) {
    if (_disposed) return;
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(_status);
      onStatusChanged?.call(newStatus);
    }
  }

  void dispose() {
    _disposed = true;
    _abandonGwConnect();
    final stopped = _gwStopped;
    if (stopped != null && !stopped.isCompleted) stopped.complete();
    _eventsSub?.cancel();
    _gwEventsSub?.cancel();
    GwEngineService.instance.unbind();
    _statusController.close();
    _engineStatusController.close();
  }
}
