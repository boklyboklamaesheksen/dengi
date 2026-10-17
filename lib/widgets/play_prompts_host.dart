import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../providers/app_provider.dart';
import '../services/in_app_update_service.dart';
import '../services/vpn_service.dart';

/// Shows Google Play's update dialog and review card only at calm moments:
/// the app is in the foreground, the VPN tab is visible with no sheet,
/// dialog or screen on top of it, the tunnel is not switching state, and
/// the screen has not been touched for [calmDelay]. Critical (immediate)
/// updates skip the idle wait. Also shows the "update downloaded" snackbar.
class PlayPromptsHost extends StatefulWidget {
  const PlayPromptsHost({
    super.key,
    required this.homeTabActive,
    required this.child,
    this.updates,
  });

  final bool homeTabActive;
  final Widget child;

  /// Defaults to [InAppUpdateService.instance]; injectable for tests.
  final InAppUpdateService? updates;

  static const Duration calmDelay = Duration(milliseconds: 2500);

  /// Error snackbars stay up for 4 s; never cover them with Play's UI.
  static const Duration calmDelayAfterError = Duration(seconds: 5);

  @override
  State<PlayPromptsHost> createState() => _PlayPromptsHostState();
}

class _PlayPromptsHostState extends State<PlayPromptsHost>
    with WidgetsBindingObserver {
  late final InAppUpdateService _updates =
      widget.updates ?? InAppUpdateService.instance;
  AppProvider? _provider;
  VpnStatus? _status;
  bool _routeIsCurrent = true;
  int _pointersDown = 0;
  // Restarted by every activity; when it fires the user has been idle.
  Timer? _calmTimer;
  bool _calm = false;
  bool _prompting = false;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _restartSnackBar;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updates.readyToInstall.addListener(_onReadyToInstallChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _markActivity();
      unawaited(_refreshUpdates());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AppProvider provider = Provider.of<AppProvider>(
      context,
      listen: false,
    );
    if (!identical(provider, _provider)) {
      _provider?.removeListener(_onProviderChanged);
      _provider = provider..addListener(_onProviderChanged);
      _status = provider.vpnStatus;
    }
    // Rebuilt by the framework whenever a route is pushed on top or popped.
    final bool routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (routeIsCurrent != _routeIsCurrent) {
      _routeIsCurrent = routeIsCurrent;
      _markActivity();
    }
  }

  @override
  void didUpdateWidget(covariant PlayPromptsHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.homeTabActive != widget.homeTabActive) _markActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markActivity();
      unawaited(_refreshUpdates());
    } else {
      _calmTimer?.cancel();
      _calm = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updates.readyToInstall.removeListener(_onReadyToInstallChanged);
    _provider?.removeListener(_onProviderChanged);
    _calmTimer?.cancel();
    super.dispose();
  }

  void _onProviderChanged() {
    final VpnStatus status = _provider?.vpnStatus ?? VpnStatus.disconnected;
    if (status != _status) {
      _status = status;
      _markActivity();
    } else {
      // Traffic ticks can make the review eligible while the user idles.
      _evaluate();
    }
  }

  void _markActivity() {
    _calm = false;
    _calmTimer?.cancel();
    final Duration delay = _status == VpnStatus.error
        ? PlayPromptsHost.calmDelayAfterError
        : PlayPromptsHost.calmDelay;
    _calmTimer = Timer(delay, () {
      _calm = true;
      _evaluate();
    });
    _evaluate();
  }

  bool get _inForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _evaluate() {
    if (!mounted || _prompting || !_inForeground || !_routeIsCurrent) return;

    if (_updates.pendingOffer == UpdateOffer.immediate) {
      unawaited(_prompt(_updates.showPendingOffer));
      return;
    }

    if (!_calm || !widget.homeTabActive || _pointersDown > 0) return;
    final VpnStatus status = _provider?.vpnStatus ?? VpnStatus.disconnected;
    if (status == VpnStatus.connecting || status == VpnStatus.disconnecting) {
      return;
    }

    if (_updates.pendingOffer == UpdateOffer.flexible) {
      unawaited(_prompt(_updates.showPendingOffer));
      return;
    }
    final review = _provider?.reviewPrompt;
    if (review != null &&
        !_updates.blocksReview &&
        review.shouldRequestReview(status)) {
      unawaited(_prompt(review.requestReview));
    }
  }

  Future<void> _prompt(Future<void> Function() showPlayUi) async {
    _prompting = true;
    try {
      await showPlayUi();
    } finally {
      _prompting = false;
      // Play's UI just closed: any next prompt needs a fresh calm moment.
      if (mounted) _markActivity();
    }
  }

  Future<void> _refreshUpdates() async {
    await _updates.refresh();
    if (!mounted) return;
    if (_updates.readyToInstall.value) _showRestartSnackBar();
    _evaluate();
  }

  void _onReadyToInstallChanged() {
    if (mounted && _updates.readyToInstall.value) _showRestartSnackBar();
  }

  void _showRestartSnackBar() {
    if (_restartSnackBar != null || !_inForeground) return;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final bool vpnConnected = _provider?.vpnStatus == VpnStatus.connected;
    final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller =
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              vpnConnected
                  ? l10n.updateReadyVpnMessage
                  : l10n.updateReadyMessage,
              style: const TextStyle(
                color: AppColors.base,
                fontWeight: FontWeight.w500,
              ),
            ),
            action: SnackBarAction(
              label: l10n.updateRestartAction,
              textColor: AppColors.base,
              onPressed: () => unawaited(_updates.completeUpdate()),
            ),
            persist: true,
            showCloseIcon: true,
            closeIconColor: AppColors.base,
            backgroundColor: AppColors.emerald,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadii.tile),
          ),
        );
    _restartSnackBar = controller;
    controller.closed.whenComplete(() {
      if (identical(_restartSnackBar, controller)) _restartSnackBar = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _pointersDown++;
        _markActivity();
      },
      onPointerUp: (_) => _onPointerReleased(),
      onPointerCancel: (_) => _onPointerReleased(),
      child: widget.child,
    );
  }

  void _onPointerReleased() {
    if (_pointersDown > 0) _pointersDown--;
    _markActivity();
  }
}
