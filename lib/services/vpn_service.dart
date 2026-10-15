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
  VpnService({bool? platformSupported})
      : _platformSupportedOverride = platformSupported;

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
      await _control.invokeMethod<void>('initialize');
      if (_disposed) return false;
      _bindEventStream();
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

      // GW (SSH-tunnel) servers run on their own native engine with its
      // own channels; it handles VpnService.prepare() internally.
      if (config.protocol == ServerProtocol.gw) {
        GwEngineService.instance.bind();
        _gwLastRx = 0;
        _gwLastTx = 0;
        _gwLastTrafficTime = null;
        _gwEventsSub ??= GwEngineService.instance.statusStream.listen(
          (event) => _handleGwEvent(event, config),
        );
        final ok = await GwEngineService.instance.connect(
          config,
          excludedApps: excludedApps,
          allowedApps: allowedApps,
        );
        if (stale()) return false;
        if (!ok) {
          _errorMessage = 'engine_not_ready';
          _updateStatus(VpnStatus.error);
        }
        return ok;
      }

      final granted = await _requestPermission();
      if (stale()) return false;
      if (!granted) {
        _errorMessage = 'vpn_permission_denied';
        _updateStatus(VpnStatus.disconnected);
        return false;
      }

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

  /// Cancels an in-flight connection attempt. Safe to call in any
  /// state: it simply tears the tunnel down (native side rolls back a
  /// half-raised handshake) and parks the UI in `disconnected`.
  Future<void> cancelConnect() async {
    _connectGeneration++;
    if (!_isPlatformSupported) {
      _updateStatus(VpnStatus.disconnected);
      return;
    }
    if (_currentConfig?.protocol == ServerProtocol.gw) {
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
    _currentConfig = null;
    _errorMessage = null;
    _updateStatus(VpnStatus.disconnected);
  }

  Future<bool> disconnect() async {
    _connectGeneration++;
    if (!_isPlatformSupported) return true;
    try {
      _updateStatus(VpnStatus.disconnecting);
      if (_currentConfig?.protocol == ServerProtocol.gw) {
        await GwEngineService.instance.disconnect();
      } else {
        await _control.invokeMethod<void>('disconnect');
      }
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
        if (_disposed || raw is! Map ||
            _currentConfig?.protocol == ServerProtocol.gw) {
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
  void _handleGwEvent(String event, ServerConfig config) {
    if (_disposed || _currentConfig?.protocol != ServerProtocol.gw) return;
    final status = GwEngineService.statusFromEvent(event);
    if (status != null) {
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
    _eventsSub?.cancel();
    _gwEventsSub?.cancel();
    GwEngineService.instance.unbind();
    _statusController.close();
    _engineStatusController.close();
  }
}
