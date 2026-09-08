import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../motion/lite_mode.dart';
import '../motion/motion_curves.dart';
import '../motion/press_feedback.dart';
import 'pulse_badge.dart';

/// Central circular power button.
///
/// The dial is **stationary**: no breathing, no pulsing glow, no shimmering
/// edges — so the rest of the UI reads as calm. Only in the connecting
/// state a slim gradient arc rotates around the rim to indicate activity.
///
/// Visual language:
///  * **idle** — dark glass disk with a thin hairline border and the
///    shield glyph in muted white.
///  * **connecting / disconnecting** — same base, with a 90° gradient arc
///    rotating once every 1.6 s around the rim.
///  * **connected** — face filled with a soft emerald→cyan gradient, a
///    power glyph in dark emerald, and a single fixed glow behind it.
class ShieldDial extends StatefulWidget {
  const ShieldDial({
    super.key,
    required this.state,
    required this.onTap,
    this.size = 188,
  });

  final TunnelState state;
  final VoidCallback onTap;
  final double size;

  @override
  State<ShieldDial> createState() => _ShieldDialState();
}

class _ShieldDialState extends State<ShieldDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    LiteMode.instance.addListener(_sync);
    _sync();
  }

  void _sync() {
    final bool animate =
        LiteMode.instance.isEnabled(RabochiyEffect.dialParticles);
    final bool shouldSpin = animate && _isBusy;
    if (shouldSpin) {
      if (!_sweep.isAnimating) _sweep.repeat();
    } else {
      _sweep.stop();
    }
  }

  @override
  void didUpdateWidget(covariant ShieldDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    LiteMode.instance.removeListener(_sync);
    _sweep.dispose();
    super.dispose();
  }

  bool get _isBusy =>
      widget.state == TunnelState.connecting ||
      widget.state == TunnelState.disconnecting;

  /// Tapping the dial while a handshake is in flight cancels the
  /// attempt, so the control must stay responsive in that state.
  bool get _tapLocked => widget.state == TunnelState.disconnecting;

  bool get _isConnected => widget.state == TunnelState.connected;

  @override
  Widget build(BuildContext context) {
    final double s = widget.size;

    return PressScale(
      enabled: !_tapLocked,
      onTap: _tapLocked ? () {} : widget.onTap,
      pressedScale: 0.94,
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Soft one-shot drop glow for connected state — fixed alpha, no
            // breathing.
            if (_isConnected)
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.emerald.withValues(alpha: 0.35),
                      blurRadius: 44,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            // Outer hairline ring.
            AnimatedContainer(
              duration: RabochiyDurations.tabSwitch,
              curve: RabochiyCurves.brisk,
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isConnected
                    ? AppColors.emerald.withValues(alpha: 0.12)
                    : AppColors.surface.withValues(alpha: 0.6),
                border: Border.all(
                  color: _isConnected
                      ? AppColors.emerald.withValues(alpha: 0.45)
                      : AppColors.border,
                  width: 1,
                ),
              ),
            ),
            // Rotating arc for the busy state.
            if (_isBusy)
              AnimatedBuilder(
                animation: _sweep,
                builder: (_, _) => Transform.rotate(
                  angle: _sweep.value * 2 * math.pi,
                  child: SizedBox(
                    width: s,
                    height: s,
                    child: CustomPaint(
                      painter: const _ArcPainter(),
                    ),
                  ),
                ),
              ),
            // Inner face.
            Container(
              width: s * 0.76,
              height: s * 0.76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _isConnected
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          Color(0xFFFFFFFF),
                          Color(0xFFD2D6DC),
                          Color(0xFF8B919B),
                        ],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          AppColors.surfaceElevated.withValues(alpha: 0.95),
                          AppColors.surface.withValues(alpha: 0.95),
                        ],
                      ),
                border: Border.all(
                  color: _isConnected
                      ? Colors.white.withValues(alpha: 0.22)
                      : AppColors.border,
                  width: 1,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.power_settings_new_rounded,
                  size: s * 0.32,
                  // White face when connected — the glyph flips dark so it
                  // keeps contrast on the monochrome ramp.
                  color: _isConnected
                      ? AppColors.base
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin 90°-arc painter used while the dial is busy (connecting /
/// disconnecting). Sits right on top of the hairline ring.
class _ArcPainter extends CustomPainter {
  const _ArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final double strokeWidth = size.width * 0.04;
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: <Color>[
          Colors.transparent,
          AppColors.emerald.withValues(alpha: 0.85),
          AppColors.cyan.withValues(alpha: 0.55),
          Colors.transparent,
        ],
        stops: const <double>[0.0, 0.12, 0.22, 0.3],
      ).createShader(rect);

    final Rect inset = rect.deflate(strokeWidth / 2);
    canvas.drawArc(inset, -math.pi / 2, math.pi * 0.6, false, paint);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) => false;
}
