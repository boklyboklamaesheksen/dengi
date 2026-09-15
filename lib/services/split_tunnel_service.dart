import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Direction of the split tunnel mask.
///
/// * [include] — only the selected apps are routed through the VPN.
/// * [exclude] — the selected apps bypass the VPN; everything else goes
///   through the tunnel.
enum SplitTunnelMode { include, exclude }

/// Persisted configuration of the per-app VPN feature.
@immutable
class SplitTunnelConfig {
  const SplitTunnelConfig({
    required this.enabled,
    required this.mode,
    required this.packages,
    required this.showSystemApps,
  });

  static const SplitTunnelConfig defaults = SplitTunnelConfig(
    enabled: false,
    mode: SplitTunnelMode.exclude,
    packages: <String>{},
    showSystemApps: false,
  );

  final bool enabled;
  final SplitTunnelMode mode;
  final Set<String> packages;
  final bool showSystemApps;

  SplitTunnelConfig copyWith({
    bool? enabled,
    SplitTunnelMode? mode,
    Set<String>? packages,
    bool? showSystemApps,
  }) =>
      SplitTunnelConfig(
        enabled: enabled ?? this.enabled,
        mode: mode ?? this.mode,
        packages: packages ?? this.packages,
        showSystemApps: showSystemApps ?? this.showSystemApps,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'mode': mode.name,
        'packages': packages.toList(growable: false),
        'showSystemApps': showSystemApps,
      };

  static SplitTunnelConfig fromJson(Map<String, dynamic> json) {
    final String modeRaw = (json['mode'] as String?) ?? 'exclude';
    final SplitTunnelMode parsedMode = SplitTunnelMode.values.firstWhere(
      (SplitTunnelMode m) => m.name == modeRaw,
      orElse: () => SplitTunnelMode.exclude,
    );
    final List<dynamic> rawPackages =
        (json['packages'] as List<dynamic>?) ?? const <dynamic>[];
    return SplitTunnelConfig(
      enabled: json['enabled'] as bool? ?? false,
      mode: parsedMode,
      packages: rawPackages
          .whereType<String>()
          .where((String s) => s.isNotEmpty)
          .toSet(),
      showSystemApps: json['showSystemApps'] as bool? ?? false,
    );
  }
}

/// Stores and publishes the user's split-tunnel preferences.
///
/// The service also derives the `blockedApps` list that the VPN engine
/// needs: the tunnel applies a single exclude list, so for the
/// "include" mode we compute `allInstalled − selected` at connect time on
/// the call-site.
class SplitTunnelService extends ChangeNotifier {
  SplitTunnelService();

  static const String _prefsKey = 'rabochiy_split_tunnel_v1';

  SplitTunnelConfig _config = SplitTunnelConfig.defaults;
  bool _loaded = false;
  bool _disposed = false;

  SplitTunnelConfig get config => _config;
  bool get isLoaded => _loaded;
  bool get isActive => _config.enabled && _config.packages.isNotEmpty;

  /// Loads persisted state. Safe to call multiple times.
  Future<void> load() async {
    if (_loaded || _disposed) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      final String? raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final Map<String, dynamic> decoded =
            jsonDecode(raw) as Map<String, dynamic>;
        _config = SplitTunnelConfig.fromJson(decoded);
      }
    } catch (_) {
      // Fall back to defaults.
      _config = SplitTunnelConfig.defaults;
    }
    _loaded = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_config.enabled == value) return;
    _config = _config.copyWith(enabled: value);
    notifyListeners();
    await _persist();
  }

  Future<void> setMode(SplitTunnelMode mode) async {
    if (_config.mode == mode) return;
    _config = _config.copyWith(mode: mode);
    notifyListeners();
    await _persist();
  }

  Future<void> setShowSystemApps(bool value) async {
    if (_config.showSystemApps == value) return;
    _config = _config.copyWith(showSystemApps: value);
    notifyListeners();
    await _persist();
  }

  Future<void> togglePackage(String pkg) async {
    final Set<String> next = Set<String>.from(_config.packages);
    if (!next.add(pkg)) {
      next.remove(pkg);
    }
    _config = _config.copyWith(packages: next);
    notifyListeners();
    await _persist();
  }

  Future<void> setPackages(Set<String> packages) async {
    _config = _config.copyWith(packages: Set<String>.from(packages));
    notifyListeners();
    await _persist();
  }

  Future<void> clearPackages() async {
    if (_config.packages.isEmpty) return;
    _config = _config.copyWith(packages: const <String>{});
    notifyListeners();
    await _persist();
  }

  /// Computes the `blockedApps` list to pass to the VPN engine based on the
  /// current configuration and the full list of currently-installed
  /// packages supplied by the caller.
  ///
  /// Returns `null` when split tunnel is off — the engine then lets every
  /// app through the tunnel.
  List<String>? buildBlockedApps(Iterable<String> installedPackages) {
    if (!isActive) return null;

    switch (_config.mode) {
      case SplitTunnelMode.exclude:
        // Selected apps skip the VPN: pass them as-is.
        return _config.packages.toList(growable: false);
      case SplitTunnelMode.include:
        // Only selected apps should go through the VPN — block everything
        // else.
        final Set<String> selected = _config.packages;
        return installedPackages
            .where((String pkg) => !selected.contains(pkg))
            .toList(growable: false);
    }
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_config.toJson()));
    } catch (_) {
      // Non-critical — will retry on next change.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
