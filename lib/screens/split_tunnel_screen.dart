import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../motion/glass.dart';
import '../motion/motion_curves.dart';
import '../motion/press_feedback.dart';
import '../providers/app_provider.dart';
import '../services/split_tunnel_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_top_bar.dart';
import '../widgets/halo_field.dart';

/// Per-app VPN configuration screen: master switch, direction (include /
/// exclude), installed-app picker with search, and bulk actions.
class SplitTunnelScreen extends StatefulWidget {
  const SplitTunnelScreen({super.key});

  @override
  State<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends State<SplitTunnelScreen> {
  Future<List<AppInfo>>? _appsFuture;
  String _query = '';
  bool _lastShowSystemFlag = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    final AppProvider provider = context.read<AppProvider>();
    _lastShowSystemFlag = provider.splitTunnel.config.showSystemApps;
    WidgetsBinding.instance.addPostFrameCallback((_) => _showDisclosureIfNeeded());
  }

  Future<void> _showDisclosureIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('split_tunnel_disclosure_shown') ?? false;
    if (shown) {
      if (mounted) setState(() => _appsFuture = _loadApps(_lastShowSystemFlag));
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black.withValues(alpha: 0.55),
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.emerald.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.app_shortcut_rounded,
                          color: AppColors.emerald,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.splitTunnelDisclosureTitle,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.splitTunnelDisclosureBody,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  PressScale(
                    onTap: () => Navigator.of(ctx).pop(true),
                    pressedScale: 0.97,
                    child: SizedBox(
                      height: 44,
                      child: LiquidTile(
                        borderRadius: AppRadii.tile,
                        child: Center(
                          child: Text(
                            l10n.splitTunnelDisclosureButton,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
    if (ok == true) {
      await prefs.setBool('split_tunnel_disclosure_shown', true);
      if (mounted) setState(() => _appsFuture = _loadApps(_lastShowSystemFlag));
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// Native bridge to `MainActivity.kt#getLaunchablePackages`. We use this
  /// instead of the plugin's built-in system-app filter because the
  /// `FLAG_SYSTEM` bit marks everything pre-installed by the OEM (Chrome,
  /// YouTube, Play Store, the device's own browser / messenger / store,
  /// etc.) on most retail devices. Filtering by that flag therefore hides
  /// almost every app the user recognises and leaves the split-tunnel
  /// picker looking empty apart from Rabochiy VPN itself. Launcher-resolving
  /// packages are a much closer match for "apps the user cares about".
  static const MethodChannel _pkgChannel =
      MethodChannel('app.rabochiy.vpn/pkg_info');

  Future<Set<String>> _loadLaunchablePackages() async {
    try {
      final List<dynamic>? raw =
          await _pkgChannel.invokeMethod<List<dynamic>>('getLaunchablePackages');
      if (raw == null) return const <String>{};
      return raw
          .whereType<String>()
          .where((String s) => s.isNotEmpty)
          .toSet();
    } catch (e) {
      debugPrint('getLaunchablePackages failed: $e');
      return const <String>{};
    }
  }

  Future<List<AppInfo>> _loadApps(bool includeSystem) async {
    try {
      // Always fetch the full installed list (icons included). Filtering
      // by `excludeSystemApps` on the plugin side is too aggressive on
      // OEM-preinstalled apps, so we do it ourselves against the
      // launcher-resolving package set when the toggle is off.
      final List<AppInfo> apps = await InstalledApps.getInstalledApps(
        false,
        true,
      );

      List<AppInfo> filtered;
      if (includeSystem) {
        filtered = apps;
      } else {
        final Set<String> launchable = await _loadLaunchablePackages();
        // Fall back to showing everything if the native bridge failed or
        // the device reports no launchable apps for some reason — seeing
        // too many apps is strictly better than seeing only one.
        filtered = launchable.isEmpty
            ? apps
            : apps
                .where((AppInfo a) => launchable.contains(a.packageName))
                .toList(growable: false);
      }

      final List<AppInfo> sorted = List<AppInfo>.of(filtered);
      sorted.sort((AppInfo a, AppInfo b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return sorted;
    } catch (_) {
      return const <AppInfo>[];
    }
  }

  void _maybeReloadApps(SplitTunnelService st) {
    if (st.config.showSystemApps != _lastShowSystemFlag) {
      _lastShowSystemFlag = st.config.showSystemApps;
      _appsFuture = _loadApps(_lastShowSystemFlag);
    }
  }

  /// Debounces search input so rapid typing doesn't filter + rebuild the
  /// installed-apps list on every single keystroke. 160 ms is short enough
  /// to feel responsive but collapses bursts into a single rebuild.
  void _onSearchChanged(String raw) {
    final String next = raw.trim().toLowerCase();
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      if (_query == next) return;
      setState(() => _query = next);
    });
  }

  List<AppInfo> _filter(List<AppInfo> all) {
    if (_query.isEmpty) return all;
    return all
        .where((AppInfo a) =>
            a.name.toLowerCase().contains(_query) ||
            a.packageName.toLowerCase().contains(_query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    // IMPORTANT: The split-tunnel service is its own ChangeNotifier —
    // we subscribe to it directly via ListenableBuilder instead of
    // relying on AppProvider's notifications. Otherwise every toggle
    // would update persisted state but the UI would stay frozen,
    // which is exactly the "stub" feeling the feature used to give.
    final SplitTunnelService st = context.read<AppProvider>().splitTunnel;

    return ListenableBuilder(
      listenable: st,
      builder: (BuildContext context, _) =>
          _buildScaffold(context, l10n, st),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    AppLocalizations l10n,
    SplitTunnelService st,
  ) {
    _maybeReloadApps(st);

    return Scaffold(
      backgroundColor: AppColors.base,
      body: HaloField(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: <Widget>[
                    GlassIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        l10n.splitTunnelTitle,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CustomScrollView(
                  slivers: <Widget>[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate.fixed(<Widget>[
                          Text(
                            l10n.splitTunnelSubtitle,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13.5,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _MasterToggle(service: st, l10n: l10n),
                          const SizedBox(height: 14),
                          _ModeSelector(service: st, l10n: l10n),
                          const SizedBox(height: 14),
                          _HintBanner(text: l10n.splitTunnelReconnectHint),
                          const SizedBox(height: 18),
                          _SearchRow(
                            onChanged: _onSearchChanged,
                            l10n: l10n,
                          ),
                          const SizedBox(height: 10),
                          _BulkRow(
                            service: st,
                            appsFuture: _appsFuture,
                            l10n: l10n,
                          ),
                          const SizedBox(height: 10),
                          _SystemToggleRow(service: st, l10n: l10n),
                          const SizedBox(height: 12),
                        ]),
                      ),
                    ),
                    FutureBuilder<List<AppInfo>>(
                      future: _appsFuture,
                      builder: (BuildContext context,
                          AsyncSnapshot<List<AppInfo>> snap) {
                        if (!snap.hasData) {
                          return SliverToBoxAdapter(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 40),
                              child: Column(
                                children: <Widget>[
                                  const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: AppColors.emerald,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.splitTunnelLoading,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        final List<AppInfo> filtered = _filter(snap.data!);
                        if (filtered.isEmpty) {
                          return const SliverToBoxAdapter(
                            child: SizedBox(height: 32),
                          );
                        }
                        return SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                          sliver: SliverList.builder(
                            itemCount: filtered.length,
                            itemBuilder: (BuildContext context, int i) {
                              final AppInfo app = filtered[i];
                              final bool selected = st.config.packages
                                  .contains(app.packageName);
                              return _AppRow(
                                key: ValueKey<String>(app.packageName),
                                app: app,
                                selected: selected,
                                enabled: st.config.enabled,
                                onToggle: () =>
                                    st.togglePackage(app.packageName),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MasterToggle extends StatelessWidget {
  const _MasterToggle({required this.service, required this.l10n});

  final SplitTunnelService service;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.splitTunnelEnable,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.splitTunnelEnableDesc,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: service.config.enabled,
            onChanged: (bool v) => service.setEnabled(v),
            activeTrackColor: AppColors.emerald.withValues(alpha: 0.7),
            activeThumbColor: AppColors.textPrimary,
          ),
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.service, required this.l10n});

  final SplitTunnelService service;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final bool enabled = service.config.enabled;
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: AbsorbPointer(
        absorbing: !enabled,
        child: Column(
          children: <Widget>[
            _ModeTile(
              selected: service.config.mode == SplitTunnelMode.exclude,
              title: l10n.splitTunnelModeExclude,
              subtitle: l10n.splitTunnelModeExcludeDesc,
              onTap: () => service.setMode(SplitTunnelMode.exclude),
            ),
            const SizedBox(height: 8),
            _ModeTile(
              selected: service.config.mode == SplitTunnelMode.include,
              title: l10n.splitTunnelModeInclude,
              subtitle: l10n.splitTunnelModeIncludeDesc,
              onTap: () => service.setMode(SplitTunnelMode.include),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      pressedScale: 0.98,
      child: AnimatedSize(
        duration: RabochiyDurations.tabSwitch,
        curve: RabochiyCurves.brisk,
        child: LiquidTile(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          borderRadius: AppRadii.card,
          selected: selected,
          accent: AppColors.emerald,
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? AppColors.emerald : AppColors.textMuted,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HintBanner extends StatelessWidget {
  const _HintBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return LiquidTile(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: const BorderRadius.all(Radius.circular(14)),
      accent: AppColors.cyan,
      selected: true,
      elevated: false,
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline_rounded,
              size: 16, color: AppColors.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.onChanged,
    required this.l10n,
  });

  final ValueChanged<String> onChanged;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded,
            color: AppColors.textMuted, size: 20),
        hintText: l10n.splitTunnelSearchApps,
      ),
    );
  }
}

class _BulkRow extends StatelessWidget {
  const _BulkRow({
    required this.service,
    required this.appsFuture,
    required this.l10n,
  });

  final SplitTunnelService service;
  final Future<List<AppInfo>>? appsFuture;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final int selected = service.config.packages.length;
    return Row(
      children: <Widget>[
        Text(
          '${l10n.splitTunnelSelected}: $selected',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const Spacer(),
        _BulkButton(
          label: l10n.splitTunnelSelectAll,
          onTap: () async {
            final List<AppInfo>? apps = await appsFuture;
            if (apps == null) return;
            await service.setPackages(
              apps.map((AppInfo a) => a.packageName).toSet(),
            );
          },
        ),
        const SizedBox(width: 8),
        _BulkButton(
          label: l10n.splitTunnelClearAll,
          onTap: service.clearPackages,
        ),
      ],
    );
  }
}

class _BulkButton extends StatelessWidget {
  const _BulkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      pressedScale: 0.92,
      child: LiquidTile(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        elevated: false,
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SystemToggleRow extends StatelessWidget {
  const _SystemToggleRow({required this.service, required this.l10n});

  final SplitTunnelService service;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(Icons.settings_rounded,
            size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            l10n.splitTunnelShowSystem,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
            ),
          ),
        ),
        Switch(
          value: service.config.showSystemApps,
          onChanged: (bool v) => service.setShowSystemApps(v),
          activeTrackColor: AppColors.cyan.withValues(alpha: 0.6),
          activeThumbColor: AppColors.textPrimary,
        ),
      ],
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    super.key,
    required this.app,
    required this.selected,
    required this.enabled,
    required this.onToggle,
  });

  final AppInfo app;
  final bool selected;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final Uint8List? iconBytes = app.icon;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: PressScale(
        onTap: onToggle,
        enabled: enabled,
        pressedScale: 0.985,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: LiquidTile(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            selected: selected,
            accent: AppColors.emerald,
            elevated: false,
            child: Row(
            children: <Widget>[
              SizedBox(
                width: 38,
                height: 38,
                child: iconBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(iconBytes, fit: BoxFit.cover),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: AppColors.surfaceElevated,
                        ),
                        child: const Icon(Icons.android_rounded,
                            color: AppColors.textMuted, size: 18),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      app.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app.packageName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: selected ? AppColors.emerald : AppColors.textMuted,
                size: 22,
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
