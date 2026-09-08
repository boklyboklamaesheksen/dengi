import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../motion/glass.dart';
import '../motion/lite_mode.dart';
import '../motion/press_feedback.dart';
import '../widgets/glass_card.dart';
import '../widgets/halo_field.dart';
import 'privacy_policy_screen.dart';
import 'split_tunnel_screen.dart';
import 'traffic_stats_screen.dart';

/// Settings tab: navigation hub for features, privacy, and version info.
/// Designed to be displayed inside the bottom-nav shell — there is no back
/// arrow and no page transition in or out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    } catch (_) {}
  }

  void _pushRoute(Widget page) {
    final bool motionOn =
        LiteMode.instance.isEnabled(RabochiyEffect.smoothTransitions);
    Navigator.push<void>(
      context,
      rabochiyPageRoute<void>(
        motionEnabled: motionOn,
        builder: (_) => page,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.base,
      body: HaloField(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
            children: <Widget>[
              _SectionTitle(l10n.advanced.toUpperCase()),
              const SizedBox(height: 10),
              GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    _SettingsTile(
                      icon: Icons.analytics_outlined,
                      accent: AppColors.emerald,
                      title: l10n.statsTitle,
                      subtitle: l10n.statsSubtitle,
                      onTap: () => _pushRoute(const TrafficStatsScreen()),
                    ),
                    const GlassDivider(),
                    _SettingsTile(
                      icon: Icons.call_split_rounded,
                      accent: AppColors.cyan,
                      title: l10n.splitTunnelTitle,
                      subtitle: l10n.splitTunnelSubtitle,
                      onTap: () => _pushRoute(const SplitTunnelScreen()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _SectionTitle(l10n.appearance.toUpperCase()),
              const SizedBox(height: 10),
              GlassCard(
                padding: EdgeInsets.zero,
                child: _SettingsTile(
                  icon: Icons.shield_outlined,
                  accent: AppColors.sky,
                  title: l10n.privacyPolicy,
                  subtitle: l10n.privacyPolicyLastUpdated,
                  onTap: () => _pushRoute(const PrivacyPolicyScreen()),
                ),
              ),
              const SizedBox(height: 18),
              _SectionTitle(l10n.settingsAbout),
              const SizedBox(height: 10),
              GlassCard(
                padding: EdgeInsets.zero,
                child: _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  accent: AppColors.teal,
                  title: l10n.version,
                  subtitle: _version.isEmpty
                      ? '—'
                      : '$_version${_buildNumber.isEmpty ? '' : ' ($_buildNumber)'}',
                  onTap: null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.0,
        ),
      ),
    );
  }
}

/// Single row inside a settings glass card.
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.accent,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      enabled: onTap != null,
      onTap: onTap ?? () {},
      pressedScale: 0.985,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 40,
              height: 40,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                      ),
                    ),
                    Center(child: Icon(icon, color: accent, size: 20)),
                    const CompactBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(12)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}
