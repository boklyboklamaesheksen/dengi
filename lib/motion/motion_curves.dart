import 'package:flutter/animation.dart';

/// Curated easing curves for Rabochiy VPN.
///
/// These are plain cubic-bezier coefficients — the same four-point math
/// that every modern design system exposes. The palette below is picked so
/// that short taps feel crisp, releases feel elastic, and long transitions
/// decelerate into rest instead of easing out abruptly.
///
/// All constants are expressed via Flutter's native [Cubic] curve, so no
/// platform code or third-party dependency is required.
class RabochiyCurves {
  RabochiyCurves._();

  /// Default motion — fast pickup, gentle landing. Use for press-down feedback
  /// and generic state interpolation.
  static const Cubic brisk = Cubic(0.28, 0.09, 0.32, 1.0);

  /// Strong deceleration curve for entrances. Elements fly in quickly then
  /// settle into place without overshoot.
  static const Cubic decelerate = Cubic(0.22, 1.0, 0.36, 1.0);

  /// Premium "quintic" decelerate — longer tail than [decelerate]. Ideal for
  /// big hero animations (dial toggle, screen transitions).
  static const Cubic premiumOut = Cubic(0.23, 1.0, 0.32, 1.0);

  /// Symmetric ease-in-out used for looping breath/pulse motion.
  static const Cubic smooth = Cubic(0.44, 0.0, 0.56, 1.0);

  /// Sharp ease-in — pulls elements off the stage quickly.
  static const Cubic accelerate = Cubic(0.42, 0.0, 1.0, 1.0);

  /// Mild overshoot — pops a control past its target and bounces back.
  /// Note: [Cubic] y-coordinates can exceed 1.0 to create the overshoot
  /// effect, just like Material's "emphasized" curve.
  static const Cubic softBounce = Cubic(0.34, 1.56, 0.64, 1.0);
}

/// Standardised durations so every surface in the app feels consistent.
class RabochiyDurations {
  RabochiyDurations._();

  /// Press-down reaction (scale shrink, haptic-like snap).
  static const Duration press = Duration(milliseconds: 60);

  /// Press-release with soft elastic tail.
  static const Duration release = Duration(milliseconds: 320);

  /// Tab / chip switch.
  static const Duration tabSwitch = Duration(milliseconds: 260);

  /// Default screen transition.
  static const Duration transition = Duration(milliseconds: 340);

  /// Long entrance animation for hero elements (splash, dial).
  static const Duration hero = Duration(milliseconds: 520);

  /// Ambient loop (pulse, breath, glow).
  static const Duration ambient = Duration(seconds: 4);
}

/// Overshoot-style curve for "enter" animations — the widget pops past its
/// final position by [overshoot] units and settles back.
///
/// Flutter doesn't ship a parameterised overshoot curve out of the box, so we
/// implement the classic formula ourselves. Behaviour is identical to
/// `android.view.animation.OvershootInterpolator(tension)` from AOSP.
class OvershootCurve extends Curve {
  const OvershootCurve([this.tension = 1.4]);

  final double tension;

  @override
  double transformInternal(double t) {
    final double u = t - 1.0;
    return u * u * ((tension + 1.0) * u + tension) + 1.0;
  }
}
