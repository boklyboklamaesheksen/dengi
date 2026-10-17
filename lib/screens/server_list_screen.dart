import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/server_config_model.dart';
import '../motion/glass.dart';
import '../motion/press_feedback.dart';
import '../providers/app_provider.dart';
import '../widgets/glass_card.dart';
import 'premium_gate.dart';

/// Bottom-sheet style server picker with a frosted surface and glass tiles.
class ServerListScreen extends StatefulWidget {
  const ServerListScreen({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Edge-to-edge: keep the sheet below the status bar / display cutout.
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => const ServerListScreen(),
    );
  }

  @override
  State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  ServerProtocol? _protocolFilter;

  @override
  void initState() {
    super.initState();
    // Re-fetch the catalogue every time the sheet opens: servers can be
    // added/removed on the backend (bot/admin) while the app is running,
    // and the provider only loads them on splash / login otherwise.
    // Post-frame so Provider listeners aren't notified during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppProvider>().loadServersIfNeeded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        const BorderRadius sheetRadius = BorderRadius.vertical(
          top: Radius.circular(28),
        );
        return ClipRRect(
          borderRadius: sheetRadius,
          child: Stack(
            children: <Widget>[
              Container(
                decoration: const BoxDecoration(
                  borderRadius: sheetRadius,
                  color: AppColors.base,
                ),
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              l10n.selectServer,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          PressScale(
                            onTap: () => Navigator.pop(context),
                            pressedScale: 0.9,
                            child: const SizedBox(
                              width: 48,
                              height: 48,
                              child: LiquidTile(
                                padding: EdgeInsets.zero,
                                borderRadius: BorderRadius.all(
                                  Radius.circular(12),
                                ),
                                elevated: false,
                                compact: true,
                                child: Center(
                                  child: Icon(
                                    Icons.close_rounded,
                                    color: AppColors.textSecondary,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Protocol filter chips. A bare Wrap shrink-wraps and
                    // gets centred by the parent Column; forcing it to full
                    // width keeps the chips pinned to the left edge (they
                    // still wrap onto a second line on very narrow screens).
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.start,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _FilterChip(
                              label: l10n.filterAll,
                              selected: _protocolFilter == null,
                              onTap: () =>
                                  setState(() => _protocolFilter = null),
                            ),
                            _FilterChip(
                              label: 'AmneziaWG 3.1',
                              selected: _protocolFilter == ServerProtocol.awg,
                              onTap: () => setState(
                                () => _protocolFilter = ServerProtocol.awg,
                              ),
                              color: AppColors.emerald,
                            ),
                            _FilterChip(
                              label: 'GW',
                              selected: _protocolFilter == ServerProtocol.gw,
                              onTap: () => setState(
                                () => _protocolFilter = ServerProtocol.gw,
                              ),
                              color: AppColors.teal,
                            ),
                            _FilterChip(
                              label: 'VLESS',
                              selected: _protocolFilter == ServerProtocol.vless,
                              onTap: () => setState(
                                () => _protocolFilter = ServerProtocol.vless,
                              ),
                              color: AppColors.cyan,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Consumer<AppProvider>(
                        builder: (context, provider, _) {
                          // Group by protocol; List.sort is not stable, so
                          // the catalogue index keeps subscription order.
                          final List<ServerConfig> catalog = provider.servers;
                          final List<int> order =
                              List<int>.generate(catalog.length, (i) => i)
                                ..sort((a, b) {
                                  final byProtocol = catalog[a].protocol.index
                                      .compareTo(catalog[b].protocol.index);
                                  return byProtocol != 0
                                      ? byProtocol
                                      : a.compareTo(b);
                                });
                          final List<ServerConfig> allServers = [
                            for (final i in order) catalog[i],
                          ];
                          final List<ServerConfig> servers =
                              _protocolFilter == null
                              ? allServers
                              : allServers
                                    .where((s) => s.protocol == _protocolFilter)
                                    .toList();
                          final errorBanner = provider.catalogError == null
                              ? null
                              : Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    provider.catalogError ==
                                            'api_not_configured'
                                        ? l10n.apiConfigurationError
                                        : l10n.failedToLoadServers,
                                    key: const ValueKey('catalog-error'),
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                );

                          if (provider.isLoading && allServers.isEmpty) {
                            return const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: AppColors.emerald,
                              ),
                            );
                          }

                          if (servers.isEmpty && !provider.isLoading) {
                            return ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              children: [
                                Icon(
                                  Icons.dns_outlined,
                                  color: Colors.white.withValues(alpha: 0.3),
                                  size: 48,
                                ),
                                const SizedBox(height: 12),
                                if (errorBanner != null)
                                  errorBanner
                                else
                                  Text(
                                    l10n.serversNotFound,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.5,
                                      ),
                                      fontSize: 15,
                                    ),
                                  ),
                              ],
                            );
                          }

                          final headerCount = errorBanner == null ? 1 : 2;
                          return ListView.separated(
                            controller: scrollController,
                            // The sheet runs under the navigation bar; the
                            // last server must still scroll clear of it.
                            padding: EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              24 + MediaQuery.paddingOf(context).bottom,
                            ),
                            itemCount: servers.length + headerCount,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              if (errorBanner != null && index == 0) {
                                return errorBanner;
                              }
                              if (index == headerCount - 1) {
                                return _AutoTile(
                                  selected: provider.isAutoSelect,
                                  onTap: () {
                                    provider.toggleAutoSelect();
                                    Navigator.pop(context);
                                  },
                                );
                              }
                              final ServerConfig server =
                                  servers[index - headerCount];
                              final bool selected =
                                  !provider.isAutoSelect &&
                                  provider.selectedServer?.id == server.id;
                              return _ServerTile(
                                server: server,
                                selected: selected,
                                onTap: () {
                                  final NavigatorState navigator = Navigator.of(
                                    context,
                                  );
                                  navigator.pop();
                                  if (provider.isLockedForUser(server)) {
                                    // Paywall right away; the working
                                    // tunnel and selection stay untouched.
                                    unawaited(
                                      PremiumGate.unlockServer(
                                        navigator,
                                        provider,
                                        server,
                                      ),
                                    );
                                    return;
                                  }
                                  provider.selectServer(server);
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const Positioned.fill(
                child: LiquidEdges(
                  borderRadius: sheetRadius,
                  topThickness: 1.4,
                  bottomThickness: 0,
                  sideAlpha: 0.05,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Filter chip for protocol selection
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textColor = selected
        ? (color ?? AppColors.emerald)
        : Colors.white.withValues(alpha: 0.6);

    return PressScale(
      onTap: onTap,
      pressedScale: 0.95,
      child: FrostedSurface(
        borderRadius: BorderRadius.circular(20),
        sigma: 14,
        compact: true,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Glass tile for the "Auto · best server" pseudo-entry at the top of the
/// list.
class _AutoTile extends StatelessWidget {
  const _AutoTile({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return PressScale(
      onTap: onTap,
      pressedScale: 0.98,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        tint: selected ? AppColors.emerald.withValues(alpha: 0.10) : null,
        child: Row(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: AppColors.signal,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.emerald.withValues(alpha: 0.15),
                    blurRadius: 10,
                    spreadRadius: -3,
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                // Glyph sits on the white→slate gradient: flip to dark.
                color: AppColors.base,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.autoSelectBest,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.optimized,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.emerald,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

/// Single server row inside the picker.
class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.selected,
    required this.onTap,
  });

  final ServerConfig server;
  final bool selected;
  final VoidCallback onTap;

  Color get _protocolColor {
    return switch (server.protocol) {
      ServerProtocol.awg => AppColors.emerald,
      ServerProtocol.gw => AppColors.teal,
      ServerProtocol.vless => AppColors.cyan,
    };
  }

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      pressedScale: 0.985,
      child: LiquidTile(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderRadius: AppRadii.card,
        selected: selected,
        accent: AppColors.emerald,
        elevated: false,
        topColor: GlassPalette.interiorBottom,
        bottomColor: GlassPalette.interiorBottom,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 42,
              height: 42,
              child: ClipOval(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            GlassPalette.interiorTop,
                            GlassPalette.interiorBottom,
                          ],
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        server.flag,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    const CompactBorder(
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: [
                      if (server.premium) ...<Widget>[
                        const Icon(
                          Icons.star_rounded,
                          key: ValueKey<String>('premium-star'),
                          color: AppColors.warning,
                          size: 17,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          server.country == 'Unknown'
                              ? server.cleanName
                              : server.country,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _protocolColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          server.protocol.displayName,
                          style: TextStyle(
                            color: _protocolColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.emerald,
                size: 18,
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
