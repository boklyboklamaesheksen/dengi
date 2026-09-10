import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/server_config_model.dart';
import '../motion/glass.dart';
import '../motion/press_feedback.dart';
import '../providers/app_provider.dart';
import '../widgets/glass_card.dart';

/// Bottom-sheet style server picker with a frosted surface and glass tiles.
class ServerListScreen extends StatefulWidget {
  const ServerListScreen({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        const BorderRadius sheetRadius =
            BorderRadius.vertical(top: Radius.circular(28));
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
                          Text(
                            l10n.selectServer,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          PressScale(
                            onTap: () => Navigator.pop(context),
                            pressedScale: 0.9,
                            child: const SizedBox(
                              width: 36,
                              height: 36,
                              child: LiquidTile(
                                padding: EdgeInsets.zero,
                                borderRadius:
                                    BorderRadius.all(Radius.circular(12)),
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
                    // Protocol filter chips
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _FilterChip(
                            label: l10n.filterAll,
                            selected: _protocolFilter == null,
                            onTap: () => setState(() => _protocolFilter = null),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'AmneziaWG 3.1',
                            selected: _protocolFilter == ServerProtocol.awg,
                            onTap: () => setState(() => _protocolFilter = ServerProtocol.awg),
                            color: AppColors.emerald,
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'GW',
                            selected: _protocolFilter == ServerProtocol.gw,
                            onTap: () => setState(() => _protocolFilter = ServerProtocol.gw),
                            color: AppColors.teal,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Consumer<AppProvider>(
                        builder: (context, provider, _) {
                          final List<ServerConfig> allServers = provider.servers.toList()
                            ..sort((a, b) {
                              if (a.protocol == b.protocol) return 0;
                              return a.protocol == ServerProtocol.awg ? -1 : 1;
                            });
                          final List<ServerConfig> servers = _protocolFilter == null
                              ? allServers
                              : allServers.where((s) => s.protocol == _protocolFilter).toList();

                          if (provider.isLoading && allServers.isEmpty) {
                            return const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: AppColors.emerald,
                              ),
                            );
                          }

                          if (servers.isEmpty && !provider.isLoading) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.dns_outlined,
                                    color: Colors.white.withOpacity(0.3),
                                    size: 48,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.serversNotFound,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(
                                16, 0, 16, 24),
                            itemCount: servers.length + 1,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return _AutoTile(
                                  selected: provider.isAutoSelect,
                                  onTap: () {
                                    provider.toggleAutoSelect();
                                    Navigator.pop(context);
                                  },
                                );
                              }
                              final ServerConfig server =
                                  servers[index - 1];
                              final bool selected =
                                  !provider.isAutoSelect &&
                                      provider.selectedServer?.id ==
                                          server.id;
                              return _ServerTile(
                                server: server,
                                selected: selected,
                                onTap: () {
                                  provider.selectServer(server);
                                  Navigator.pop(context);
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
        : Colors.white.withOpacity(0.6);

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
        tint: selected
            ? AppColors.emerald.withValues(alpha: 0.10)
            : null,
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
                      borderRadius:
                          BorderRadius.all(Radius.circular(999)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _protocolColor.withOpacity(0.15),
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
