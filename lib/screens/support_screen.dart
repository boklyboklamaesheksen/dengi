import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../motion/glass.dart';
import '../motion/press_feedback.dart';
import '../widgets/brand_logos.dart';
import '../widgets/glass_card.dart';
import '../widgets/halo_field.dart';

/// Support tab: the Telegram chat up front, the news channel, then e-mail
/// and a Google Play rating.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const String telegramChatHandle = 'chatzapret';
  static const String telegramNewsHandle = 'zapretvpnru';
  static const String _emailAddress = 'support@vpnhub.ltd';
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=app.rabochiy.vpn';

  /// Opens a Telegram chat or channel; without the Telegram app the t.me
  /// page opens in the browser instead of the tap doing nothing.
  static Future<void> openTelegram(String handle) => _open(
    Uri.parse('tg://resolve?domain=$handle'),
    fallback: Uri.parse('https://t.me/$handle'),
  );

  static Future<void> _open(Uri uri, {Uri? fallback}) async {
    for (final target in <Uri>[uri, ?fallback]) {
      try {
        if (await launchUrl(target, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {
        // No handler for this scheme; try the next target.
      }
    }
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
              const SizedBox(height: 24),
              _TelegramChatCard(
                title: l10n.supportChannelTelegramChat,
                subtitle: l10n.supportChannelTelegramChatDesc,
                action: l10n.supportChatAction,
                onTap: () => openTelegram(telegramChatHandle),
              ),
              const SizedBox(height: 12),
              _NewsChannelCard(
                title: l10n.supportChannelTelegramNews,
                subtitle: l10n.supportChannelTelegramNewsDesc,
                action: l10n.supportNewsAction,
                onTap: () => openTelegram(telegramNewsHandle),
              ),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: _SmallChannelCard(
                        mark: const MailMark(size: 44),
                        title: l10n.supportChannelEmail,
                        subtitle: l10n.supportChannelEmailDesc,
                        // The full address shrinks rather than being cut off.
                        footer: const FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _emailAddress,
                            maxLines: 1,
                            style: TextStyle(
                              color: Color(0xFFB4A9FF),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        onTap: () =>
                            _open(Uri(scheme: 'mailto', path: _emailAddress)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SmallChannelCard(
                        mark: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.only(left: 3),
                          child: const GooglePlayLogo(size: 24),
                        ),
                        title: l10n.supportChannelRate,
                        subtitle: l10n.supportChannelRateDesc,
                        footer: const _Stars(),
                        onTap: () => _open(Uri.parse(_playStoreUrl)),
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

/// Primary card: official logo, the handle and a Telegram-blue button.
class _TelegramChatCard extends StatelessWidget {
  const _TelegramChatCard({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const BorderRadius radius = BorderRadius.all(Radius.circular(24));
    return PressScale(
      onTap: onTap,
      pressedScale: 0.985,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: TelegramLogo.blue.withValues(alpha: 0.22),
              blurRadius: 28,
              spreadRadius: -8,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: <Widget>[
              // Opaque base: the glow below must not show through.
              const Positioned.fill(
                child: ColoredBox(color: AppColors.surface),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        TelegramLogo.blue.withValues(alpha: 0.30),
                        const Color(0xFF0F1A24),
                        AppColors.surface,
                      ],
                      stops: const <double>[0, 0.55, 1],
                    ),
                  ),
                ),
              ),
              // Large faint plane as a backdrop motif.
              Positioned(
                right: -18,
                top: -10,
                child: TelegramPlane(
                  size: 132,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const TelegramLogo(size: 52),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                title,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                '@${SupportScreen.telegramChatHandle}',
                                style: TextStyle(
                                  color: Color(0xFF7CCBF5),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Color(0xFF38AEEB),
                            TelegramLogo.blueDeep,
                          ],
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: TelegramLogo.blue.withValues(alpha: 0.35),
                            blurRadius: 16,
                            spreadRadius: -6,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const TelegramPlane(size: 18),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              action,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(
                        color: TelegramLogo.blue.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewsChannelCard extends StatelessWidget {
  const _NewsChannelCard({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      pressedScale: 0.985,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        edgeStyle: LiquidEdgeStyle.diagonal,
        child: Row(
          children: <Widget>[
            SizedBox.square(
              dimension: 48,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  const TelegramLogo(size: 46),
                  Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[Color(0xFFFFD86B), Color(0xFFF5A90B)],
                        ),
                        border: Border.all(color: AppColors.surface, width: 2),
                      ),
                      child: const Icon(
                        Icons.campaign_rounded,
                        size: 12,
                        color: Color(0xFF3A2600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: TelegramLogo.blue.withValues(alpha: 0.14),
                border: Border.all(
                  color: TelegramLogo.blue.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                action,
                style: const TextStyle(
                  color: Color(0xFF7CCBF5),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallChannelCard extends StatelessWidget {
  const _SmallChannelCard({
    required this.mark,
    required this.title,
    required this.subtitle,
    required this.footer,
    required this.onTap,
  });

  final Widget mark;
  final String title;
  final String subtitle;
  final Widget footer;
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
            mark,
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const Spacer(),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(child: footer),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < 5; i++)
          const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFC83D)),
      ],
    );
  }
}
