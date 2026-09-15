import 'package:flutter/foundation.dart';

import 'device_tier.dart';

/// Opaque effect identifiers. Each effect can be toggled independently so
/// the user (or an auto-tuner) can enable the parts that their device
/// handles well and disable the rest.
enum RabochiyEffect {
  /// Animated halo blobs on background surfaces.
  haloMotion,

  /// Real BackdropFilter blur on glass cards. When disabled we fall back to
  /// a flat translucent gradient.
  frostedGlass,

  /// Animated sparkline + chart stroke redraws in the signal meter.
  signalCharts,

  /// Shimmer / scan-line particle effects on the power dial.
  dialParticles,

  /// Soft inner glow / highlight on glass cards (second paint pass).
  innerGlow,

  /// Smooth page / sheet transitions. When disabled, navigation uses instant
  /// cross-fades — the OS compositor has almost no work to do.
  smoothTransitions,

  /// Floating particle dust on background surfaces (splash / home).
  fieldParticles,
}

/// Central on/off switch matrix for visual effects. Mirrors the
/// "feature-flag bitmask + performance tier default" approach used by other
/// modern Android clients, implemented from scratch against Flutter's
/// [ChangeNotifier] pipeline.
class LiteMode extends ChangeNotifier {
  LiteMode._() {
    DeviceTierProbe.tier.addListener(_onTierChanged);
    _applyTier(DeviceTierProbe.tier.value);
  }

  static final LiteMode instance = LiteMode._();

  final Map<RabochiyEffect, bool> _flags = <RabochiyEffect, bool>{};

  /// When true, the power-saver preset has kicked in. UI reads this so it
  /// can surface a subtle banner / hint to the user.
  bool _powerSaverActive = false;
  bool get isPowerSaverActive => _powerSaverActive;

  void _onTierChanged() {
    _applyTier(DeviceTierProbe.tier.value);
    notifyListeners();
  }

  void _applyTier(DeviceTier tier) {
    switch (tier) {
      case DeviceTier.low:
        _flags[RabochiyEffect.haloMotion] = false;
        _flags[RabochiyEffect.frostedGlass] = false;
        _flags[RabochiyEffect.signalCharts] = true;
        _flags[RabochiyEffect.dialParticles] = false;
        _flags[RabochiyEffect.innerGlow] = false;
        _flags[RabochiyEffect.smoothTransitions] = false;
        _flags[RabochiyEffect.fieldParticles] = false;
        break;
      case DeviceTier.standard:
        _flags[RabochiyEffect.haloMotion] = true;
        _flags[RabochiyEffect.frostedGlass] = true;
        _flags[RabochiyEffect.signalCharts] = true;
        _flags[RabochiyEffect.dialParticles] = true;
        _flags[RabochiyEffect.innerGlow] = false;
        _flags[RabochiyEffect.smoothTransitions] = true;
        _flags[RabochiyEffect.fieldParticles] = true;
        break;
      case DeviceTier.high:
        _flags[RabochiyEffect.haloMotion] = true;
        _flags[RabochiyEffect.frostedGlass] = true;
        _flags[RabochiyEffect.signalCharts] = true;
        _flags[RabochiyEffect.dialParticles] = true;
        _flags[RabochiyEffect.innerGlow] = true;
        _flags[RabochiyEffect.smoothTransitions] = true;
        _flags[RabochiyEffect.fieldParticles] = true;
        break;
    }
  }

  bool isEnabled(RabochiyEffect effect) {
    if (_powerSaverActive) return false;
    return _flags[effect] ?? true;
  }

  void setEnabled(RabochiyEffect effect, bool enabled) {
    if (_flags[effect] == enabled) return;
    _flags[effect] = enabled;
    notifyListeners();
  }

  /// Called by the battery listener (or by manual toggle in settings) when
  /// the OS reports a low-battery state. All animated effects collapse to
  /// static fallbacks.
  void setPowerSaverActive(bool active) {
    if (_powerSaverActive == active) return;
    _powerSaverActive = active;
    notifyListeners();
  }

  @override
  void dispose() {
    DeviceTierProbe.tier.removeListener(_onTierChanged);
    super.dispose();
  }
}
