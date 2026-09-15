import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../motion/glass.dart';
import '../motion/lite_mode.dart';
import '../motion/motion_curves.dart';

/// Capsule that advertises the current VPN state. A dot on the left pulses
/// in sync with a sinusoidal breathe — or stays static on low-end devices.
enum TunnelState {
  idle,
  connecting,
  connected,
  disconnecting,
}

class PulseBadge extends StatefulWidget {
  const PulseBadge({
    super.key,
    required this.state,
    required this.idleLabel,
    required this.connectingLabel,
    required this.connectedLabel,
    required this.disconnectingLabel,
  });

  final TunnelState state;
  final String idleLabel;
  final String connectingLabel;
  final String connectedLabel;
  final String disconnectingLabel;

  @override
  State<PulseBadge> createState() => _PulseBadgeState();
}

class _PulseBadgeState extends State<PulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
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
    if (animate) {
      if (!_breathe.isAnimating) _breathe.repeat(reverse: true);
    } else {
      _breathe.stop();
      _breathe.value = 0.5;
    }
  }

  @override
  void dispose() {
    LiteMode.instance.removeListener(_sync);
    _breathe.dispose();
    super.dispose();
  }

  Color get _accent {
    switch (widget.state) {
      case TunnelState.connected:
        return const Color(0xFF10B981); // Bright green
      case TunnelState.connecting:
        return AppColors.cyan;
      case TunnelState.disconnecting:
        return AppColors.sky;
      case TunnelState.idle:
        return const Color(0xFFEF4444); // Bright red
    }
  }

  String get _label {
    switch (widget.state) {
      case TunnelState.connected:
        return widget.connectedLabel;
      case TunnelState.connecting:
        return widget.connectingLabel;
      case TunnelState.disconnecting:
        return widget.disconnectingLabel;
      case TunnelState.idle:
        return widget.idleLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = _accent;
    return FrostedPill(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      borderColor: accent.withValues(alpha: 0.32),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Fixed-size slot keeps the pill's height stable even as the halo
          // breathes. Without this, the Row grew by a few pixels on every
          // pulse cycle and shoved the whole home layout up & down.
          SizedBox(
            width: 20,
            height: 20,
            child: AnimatedBuilder(
              animation: _breathe,
              builder: (_, _) {
                final double t = RabochiyCurves.smooth.transform(_breathe.value);
                final double halo = 1.0 + 0.35 * math.sin(t * math.pi);
                return Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Container(
                      width: 14 * halo,
                      height: 14 * halo,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: accent.withValues(alpha: 0.7),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          AnimatedDefaultTextStyle(
            duration: RabochiyDurations.tabSwitch,
            curve: RabochiyCurves.brisk,
            style: TextStyle(
              color: accent,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
            child: Text(_label),
          ),
        ],
      ),
    );
  }
}
