import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../motion/glass.dart';
import '../motion/press_feedback.dart';
import '../providers/app_provider.dart';
import '../services/vpn_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/halo_field.dart';
import '../widgets/location_tile.dart';
import '../widgets/orbit_timer.dart';
import '../widgets/primary_action.dart';
import '../widgets/pulse_badge.dart';
import '../widgets/shield_dial.dart';
import '../widgets/signal_meter.dart';
import 'premium_screen.dart';

/// VPN tab: status badge, session timer, central shield dial, server
/// selector, up/down meters and the primary CTA. No more top-right gear —
/// settings live in their dedicated bottom-nav tab now.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _premiumRouteOpen = false;

  Future<void> _openPremiumScreen() async {
    if (_premiumRouteOpen || !mounted) return;
    _premiumRouteOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const PremiumScreen()),
      );
    } finally {
      _premiumRouteOpen = false;
    }
  }

  Future<void> _toggleVpn(AppProvider provider, bool isConnected) async {
    final VpnStatus status = provider.vpnStatus;

    // Second tap while a connection attempt is in flight cancels it.
    if (status == VpnStatus.connecting) {
      await provider.cancelConnect();
      return;
    }

    if (isConnected) {
      await provider.disconnectVpn();
      return;
    }

    if (provider.selectedServerRequiresPremium) {
      provider.clearError();
      await _openPremiumScreen();
      return;
    }

    await provider.connectVpn();
    if (!mounted) return;

    if (provider.errorMessage == 'premium_required') {
      provider.clearError();
      await _openPremiumScreen();
    }
  }

  TunnelState _tunnelStateFrom(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        return TunnelState.connected;
      case VpnStatus.connecting:
        return TunnelState.connecting;
      case VpnStatus.disconnecting:
        return TunnelState.disconnecting;
      case VpnStatus.disconnected:
      case VpnStatus.error:
        return TunnelState.idle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return ResponsiveScaledBox(
      width: 390,
      child: Scaffold(
        backgroundColor: AppColors.base,
        body: Selector<AppProvider, bool>(
          selector: (context, provider) =>
              provider.vpnStatus == VpnStatus.connected,
          builder: (context, isConnected, child) {
            return HaloField(active: isConnected, child: child);
          },
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Row(
                      children: <Widget>[
                        const Text(
                          'Rabochiy VPN',
                          style: TextStyle(
                            fontSize: 22,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const Spacer(),
                        PressScale(
                          onTap: _openPremiumScreen,
                          pressedScale: 0.97,
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            borderRadius: AppRadii.card,
                            edgeStyle: LiquidEdgeStyle.diagonal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  l10n.homeGetProPrefix,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  l10n.homeGetProAccent,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  l10n.homeGetProSuffix,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Consumer<AppProvider>(
                      builder: (context, provider, _) {
                        final VpnStatus status = provider.vpnStatus;
                        final bool isConnected = status == VpnStatus.connected;
                        final bool isBusy =
                            status == VpnStatus.connecting ||
                            status == VpnStatus.disconnecting;
                        final TunnelState tunnelState = _tunnelStateFrom(
                          status,
                        );

                        return SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.only(
                            bottom: 130,
                          ), // Отступ снизу
                          child: Column(
                            children: <Widget>[
                              PulseBadge(
                                state: tunnelState,
                                idleLabel: l10n.notConnected,
                                connectingLabel: l10n.connectingUpper,
                                connectedLabel: l10n.securelyConnected,
                                disconnectingLabel: l10n.disconnectingUpper,
                              ),
                              const SizedBox(
                                height: 14,
                              ), // Уменьшили с 22 до 14
                              OrbitTimer(
                                elapsed: provider.connectionDuration,
                                active: isConnected || isBusy,
                              ),
                              const SizedBox(
                                height: 16,
                              ), // Уменьшили с 28 до 16
                              ShieldDial(
                                state: tunnelState,
                                onTap: () => _toggleVpn(provider, isConnected),
                              ),
                              const SizedBox(height: 28),
                              const LocationTile(),
                              const SizedBox(height: 14),
                              // Primary action now sits directly under the
                              // location tile — the hero CTA should be the
                              // shortest thumb-travel after picking a server.
                              PrimaryAction(
                                isConnected: isConnected,
                                isBusy: isBusy,
                                onTap: () => _toggleVpn(provider, isConnected),
                                connectLabel: l10n.connectNow,
                                disconnectLabel: l10n.disconnectUpper,
                                busyConnectLabel: l10n.connectingUpper,
                                busyDisconnectLabel: l10n.disconnectingUpper,
                                cancelLabel: l10n.cancelConnecting,
                              ),
                              const SizedBox(height: 14),
                              // Download / Upload meter moved below the CTA
                              // per request — the live throughput is
                              // ambient info, not the primary surface of
                              // the screen.
                              SignalMeter(
                                downloadBytesPerSec:
                                    provider.downloadSpeedBytes,
                                uploadBytesPerSec: provider.uploadSpeedBytes,
                                downloadTotalBytes:
                                    provider.sessionRxBytes,
                                uploadTotalBytes:
                                    provider.sessionTxBytes,
                                isConnected: isConnected,
                                downloadLabel: l10n.download,
                                uploadLabel: l10n.upload,
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
