import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../motion/glass.dart';
import '../motion/motion_curves.dart';
import '../motion/press_feedback.dart';
import '../providers/app_provider.dart';
import '../services/traffic_stats_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_top_bar.dart';
import '../widgets/halo_field.dart';

/// Full-screen dashboard showing aggregated VPN traffic over a selection
/// of predefined time ranges.
class TrafficStatsScreen extends StatefulWidget {
  const TrafficStatsScreen({super.key});

  @override
  State<TrafficStatsScreen> createState() => _TrafficStatsScreenState();
}

class _TrafficStatsScreenState extends State<TrafficStatsScreen> {
  TrafficPeriod _period = TrafficPeriod.day;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final TrafficStatsService stats =
        context.watch<AppProvider>().trafficStats;
    final TrafficSummary summary = stats.summaryFor(_period);

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
                        l10n.statsTitle,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    PressScale(
                      onTap: () => _confirmReset(context, stats, l10n),
                      pressedScale: 0.9,
                      child: FrostedSurface(
                        borderRadius: AppRadii.tile,
                        sigma: 14,
                        compact: true,
                        padding: const EdgeInsets.all(11),
                        child: const SizedBox(
                          width: 20,
                          height: 20,
                          child: Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.error,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: <Widget>[
                    Text(
                      l10n.statsSubtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _PeriodSelector(
                      selected: _period,
                      onChanged: (TrafficPeriod p) =>
                          setState(() => _period = p),
                      l10n: l10n,
                    ),
                    const SizedBox(height: 18),
                    _TotalCard(summary: summary, l10n: l10n),
                    const SizedBox(height: 14),
                    _DetailsGrid(summary: summary, l10n: l10n),
                    const SizedBox(height: 14),
                    _ChartCard(
                      summary: summary,
                      period: _period,
                      l10n: l10n,
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

  Future<void> _confirmReset(
    BuildContext context,
    TrafficStatsService stats,
    AppLocalizations l10n,
  ) async {
    // Replaced Flutter's stock AlertDialog with a liquid-glass panel so
    // the destructive flow inherits the app's visual language: dark
    // gradient body, error-tinted top/bottom rails and a soft backdrop
    // instead of the old grey rectangle.
    final bool? ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: l10n.statsCancel,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
      transitionBuilder:
          (BuildContext dialogCtx, Animation<double> anim, _, _) {
        final Curve curve =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic).value == 0
                ? Curves.linear
                : Curves.easeOutCubic;
        return FadeTransition(
          opacity: anim,
          child: Transform.scale(
            scale: 0.94 + 0.06 * curve.transform(anim.value),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Material(
                    color: Colors.transparent,
                    child: LiquidTile(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                      borderRadius: AppRadii.card,
                      topColor: GlassPalette.interiorBottom,
                      bottomColor: GlassPalette.interiorBottom,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const _DestructiveIcon(),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  l10n.statsResetHint,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            l10n.statsResetConfirm,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13.5,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              _DialogButton(
                                label: l10n.statsCancel,
                                onTap: () =>
                                    Navigator.pop(dialogCtx, false),
                              ),
                              const SizedBox(width: 10),
                              _DialogButton(
                                label: l10n.statsResetButton,
                                onTap: () =>
                                    Navigator.pop(dialogCtx, true),
                                accent: AppColors.error,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (ok == true) {
      await stats.reset();
    }
  }
}

/// Small red-tinted glyph sitting in the dialog's header row.
class _DestructiveIcon extends StatelessWidget {
  const _DestructiveIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.16),
              ),
            ),
            const Center(
              child: Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
                size: 20,
              ),
            ),
            const CompactBorder(
              borderRadius: BorderRadius.all(Radius.circular(11)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Flat text-like button styled as a compact liquid pill. The primary
/// action gets an accent (red for destructive, emerald for safe); the
/// secondary action stays neutral.
class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onTap,
    this.accent,
  });

  final String label;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final bool isAccented = accent != null;
    return PressScale(
      onTap: onTap,
      pressedScale: 0.94,
      child: LiquidTile(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        elevated: false,

        accent: accent,
        selected: isAccented,
        child: Text(
          label,
          style: TextStyle(
            color: isAccented ? accent : AppColors.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

/// Horizontal scroll of period chips.
class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.selected,
    required this.onChanged,
    required this.l10n,
  });

  final TrafficPeriod selected;
  final ValueChanged<TrafficPeriod> onChanged;
  final AppLocalizations l10n;

  String _labelFor(TrafficPeriod p) {
    switch (p) {
      case TrafficPeriod.hour:
        return l10n.statsPeriodHour;
      case TrafficPeriod.day:
        return l10n.statsPeriodDay;
      case TrafficPeriod.week:
        return l10n.statsPeriodWeek;
      case TrafficPeriod.month:
        return l10n.statsPeriodMonth;
      case TrafficPeriod.halfYear:
        return l10n.statsPeriodHalfYear;
      case TrafficPeriod.year:
        return l10n.statsPeriodYear;
      case TrafficPeriod.all:
        return l10n.statsPeriodAll;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: TrafficPeriod.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final TrafficPeriod p = TrafficPeriod.values[index];
          final bool isSelected = p == selected;
          return PressScale(
            onTap: () => onChanged(p),
            pressedScale: 0.95,
            child: FrostedSurface(
              borderRadius: BorderRadius.circular(19),
              sigma: 14,
              compact: true,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 9,
              ),
              child: Text(
                _labelFor(p),
                style: TextStyle(
                  color: isSelected
                      ? AppColors.emerald
                      : AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.summary, required this.l10n});

  final TrafficSummary summary;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.statsTotalTraffic,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          _BigBytes(bytes: summary.totalBytes),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              _MiniChip(
                tint: AppColors.emerald,
                icon: Icons.arrow_downward_rounded,
                label: l10n.statsReceived,
                value: _formatBytes(summary.rxBytes),
              ),
              const SizedBox(width: 10),
              _MiniChip(
                tint: AppColors.cyan,
                icon: Icons.arrow_upward_rounded,
                label: l10n.statsSent,
                value: _formatBytes(summary.txBytes),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BigBytes extends StatelessWidget {
  const _BigBytes({required this.bytes});

  final int bytes;

  @override
  Widget build(BuildContext context) {
    final _Formatted f = _formatBytesParts(bytes);
    return RichText(
      text: TextSpan(
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 48,
            fontWeight: FontWeight.w300,
            color: Colors.white,
            letterSpacing: -1.6,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
          children: <TextSpan>[
            TextSpan(text: f.number),
            TextSpan(
              text: ' ${f.unit}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.tint,
    required this.icon,
    required this.label,
    required this.value,
  });

  final Color tint;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: LiquidTile(
        borderRadius: BorderRadius.circular(14),

        accent: tint,
        selected: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: tint, size: 13),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: tint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsGrid extends StatelessWidget {
  const _DetailsGrid({required this.summary, required this.l10n});

  final TrafficSummary summary;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _InfoTile(
            label: l10n.statsSessions,
            value: summary.sessions.toString(),
            icon: Icons.play_circle_outline_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InfoTile(
            label: l10n.statsOnlineTime,
            value: _formatDuration(summary.onlineSeconds),
            icon: Icons.schedule_rounded,
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w600,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.summary,
    required this.period,
    required this.l10n,
  });

  final TrafficSummary summary;
  final TrafficPeriod period;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    if (summary.buckets.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Center(
          child: Text(
            l10n.statsEmpty,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
            ),
          ),
        ),
      );
    }

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              _chartTitle(period),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
          ),
          SizedBox(
            height: 120,
            child: CustomPaint(
              size: Size.infinite,
              painter: _BarChartPainter(buckets: summary.buckets),
            ),
          ),
        ],
      ),
    );
  }

  String _chartTitle(TrafficPeriod p) {
    switch (p) {
      case TrafficPeriod.hour:
        return l10n.statsPeriodHour.toUpperCase();
      case TrafficPeriod.day:
        return l10n.statsPeriodDay.toUpperCase();
      case TrafficPeriod.week:
        return l10n.statsPeriodWeek.toUpperCase();
      case TrafficPeriod.month:
        return l10n.statsPeriodMonth.toUpperCase();
      case TrafficPeriod.halfYear:
        return l10n.statsPeriodHalfYear.toUpperCase();
      case TrafficPeriod.year:
        return l10n.statsPeriodYear.toUpperCase();
      case TrafficPeriod.all:
        return l10n.statsPeriodAll.toUpperCase();
    }
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({required this.buckets});

  final List<TrafficBucket> buckets;

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) return;

    // Lightweight down-sample: keep at most 48 columns visually so long
    // ranges (year) don't grind down to invisible slivers.
    const int maxColumns = 48;
    final List<int> values = _downsample(buckets, maxColumns);
    final int peak = values.fold<int>(0, math.max);
    if (peak == 0) return;

    final double gap = 2;
    final double totalGap = gap * (values.length - 1);
    final double barWidth =
        ((size.width - totalGap) / values.length).clamp(1.0, 20.0);

    for (int i = 0; i < values.length; i++) {
      final double norm = values[i] / peak;
      final double h = math.max(2.0, norm * size.height * 0.96);
      final double left = i * (barWidth + gap);
      final Rect r = Rect.fromLTWH(
        left,
        size.height - h,
        barWidth,
        h,
      );
      final Paint paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            AppColors.emerald.withValues(alpha: 0.95),
            AppColors.cyan.withValues(alpha: 0.7),
          ],
        ).createShader(r);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(3)),
        paint,
      );
    }
  }

  List<int> _downsample(List<TrafficBucket> src, int maxColumns) {
    if (src.length <= maxColumns) {
      return src.map((TrafficBucket b) => b.totalBytes).toList(growable: false);
    }
    final double chunk = src.length / maxColumns;
    final List<int> out = <int>[];
    for (int i = 0; i < maxColumns; i++) {
      final int from = (i * chunk).floor();
      final int to = ((i + 1) * chunk).floor().clamp(from + 1, src.length);
      int total = 0;
      for (int j = from; j < to; j++) {
        total += src[j].totalBytes;
      }
      out.add(total);
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.buckets != buckets;
}

// ── Helpers ──────────────────────────────────────────────────────────────

class _Formatted {
  const _Formatted(this.number, this.unit);
  final String number;
  final String unit;
}

String _formatBytes(int bytes) {
  final _Formatted f = _formatBytesParts(bytes);
  return '${f.number} ${f.unit}';
}

_Formatted _formatBytesParts(int bytes) {
  if (bytes <= 0) return const _Formatted('0', 'B');
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  final int i = (math.log(bytes) / math.log(1024)).floor().clamp(0, 4);
  final double v = bytes / math.pow(1024, i);
  final String number = v.toStringAsFixed(v < 10 ? 2 : (v < 100 ? 1 : 0));
  return _Formatted(number, units[i]);
}

String _formatDuration(int totalSeconds) {
  if (totalSeconds <= 0) return '0m';
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}
