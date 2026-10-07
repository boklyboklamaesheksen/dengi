import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../motion/glass.dart';
import '../motion/press_feedback.dart';
import '../widgets/glass_card.dart';
import '../widgets/halo_field.dart';

/// Support tab: a stack of pressable glass tiles that jump out to Telegram,
/// email, or the Play Store.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const String _telegramChatUrl = 'tg://resolve?domain=chatzapret';
  static const String _telegramNewsUrl = 'tg://resolve?domain=zapretvpnru';
  static const String _emailAddress = 'support@vpnhub.ltd';
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=app.rabochiy.vpn';

  Future<void> _open(Uri uri) async {
    try {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        await launchUrl(uri);
      }
    } catch (_) {
      // Nothing we can do; the tile will remain tappable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final List<_Channel> channels = <_Channel>[
      _Channel(
        icon: Icons.forum_rounded,
        tint: AppColors.emerald,
        title: l10n.supportChannelTelegramChat,
        subtitle: l10n.supportChannelTelegramChatDesc,
        target: 't.me/chatzapret',
        url: Uri.parse(_telegramChatUrl),
      ),
      _Channel(
        icon: Icons.campaign_rounded,
        tint: AppColors.cyan,
        title: l10n.supportChannelTelegramNews,
        subtitle: l10n.supportChannelTelegramNewsDesc,
        target: 't.me/zapretvpnru',
        url: Uri.parse(_telegramNewsUrl),
      ),
      _Channel(
        icon: Icons.mail_outline_rounded,
        tint: AppColors.sky,
        title: l10n.supportChannelEmail,
        subtitle: l10n.supportChannelEmailDesc,
        target: _emailAddress,
        url: Uri(scheme: 'mailto', path: _emailAddress),
      ),
      _Channel(
        icon: Icons.star_outline_rounded,
        tint: AppColors.warning,
        title: l10n.supportChannelRate,
        subtitle: l10n.supportChannelRateDesc,
        target: 'Google Play',
        url: Uri.parse(_playStoreUrl),
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.base,
      body: HaloField(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
            children: <Widget>[
              Text(
                l10n.supportTitle,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.supportSubtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              for (int i = 0; i < channels.length; i += 2) ...<Widget>[
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: _ChannelTile(
                          channel: channels[i],
                          onTap: () => _open(channels[i].url),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (i + 1 < channels.length)
                        Expanded(
                          child: _ChannelTile(
                            channel: channels[i + 1],
                            onTap: () => _open(channels[i + 1].url),
                          ),
                        )
                      else
                        const Expanded(child: SizedBox.shrink()),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Channel {
  const _Channel({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.target,
    required this.url,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final String target;
  final Uri url;
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel, required this.onTap});

  final _Channel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      pressedScale: 0.985,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        edgeStyle: LiquidEdgeStyle.diagonal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: channel.tint.withValues(alpha: 0.16),
                border: Border.all(color: channel.tint.withValues(alpha: 0.32)),
              ),
              child: Icon(channel.icon, color: channel.tint, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              channel.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              channel.subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const Spacer(),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white.withValues(alpha: 0.5),
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
