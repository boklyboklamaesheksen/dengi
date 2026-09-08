import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../motion/glass.dart';
import '../motion/press_feedback.dart';
import '../providers/app_provider.dart';
import '../screens/server_list_screen.dart';
import 'glass_card.dart';

/// Pressable card that shows the currently selected tunnel location. Taps
/// open the server picker sheet. The trailing ping pill hints at the
/// quality of the link with a soft colour cue.
class LocationTile extends StatelessWidget {
  const LocationTile({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final server = provider.selectedServer;
        final bool isAuto = provider.isAutoSelect;

        String title = server?.serverName ?? l10n.selectServer;
        String subtitle = server?.country ?? l10n.clickToSelect;
        String flag = server?.flag ?? '🌐';

        if (isAuto && server != null) {
          title = l10n.autoSelectBest;
          subtitle = '${l10n.optimized} · ${server.country}';
        } else if (!isAuto && server != null) {
          title = server.country != 'Unknown' ? server.country : server.cleanName;
          subtitle = l10n.manualSelection;
        }

        return PressScale(
          onTap: () => ServerListScreen.show(context),
          child: GlassCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                // Flag avatar uses the liquid recipe: a softly lit signal
                // gradient with the asymmetric highlight overlay on top so
                // it matches every other rounded element on the screen.
                SizedBox(
                  width: 48,
                  height: 48,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: AppColors.signalSoft,
                          ),
                        ),
                        Center(
                          child: Text(flag,
                              style: const TextStyle(fontSize: 24)),
                        ),
                        const CompactBorder(
                          borderRadius:
                              BorderRadius.all(Radius.circular(14)),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (server != null && server.ping > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '${server.ping} ms',
                      style: TextStyle(
                        color: _pingColor(server.ping),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                  size: 22,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _pingColor(int ping) {
    if (ping < 80) return AppColors.emerald;
    if (ping < 180) return AppColors.teal;
    if (ping < 300) return AppColors.warning;
    return AppColors.error;
  }
}
