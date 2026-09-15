import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../motion/glass.dart';
import 'glass_card.dart';

/// Download / upload tiles with a bezier sparkline each. Designed as two
/// equal-width glass cards separated by a thin gutter. The sparkline history
/// buffer rolls at about 1 Hz (driven from the caller).
class SignalMeter extends StatefulWidget {
  const SignalMeter({
    super.key,
    required this.downloadBytesPerSec,
    required this.uploadBytesPerSec,
    required this.isConnected,
    required this.downloadLabel,
    required this.uploadLabel,
    this.downloadTotalBytes = 0,
    this.uploadTotalBytes = 0,
  });

  final int downloadBytesPerSec;
  final int uploadBytesPerSec;
  final bool isConnected;
  final String downloadLabel;
  final String uploadLabel;

  /// Total bytes transferred this session — shown instead of the
  /// instantaneous speed.
  final int downloadTotalBytes;
  final int uploadTotalBytes;

  @override
  State<SignalMeter> createState() => _SignalMeterState();
}

class _SignalMeterState extends State<SignalMeter> {
  static const int _bufferSize = 24;
  final Queue<double> _down = Queue<double>();
  final Queue<double> _up = Queue<double>();

  int _lastDown = -1;
  int _lastUp = -1;

  @override
  void didUpdateWidget(covariant SignalMeter old) {
    super.didUpdateWidget(old);
    if (widget.downloadBytesPerSec != _lastDown ||
        widget.uploadBytesPerSec != _lastUp) {
      _lastDown = widget.downloadBytesPerSec;
      _lastUp = widget.uploadBytesPerSec;
      _push();
    }
  }

  void _push() {
    _down.add(_lastDown.toDouble().clamp(0, double.maxFinite));
    _up.add(_lastUp.toDouble().clamp(0, double.maxFinite));
    while (_down.length > _bufferSize) {
      _down.removeFirst();
    }
    while (_up.length > _bufferSize) {
      _up.removeFirst();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _MeterTile(
            title: widget.downloadLabel,
            bytes: widget.downloadTotalBytes,
            history: _down.toList(growable: false),
            primary: AppColors.emerald,
            secondary: AppColors.teal,
            icon: Icons.arrow_downward_rounded,
            isConnected: widget.isConnected,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MeterTile(
            title: widget.uploadLabel,
            bytes: widget.uploadTotalBytes,
            history: _up.toList(growable: false),
            primary: AppColors.cyan,
            secondary: AppColors.sky,
            icon: Icons.arrow_upward_rounded,
            isConnected: widget.isConnected,
          ),
        ),
      ],
    );
  }
}

class _MeterTile extends StatelessWidget {
  const _MeterTile({
    required this.title,
    required this.bytes,
    required this.history,
    required this.primary,
    required this.secondary,
    required this.icon,
    required this.isConnected,
  });

  final String title;
  final int bytes;
  final List<double> history;
  final Color primary;
  final Color secondary;
  final IconData icon;
  final bool isConnected;

  String get _value {
    if (!isConnected || bytes <= 0) return '0.00';
    final int i = (math.log(bytes) / math.log(1024)).floor().clamp(0, 3);
    final double v = bytes / math.pow(1024, i);
    return v.toStringAsFixed(v < 10 ? 2 : 1);
  }

  String get _unit {
    if (bytes <= 0) return 'KB';
    const List<String> suffixes = <String>['B', 'KB', 'MB', 'GB'];
    final int i = (math.log(bytes) / math.log(1024)).floor().clamp(0, 3);
    return suffixes[i];
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      edgeStyle: LiquidEdgeStyle.diagonal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 14, color: primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontFamily: 'Inter',
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
              children: <TextSpan>[
                TextSpan(text: _value),
                TextSpan(
                  text: ' $_unit',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 24,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparklinePainter(
                history: history,
                primary: primary,
                secondary: secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.history,
    required this.primary,
    required this.secondary,
  });

  final List<double> history;
  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    if (history.length < 2) {
      _drawBaseline(canvas, size);
      return;
    }

    final double maxVal = history.reduce(math.max);
    final double minVal = history.reduce(math.min);
    final double range = math.max(maxVal - minVal, 1.0);

    final List<Offset> points = <Offset>[];
    for (int i = 0; i < history.length; i++) {
      final double dx = size.width * (i / (history.length - 1));
      final double norm = (history[i] - minVal) / range;
      final double dy =
          size.height - norm * size.height * 0.9 - size.height * 0.05;
      points.add(Offset(dx, dy));
    }

    final Path fill = Path()..moveTo(points.first.dx, size.height);
    for (final Offset p in points) {
      fill.lineTo(p.dx, p.dy);
    }
    fill.lineTo(size.width, size.height);
    fill.close();

    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          primary.withValues(alpha: 0.45),
          primary.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    final Paint stroke = Paint()
      ..shader = LinearGradient(
        colors: <Color>[primary, secondary],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path line = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      line.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(line, stroke);
  }

  void _drawBaseline(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.history != history ||
      old.primary != primary ||
      old.secondary != secondary;
}
