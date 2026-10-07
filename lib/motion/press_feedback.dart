import 'package:flutter/material.dart';

import 'motion_curves.dart';

/// Tappable wrapper that reproduces the "press shrink + elastic release"
/// feel typical of premium mobile UIs.
///
/// It differs from Flutter's stock [InkWell] in two ways:
///   1. there is no Material ripple — instead the child itself scales down
///      while pressed and eases back with a mild overshoot,
///   2. two separate curves / durations are used for press vs. release,
///      mirroring how real haptics behave (tap = sharp, release = springy).
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.965,
    this.pressDuration = RabochiyDurations.press,
    this.releaseDuration = RabochiyDurations.release,
    this.releaseOvershoot = 1.4,
    this.enabled = true,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final Duration pressDuration;
  final Duration releaseDuration;
  final double releaseOvershoot;
  final bool enabled;
  final HitTestBehavior behavior;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 0.0,
    lowerBound: 0.0,
    upperBound: 1.0,
    duration: widget.pressDuration,
    reverseDuration: widget.releaseDuration,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDown(_) {
    if (!widget.enabled) return;
    _controller.animateTo(1.0, curve: RabochiyCurves.brisk);
  }

  void _onUp([_]) {
    if (!widget.enabled) return;
    _controller.animateBack(
      0.0,
      curve: OvershootCurve(widget.releaseOvershoot),
    );
  }

  void _onCancel() => _onUp();

  void _onTap() {
    if (!widget.enabled) return;
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: _onDown,
      onTapUp: _onUp,
      onTapCancel: _onCancel,
      onTap: _onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final double t = _controller.value.clamp(0.0, 1.0);
          final double scale = 1.0 + (widget.pressedScale - 1.0) * t;
          return Transform.scale(
            scale: scale,
            filterQuality: FilterQuality.low,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Route builder that animates a destination with Zapret's signature curves.
/// Honours [RabochiyEffect.smoothTransitions] via the [motionEnabled] flag.
Route<T> rabochiyPageRoute<T>({
  required WidgetBuilder builder,
  required bool motionEnabled,
  RouteSettings? settings,
}) {
  if (!motionEnabled) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 120),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (ctx, _, _) => builder(ctx),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: child,
      ),
    );
  }
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: RabochiyDurations.transition,
    reverseTransitionDuration: RabochiyDurations.transition,
    pageBuilder: (ctx, _, _) => builder(ctx),
    transitionsBuilder: (_, animation, _, child) {
      final Animation<double> curved = CurvedAnimation(
        parent: animation,
        curve: RabochiyCurves.premiumOut,
        reverseCurve: RabochiyCurves.accelerate,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Lightweight helper to schedule a "tap bounce" without a [StatefulWidget]
/// (used inside custom painters and ListView cells to keep allocations low).
class PressController extends ValueNotifier<double> {
  PressController() : super(0.0);

  @visibleForTesting
  void setValue(double v) => value = v.clamp(0.0, 1.0);
}
