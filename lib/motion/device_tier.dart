import 'dart:io';
import 'dart:ui' show FlutterView, PlatformDispatcher;

import 'package:flutter/foundation.dart';

/// Three buckets used across the app to decide which visual effects should
/// run. Matches the conceptual performance-tier approach that most polished
/// Android apps use (RAM / CPU / API version signals combined into a single
/// coarse tier), but does not borrow any classifier logic from third-party
/// codebases.
enum DeviceTier { low, standard, high }

/// Evaluates the device once on startup and publishes the result to the
/// rest of the UI layer via a [ValueListenable]. Subsequent listeners (like
/// [LiteMode]) can tune their behaviour without re-running the probe.
class DeviceTierProbe {
  DeviceTierProbe._();

  static final ValueNotifier<DeviceTier> tier =
      ValueNotifier<DeviceTier>(DeviceTier.standard);

  static bool _initialised = false;

  /// Runs the tier probe. Safe to call multiple times; subsequent calls
  /// are no-ops.
  static Future<void> ensureInitialised() async {
    if (_initialised) return;
    _initialised = true;
    try {
      tier.value = await _probe();
    } catch (_) {
      tier.value = DeviceTier.standard;
    }
  }

  static Future<DeviceTier> _probe() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return DeviceTier.high;
    }

    final int cpuCores = Platform.numberOfProcessors;

    // The refresh rate of the running display is a strong signal on Android:
    // 60 Hz panels are almost always bundled with budget SoCs.
    double refreshRate = 60;
    try {
      final FlutterView? view =
          PlatformDispatcher.instance.views.isNotEmpty
              ? PlatformDispatcher.instance.views.first
              : null;
      if (view != null) {
        refreshRate = view.display.refreshRate;
      }
    } catch (_) {}

    // Heuristic — kept intentionally simple so the classifier remains our
    // own work. Real workloads (blur, glass, particles) will be additionally
    // gated by battery level, so any mis-classification here is soft.
    if (cpuCores <= 4 && refreshRate <= 60) {
      return DeviceTier.low;
    }
    if (cpuCores <= 6 || refreshRate <= 60) {
      return DeviceTier.standard;
    }
    return DeviceTier.high;
  }

  /// Allows QA and dev builds to override the probe result.
  @visibleForTesting
  static void debugOverride(DeviceTier value) {
    _initialised = true;
    tier.value = value;
  }
}
