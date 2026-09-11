import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:installed_apps/installed_apps.dart';

import '../models/server_config_model.dart';
import '../services/api_service.dart';
import '../services/gw_api_service.dart';
import '../services/split_tunnel_service.dart';
import '../services/traffic_stats_service.dart';
import '../services/vpn_service.dart';

/// Central state container for Rabochiy VPN.
///
/// Drives every reactive widget in the app. The provider owns:
///   * [VpnService] — bridge to the native IKEv2 / AmneziaWG engines.
///   * [ApiService] — HTTPS client for the backend (server catalogue,
///     server load, connection heartbeats, payments, account state).
///   * [TrafficStatsService] — persistent hourly traffic buckets.
///   * [SplitTunnelService] — per-app include / exclude masks.
class AppProvider with ChangeNotifier {
  final VpnService _vpnService = VpnService();
  final ApiService _apiService = ApiService();
  final GwApiService _gwApiService = GwApiService();
  final TrafficStatsService _trafficStats = TrafficStatsService();
  final SplitTunnelService _splitTunnel = SplitTunnelService();

  VpnStatus _vpnStatus = VpnStatus.disconnected;
  List<ServerConfig> _servers = [];

  /// Per-server load percentage, keyed by server `ip_address`. Filled
  /// from the backend `/vpn/api/v1/user/servers/load` endpoint. Values
  /// are clamped to `0..100` server-side.
  final Map<String, int> _serverLoadByIp = {};

  /// Approximate online-user count derived from the load percentages.
  /// Used by the "X users online" banner on the home screen.
  int _totalOnlineUsers = 0;

  ServerConfig? _selectedServer;
  bool _isAutoSelect = true;
  String? _errorMessage;
  bool _isLoading = false;
  bool _isPremium = false;

  Duration _connectionDuration = Duration.zero;
  Timer? _timer;
  int _downloadSpeedBytes = 0;
  int _uploadSpeedBytes = 0;

  int _cumulativeRxBytes = 0;
  int _cumulativeTxBytes = 0;
  int _lastEngineRx = 0;
  int _lastEngineTx = 0;

  /// Debounce handle for "reapply split-tunnel while connected". Rapid
  /// toggles in the picker (e.g. tapping a dozen apps) collapse into a
  /// single reconnect instead of spawning one per tap.
  Timer? _splitTunnelApplyTimer;

  /// Periodic heartbeat that tells the backend "this user is online on
  /// server X" so the admin panel's online counter and the per-server
  /// load endpoint stay accurate.
  Timer? _heartbeatTimer;
  String? _activeServerIp;
  String? _activeProtocol;

  VpnStatus get vpnStatus => _vpnStatus;
  List<ServerConfig> get servers => _servers;
  ServerConfig? get selectedServer => _selectedServer;
  bool get isAutoSelect => _isAutoSelect;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isPremium => _isPremium;
  bool get selectedServerRequiresPremium =>
      !_isPremium && _selectedServer?.premium == true;
  Duration get connectionDuration => _connectionDuration;
  int get downloadSpeedBytes => _downloadSpeedBytes;
  int get uploadSpeedBytes => _uploadSpeedBytes;

  /// Total bytes transferred during the current (or last) session.
  int get sessionRxBytes => _cumulativeRxBytes;
  int get sessionTxBytes => _cumulativeTxBytes;
  int get totalOnlineUsers => _totalOnlineUsers;
  TrafficStatsService get trafficStats => _trafficStats;
  SplitTunnelService get splitTunnel => _splitTunnel;
  ApiService get apiService => _apiService;

  /// Backend-derived load → derived online-user count.
  ///
  /// The server-side load endpoint already does the heavy lifting (it
  /// counts active connections per IP and divides by a per-server cap),
  /// so a simple linear approximation `users = load% / 10` works well
  /// enough for the "X users online" labels.
  int getServerOnlineUsers(ServerConfig config) {
    final load = _serverLoadByIp[config.address];
    if (load == null) return 0;
    return (load / 10).round();
  }

  /// Returns server load as a percentage in `0..100`. Always sourced
  /// from the backend now; no heuristics.
  double getServerLoadPercentage(ServerConfig config) {
    final liveLoad = _serverLoadByIp[config.address];
    if (liveLoad == null) return 0.0;
    return liveLoad.toDouble().clamp(0.0, 100.0);
  }

  AppProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    _isLoading = true;
    notifyListeners();

    await Future.wait<void>(<Future<void>>[
      _vpnService.initialize(),
      _trafficStats.load(),
      _splitTunnel.load(),
      _apiService.getIsPremium().then((value) {
        _isPremium = value;
      }),
    ]);

    // Subscribe to split-tunnel changes so (a) any widget that watches
    // AppProvider rebuilds when tunnel state changes and (b) we can
    // transparently reapply the new mask while the VPN is already live.
    _splitTunnel.addListener(_onSplitTunnelChanged);

    await loadServers();

    // Fire-and-forget user-state refresh so the premium badge reflects
    // any backend-side changes (code activation, plan extension) that
    // happened while the app was closed.
    unawaited(_refreshUserState());

    _vpnService.engineStatusStream.listen((status) {
      _downloadSpeedBytes = status.downloadSpeed;
      _uploadSpeedBytes = status.uploadSpeed;

      // status.download / status.upload are cumulative byte counters for
      // the live session. Use them to feed the hourly traffic buckets.
      final int rxNow = status.download;
      final int txNow = status.upload;

      int rxDelta = rxNow - _lastEngineRx;
      int txDelta = txNow - _lastEngineTx;
      if (rxDelta < 0) rxDelta = rxNow;
      if (txDelta < 0) txDelta = txNow;
      _lastEngineRx = rxNow;
      _lastEngineTx = txNow;

      _cumulativeRxBytes += rxDelta;
      _cumulativeTxBytes += txDelta;

      _trafficStats.recordSample(
        totalRxBytes: _cumulativeRxBytes,
        totalTxBytes: _cumulativeTxBytes,
      );

      notifyListeners();
    });

    _vpnService.statusStream.listen((status) {
      _vpnStatus = status;

      if (status == VpnStatus.connected) {
        _startTimer();
        _trafficStats.recordSessionStart();
        _startHeartbeat();
      } else if (status == VpnStatus.disconnected) {
        _stopTimer();
        _connectionDuration = Duration.zero;
        _downloadSpeedBytes = 0;
        _uploadSpeedBytes = 0;
        _lastEngineRx = 0;
        _lastEngineTx = 0;
        _trafficStats.resetSession();
        _stopHeartbeat(reportDisconnect: true);
      } else if (status == VpnStatus.error) {
        _errorMessage = _vpnService.errorMessage;
        _stopHeartbeat(reportDisconnect: true);
      }

      notifyListeners();
    });

    _isLoading = false;
    notifyListeners();
  }

  /// Caches the package names of every installed Android app. Rebuilt on
  /// demand because the universe changes rarely (install/uninstall) and
  /// the underlying plugin call is slow.
  List<String>? _installedPackageCache;
  DateTime? _installedPackageCacheTime;

  Future<List<String>> _listInstalledPackages() async {
    final DateTime now = DateTime.now();
    final List<String>? cached = _installedPackageCache;
    final DateTime? cachedAt = _installedPackageCacheTime;
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < const Duration(minutes: 5)) {
      return cached;
    }

    try {
      // NOTE: we intentionally include system apps here. The include-mode
      // of split-tunnel computes `blocked = installed − selected`, so if
      // the installed list is missing system packages they'd quietly
      // slip through the VPN even though the user chose "only these
      // apps". Icons aren't needed at the connect-path so we skip them
      // for speed.
      final List<dynamic> apps = await InstalledApps.getInstalledApps(
        false,
        false,
      );
      final List<String> names = apps
          .map((dynamic app) {
            try {
              return app.packageName?.toString();
            } catch (_) {
              return null;
            }
          })
          .whereType<String>()
          .where((String s) => s.isNotEmpty)
          .toList(growable: false);
      _installedPackageCache = names;
      _installedPackageCacheTime = now;
      return names;
    } catch (_) {
      return cached ?? const <String>[];
    }
  }

  Future<void> loadServers() async {
    try {
      _isLoading = true;
      notifyListeners();

      final futures = await Future.wait<Object>(<Future<Object>>[
        _apiService.fetchServerConfigs(),
        _apiService.fetchServerLoads(),
      ]);

      final servers = futures[0] as List<ServerConfig>;
      final loadByIp = futures[1] as Map<String, int>;

      // GW (SSH-tunnel) servers join the same catalogue; failures to load
      // them (no fleet yet, no user) degrade silently to an empty list.
      final gwServers = await _gwApiService.fetchServers();

      _serverLoadByIp
        ..clear()
        ..addAll(loadByIp);

      // Approximate total online users from the per-server load map.
      int total = 0;
      loadByIp.forEach((_, value) {
        total += (value / 10).round();
      });
      _totalOnlineUsers = total;

      _servers = [...servers, ...gwServers];
      notifyListeners();

      if (_isAutoSelect || _selectedServer == null) {
        await _autoSelectBestServer();
      }
    } catch (e) {
      // Stable code consumed by the localised banner in the UI.
      _errorMessage = 'load_servers_failed';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshUserState() async {
    final state = await _apiService.refreshUserState();
    if (state == null) return;
    final premiumChanged = _isPremium != state.isPremium;
    _isPremium = state.isPremium;
    if (premiumChanged) {
      // Premium gate just flipped — the server catalogue may have
      // grown / shrunk (premium-only servers strip credentials
      // server-side for non-premium users), so reload it.
      await loadServers();
    } else {
      notifyListeners();
    }
  }

  /// Public entry point for the Account / Premium screens to refresh
  /// the premium state on demand (e.g. after the user returns from the
  /// payment URL).
  Future<void> refreshUserState() => _refreshUserState();

  Future<void> _autoSelectBestServer() async {
    if (_servers.isEmpty) return;

    ServerConfig? best;
    try {
      // Free-tier: prefer non-premium servers but keep premium ones as
      // fallback candidates (tapping them opens the premium gate).
      final ranked = _servers.toList()
        ..sort((a, b) {
          final loadA = _serverLoadByIp[a.address] ?? 50;
          final loadB = _serverLoadByIp[b.address] ?? 50;
          if (a.recommend != b.recommend) return a.recommend ? -1 : 1;
          if (loadA != loadB) return loadA.compareTo(loadB);
          return b.priority.compareTo(a.priority);
        });

      if (ranked.isNotEmpty) {
        best = ranked.first;
      } else {
        best = _servers.first;
      }
    } catch (_) {
      if (_servers.isNotEmpty) best = _servers.first;
    }

    _selectedServer = best;
    _isAutoSelect = true;
    notifyListeners();
  }

  void selectServer(ServerConfig server) {
    final wasConnected =
        _vpnStatus == VpnStatus.connected || _vpnStatus == VpnStatus.connecting;
    final isSameServer = _selectedServer?.id == server.id;

    _selectedServer = server;
    _isAutoSelect = false;
    notifyListeners();

    if (wasConnected && !isSameServer) {
      if (server.premium && !_isPremium) {
        unawaited(_disconnectForPremiumGate());
      } else {
        unawaited(_reconnect());
      }
    }
  }

  void toggleAutoSelect() {
    final wasConnected =
        _vpnStatus == VpnStatus.connected || _vpnStatus == VpnStatus.connecting;
    final previous = _selectedServer;

    _isAutoSelect = true;
    _autoSelectBestServer().then((_) {
      if (wasConnected && _selectedServer?.id != previous?.id) {
        unawaited(_reconnect());
      }
    });
  }

  Future<void> _reconnect() async {
    await _vpnService.disconnect();
    await Future.delayed(const Duration(milliseconds: 500));
    await connectVpn();
  }

  Future<void> _disconnectForPremiumGate() async {
    await _vpnService.disconnect();
    _errorMessage = 'premium_required';
    notifyListeners();
  }

  /// Called whenever [SplitTunnelService] fires a change. Two jobs:
  /// 1. Rebroadcast to anyone watching the central [AppProvider] so
  ///    summary rows (e.g. the settings subtitle) stay in sync.
  /// 2. If the VPN is currently live, schedule a debounced reconnect so
  ///    the new include / exclude mask actually takes effect.
  void _onSplitTunnelChanged() {
    notifyListeners();

    final bool live =
        _vpnStatus == VpnStatus.connected || _vpnStatus == VpnStatus.connecting;
    if (!live) return;

    _splitTunnelApplyTimer?.cancel();
    _splitTunnelApplyTimer = Timer(const Duration(milliseconds: 700), () {
      // Re-check status at fire time: the user may have disconnected
      // in the meantime.
      if (_vpnStatus == VpnStatus.connected ||
          _vpnStatus == VpnStatus.connecting) {
        unawaited(_reconnect());
      }
    });
  }

  Future<void> connectVpn() async {
    if (_servers.isEmpty) {
      await loadServers();
      if (_servers.isEmpty) {
        _errorMessage = 'no_servers_available';
        notifyListeners();
        return;
      }
    }

    ServerConfig? target = _selectedServer;
    if (_isAutoSelect) {
      if (target == null) await _autoSelectBestServer();
      target = _selectedServer;
    }

    if (target == null) {
      _errorMessage = 'no_server_selected';
      notifyListeners();
      return;
    }

    // Premium-only servers ship without credentials for free users —
    // refuse to connect instead of attempting an obviously broken
    // tunnel.
    // Free accounts must never connect to premium servers, even if
    // the backend includes usable credentials.
    if (target.premium && !_isPremium) {
      _errorMessage = 'premium_required';
      notifyListeners();
      return;
    }

    // Per-app VPN mask. `blocked` drives the AWG path (injected as
    // ExcludedApplications); the GW engine takes the mask as an
    // excluded/allowed pair so the include mode maps to allowedApps
    // instead of an inverted exclude list.
    List<String>? blocked;
    List<String>? gwExcluded;
    List<String>? gwAllowed;
    if (_splitTunnel.isActive) {
      final List<String> installed = await _listInstalledPackages();
      blocked = _splitTunnel.buildBlockedApps(installed);
      if (_splitTunnel.config.mode == SplitTunnelMode.exclude) {
        gwExcluded = List<String>.from(_splitTunnel.config.packages);
      } else {
        gwAllowed = List<String>.from(_splitTunnel.config.packages);
      }
    }

    final success = await _vpnService.connect(
      target,
      blockedApps: blocked,
      excludedApps: gwExcluded,
      allowedApps: gwAllowed,
    );
    if (!success) {
      _errorMessage = _vpnService.errorMessage;
      notifyListeners();
    }
  }

  Future<void> disconnectVpn() async {
    await _vpnService.disconnect();
  }

  /// User tapped the button again while a connection attempt was still
  /// in flight — cancel it instead of waiting for the handshake.
  Future<void> cancelConnect() async {
    await _vpnService.cancelConnect();
  }

  /// Wipes all in-memory account state after a logout / delete-account
  /// flow. Stops timers, drops the tunnel best-effort (with a hard
  /// 2-second budget so a hung native engine never blocks navigation
  /// to /welcome), and zeroes everything tied to the previous user
  /// (premium flag, selected server, cached lists, error string).
  ///
  /// Persistent storage (`SharedPreferences`) is NOT touched here —
  /// that is `ApiService.logout()`'s job. Splitting the two means
  /// we can clear the on-disk credentials *before* this runs, so
  /// even if the native disconnect throws or the activity is
  /// killed mid-flow the next launch still lands on /welcome.
  Future<void> resetSession() async {
    _stopHeartbeat();
    _stopTimer();
    _splitTunnelApplyTimer?.cancel();
    _splitTunnelApplyTimer = null;

    try {
      await _vpnService.disconnect().timeout(
        const Duration(seconds: 2),
        onTimeout: () => true,
      );
    } catch (_) {
      /* tunnel was already down or platform threw — ignore */
    }

    _vpnStatus = VpnStatus.disconnected;
    _isPremium = false;
    _selectedServer = null;
    _isAutoSelect = true;
    _servers = const <ServerConfig>[];
    _serverLoadByIp.clear();
    _totalOnlineUsers = 0;
    _errorMessage = null;
    _connectionDuration = Duration.zero;
    _downloadSpeedBytes = 0;
    _uploadSpeedBytes = 0;
    _isLoading = false;
    _cumulativeRxBytes = 0;
    _cumulativeTxBytes = 0;
    _lastEngineRx = 0;
    _lastEngineTx = 0;
    _activeServerIp = null;
    _activeProtocol = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _startTimer() {
    _stopTimer();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _connectionDuration += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Starts the periodic `connection/update` heartbeat. The first call
  /// fires immediately so the admin panel sees the user as online
  /// without waiting a full 30 s cycle.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    final ServerConfig? target = _selectedServer ?? _vpnService.currentConfig;
    _activeServerIp = target?.address;
    _activeProtocol = target?.protocol.apiName;
    _sendHeartbeat('connect');
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendHeartbeat('heartbeat');
    });
  }

  /// Cancels the heartbeat loop. When `reportDisconnect` is true we
  /// also fire one last update with `action=disconnect` so the
  /// backend doesn't have to wait for the 2-min sliding window before
  /// dropping the user from the online counter.
  void _stopHeartbeat({bool reportDisconnect = false}) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (reportDisconnect && _activeServerIp != null) {
      _sendHeartbeat('disconnect');
    }
    _activeServerIp = null;
    _activeProtocol = null;
  }

  Future<void> _sendHeartbeat(String action) async {
    final userId = await _apiService.getUserId();
    if (userId == null || userId.isEmpty || userId == 'pending') return;
    await _apiService.reportConnection(
      userId: userId,
      serverIp: _activeServerIp,
      action: action,
      protocol: _activeProtocol ?? 'awg',
    );
  }

  @override
  void dispose() {
    _splitTunnelApplyTimer?.cancel();
    _splitTunnel.removeListener(_onSplitTunnelChanged);
    _vpnService.dispose();
    _trafficStats.dispose();
    _splitTunnel.dispose();
    _stopTimer();
    _stopHeartbeat();
    _apiService.close();
    super.dispose();
  }
}
