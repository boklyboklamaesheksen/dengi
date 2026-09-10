import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_theme.dart';
import '../motion/glass.dart';
import '../l10n/app_localizations.dart';
import '../motion/motion_curves.dart';
import '../motion/press_feedback.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/halo_field.dart';

/// Boot screen: checks for existing user, creates new one via API if needed,
/// and shows mnemonic reveal screen for new accounts before entering the app.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 960),
  )..forward();

  late final AnimationController _dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  String? _errorMessage;
  bool _showMnemonic = false;
  bool _enteringApp = false;
  String? _mnemonic;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final existingUserId = prefs.getString(ApiService.userIdPrefsKey);

    if (existingUserId != null &&
        existingUserId.isNotEmpty &&
        existingUserId != 'pending') {
      final existingMnemonic = prefs.getString(ApiService.mnemonicPrefsKey);
      final mnemonicConfirmed =
          prefs.getBool(ApiService.mnemonicConfirmedPrefsKey) ?? true;
      if (!mnemonicConfirmed &&
          existingMnemonic != null &&
          existingMnemonic.isNotEmpty) {
        if (mounted) {
          setState(() {
            _mnemonic = existingMnemonic;
            _userId = existingUserId;
            _showMnemonic = true;
          });
        }
        return;
      }
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
      return;
    }
    try {
      final api = ApiService();
      // Mark as pending so other parallel initializers don't hammer the API.
      await prefs.setString(ApiService.userIdPrefsKey, 'pending');
      final created = await api.createUser();
      api.close();

      if (created != null &&
          created.userId.isNotEmpty &&
          created.userId != 'pending') {
        if (mounted) {
          setState(() {
            _mnemonic = created.mnemonic;
            _userId = created.userId;
            _showMnemonic = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = l10n.splashConnectError;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = l10n.splashServerError;
        });
      }
    }
  }

  Future<void> _retry() async {
    setState(() {
      _errorMessage = null;
    });
    await _init();
  }

  Future<void> _proceedToApp() async {
    if (_enteringApp) return;
    _enteringApp = true;

    // Enter the app immediately — the housekeeping (confirm flag, server
    // catalogue) runs in the background so no extra loading window shows.
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');

    AppProvider? provider;
    try {
      provider = context.read<AppProvider>();
    } catch (_) {}
    try {
      if (provider != null) {
        await provider.apiService.confirmMnemonicSaved();
      } else {
        final api = ApiService();
        await api.confirmMnemonicSaved();
        api.close();
      }
    } catch (_) {/* prefs unavailable — non-blocking */}
    try {
      await provider?.loadServers();
    } catch (_) {
      /* the home screen will surface the provider error state */
    }
  }

  void _copyMnemonic(AppLocalizations l10n) {
    if (_mnemonic == null) return;
    Clipboard.setData(ClipboardData(text: _mnemonic!));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // contentTextStyle was removed from SnackBar in newer Flutter;
        // style the content directly instead (same white-on-emerald look).
        content: DefaultTextStyle(
          style: const TextStyle(color: AppColors.base),
          child: Text(l10n.splashCopied),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.emerald,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.tile),
      ),
    );
  }

  @override
  void dispose() {
    _entrance.dispose();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.base,
      body: HaloField(
        active: true,
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _entrance,
              builder: (_, child) {
                final double t = RabochiyCurves.premiumOut.transform(
                  _entrance.value,
                );
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, 24 * (1 - t)),
                    child: child,
                  ),
                );
              },
              child: _buildContent(l10n),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    if (_showMnemonic && _mnemonic != null) {
      return _MnemonicRevealScreen(
        l10n: l10n,
        mnemonic: _mnemonic!,
        userId: _userId ?? '',
        onProceed: _proceedToApp,
        onCopy: () => _copyMnemonic(l10n),
      );
    }

    if (_errorMessage != null) {
      return _ErrorView(l10n: l10n, message: _errorMessage!, onRetry: _retry);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _AppLogoBadge(size: 118),
        const SizedBox(height: 28),
        const Text(
          'RABOCHIY VPN',
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 4.4,
          ),
        ),
        const SizedBox(height: 56),
        _OrbitDots(controller: _dots),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Mnemonic reveal — styled with GlassCard + LiquidTile accents
// ─────────────────────────────────────────────────────────────────────────────
class _MnemonicRevealScreen extends StatefulWidget {
  const _MnemonicRevealScreen({
    required this.l10n,
    required this.mnemonic,
    required this.userId,
    required this.onProceed,
    required this.onCopy,
  });

  final AppLocalizations l10n;
  final String mnemonic;
  final String userId;
  final VoidCallback onProceed;
  final VoidCallback onCopy;

  @override
  State<_MnemonicRevealScreen> createState() => _MnemonicRevealScreenState();
}

class _MnemonicRevealScreenState extends State<_MnemonicRevealScreen> {

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header icon ──
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: AppColors.signalSoft,
              borderRadius: AppRadii.chunk,
            ),
            child: const Icon(
              Icons.vpn_key_outlined,
              color: AppColors.emerald,
              size: 28,
            ),
          ),
          const SizedBox(height: 20),

          // ── Title ──
          Text(
            l10n.splashSaveRecoveryPhrase,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 16),

          // ── Warning card ──
          GlassCard(
            padding: const EdgeInsets.all(14),
            borderRadius: AppRadii.tile,
            tint: AppColors.error.withValues(alpha: 0.18),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.error,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.splashWarningMnemonic,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Mnemonic card ──
          GlassCard(
            padding: const EdgeInsets.all(16),
            borderRadius: AppRadii.tile,
            tint: AppColors.surface.withValues(alpha: 0.6),
            child: Column(
              children: [
                Text(
                  widget.mnemonic,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                    height: 1.6,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 14),
                // Copy button — outlined, app style
                PressScale(
                  onTap: widget.onCopy,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: AppRadii.tight,
                      border: Border.all(
                        color: AppColors.emerald.withValues(alpha: 0.4),
                      ),
                      color: AppColors.emerald.withValues(alpha: 0.08),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.copy_rounded,
                          color: AppColors.emerald,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.splashCopy,
                          style: const TextStyle(
                            color: AppColors.emerald,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),



          // ── Continue CTA ──
          PressScale(
            onTap: widget.onProceed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: RabochiyCurves.brisk,
              height: 58,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: AppRadii.tile,
              ),
              child: LiquidTile(
                borderRadius: AppRadii.tile,
                accent: AppColors.emerald,
                selected: true,
                child: Center(
                  child: Text(
                    l10n.splashContinue,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
            ),
          ),
        ),
      ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Error view — glass card, signal icon, outlined retry button
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.l10n,
    required this.message,
    required this.onRetry,
  });

  final AppLocalizations l10n;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _AppLogoBadge(size: 80),
          const SizedBox(height: 32),
          GlassCard(
            padding: const EdgeInsets.all(20),
            borderRadius: AppRadii.card,
            tint: AppColors.error.withValues(alpha: 0.12),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    borderRadius: AppRadii.chunk,
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    color: AppColors.error,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                PressScale(
                  onTap: onRetry,
                  child: SizedBox(
                    height: 52,
                    width: double.infinity,
                    child: LiquidTile(
                      borderRadius: AppRadii.tile,
                      accent: AppColors.emerald,
                      selected: true,
                      child: Center(
                        child: Text(
                          l10n.splashRetry,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  App logo badge — gradient ring around the brand logo asset
// ─────────────────────────────────────────────────────────────────────────────
class _AppLogoBadge extends StatelessWidget {
  const _AppLogoBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: AppColors.signal,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.emerald.withValues(alpha: 0.45),
            blurRadius: 44,
            spreadRadius: -4,
          ),
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.25),
            blurRadius: 64,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Container(
        margin: EdgeInsets.all(size * 0.055),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.24),
          color: AppColors.base,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.21),
          child: const Image(
            image: AssetImage('assets/images/logo_rabochiy.png'),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Orbit dots loader — unchanged
// ─────────────────────────────────────────────────────────────────────────────
class _OrbitDots extends StatelessWidget {
  const _OrbitDots({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (int i) {
            final double phase = (controller.value - i * 0.18) % 1.0;
            final double intensity =
                (0.3 + 0.7 * math.max(0.0, math.sin(phase * math.pi))).clamp(
                  0.2,
                  1.0,
                );
            final Color tint = <Color>[
              AppColors.emerald,
              AppColors.teal,
              AppColors.cyan,
            ][i];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tint.withValues(alpha: intensity),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: tint.withValues(alpha: intensity * 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
