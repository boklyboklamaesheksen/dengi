import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../motion/glass.dart';
import '../motion/motion_curves.dart';
import '../motion/press_feedback.dart';

/// Big call-to-action row at the bottom of the home screen. Morphs between
/// a vivid emerald gradient (disconnected state, urging action) and a
/// floating liquid-glass slab (connected state, offering escape).
class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    super.key,
    required this.isConnected,
    required this.isBusy,
    required this.onTap,
    required this.connectLabel,
    required this.disconnectLabel,
    required this.busyConnectLabel,
    required this.busyDisconnectLabel,
    this.cancelLabel,
  });

  final bool isConnected;
  final bool isBusy;
  final VoidCallback onTap;
  final String connectLabel;
  final String disconnectLabel;
  final String busyConnectLabel;
  final String busyDisconnectLabel;

  /// Label shown while a connection attempt is in flight — tapping
  /// cancels the attempt.
  final String? cancelLabel;

  bool get _isConnecting => !isConnected && isBusy;

  String get _label {
    if (isBusy) {
      if (_isConnecting && cancelLabel != null) return cancelLabel!;
      return isConnected ? busyDisconnectLabel : busyConnectLabel;
    }
    return isConnected ? disconnectLabel : connectLabel;
  }

  @override
  Widget build(BuildContext context) {
    const BorderRadius radius = AppRadii.tile;

    // Both states now share the same dark liquid body; the accent drives
    // the highlight rails and glyph colour so the button still signals
    // "go" vs "stop" without resorting to a flood-fill green background.
    final Color accent =
        isConnected ? AppColors.textSecondary : AppColors.emerald;
    final Color contentColor =
        isConnected ? AppColors.textPrimary : AppColors.emerald;

    final Widget inner = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (isBusy)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(contentColor),
            ),
          )
        else
          Icon(
            isConnected ? Icons.link_off_rounded : Icons.shield_outlined,
            color: contentColor,
            size: 20,
          ),
        const SizedBox(width: 10),
        AnimatedDefaultTextStyle(
          duration: RabochiyDurations.tabSwitch,
          curve: RabochiyCurves.brisk,
          style: TextStyle(
            color: contentColor,
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: 1.6,
          ),
          child: Text(_label),
        ),
      ],
    );

    return PressScale(
      enabled: !_isConnecting || cancelLabel != null,
      onTap: (isBusy && !_isConnecting) ? () {} : onTap,
      child: SizedBox(
        height: 58,
        width: double.infinity,
        child: AnimatedSwitcher(
          duration: RabochiyDurations.tabSwitch,
          switchInCurve: RabochiyCurves.brisk,
          switchOutCurve: RabochiyCurves.brisk,
          transitionBuilder: (Widget child, Animation<double> animation) =>
              FadeTransition(opacity: animation, child: child),
          child: LiquidTile(
            key: ValueKey<bool>(isConnected),
            borderRadius: radius,
            padding: EdgeInsets.zero,
            accent: accent,
            // Connect state keeps the emerald bleeding into the rails
            // (`selected: true`) so it still reads as a ready-to-go
            // action; disconnect stays neutral white.
            selected: !isConnected,
            child: Center(child: inner),
          ),
        ),
      ),
    );
  }
}
