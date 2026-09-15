import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../motion/press_feedback.dart';
import '../motion/glass.dart';
import '../widgets/halo_field.dart';

/// Welcome screen — shown on first launch when there is no `user_id`
/// in SharedPreferences. Lets the user pick between creating a fresh
/// account (which routes to `/` so the splash flow can generate and
/// reveal the mnemonic) or restoring an existing account by typing
/// the recovery phrase (`/login`).
///
/// Mirrors the two-button "I'm a new user / Enter mnemonic phrase"
/// dialog from the reference Android app.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _createNewAccount(BuildContext context) {
    // Splash screen will detect the missing user_id, mint a new account
    // and walk the user through the recovery-phrase reveal flow.
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  void _restoreFromMnemonic(BuildContext context) {
    Navigator.of(context).pushNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.base,
      body: HaloField(
        active: true,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                    const Spacer(flex: 4),
                    _BrandLogo(),
                    const SizedBox(height: 28),
                    const Text(
                      'RABOCHIY VPN',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.welcomeSubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const Spacer(flex: 5),
                    _PrimaryAction(
                      label: l10n.welcomeCreateNew,
                      onTap: () => _createNewAccount(context),
                    ),
                    const SizedBox(height: 14),
                    _SecondaryAction(
                      label: l10n.welcomeRestoreMnemonic,
                      onTap: () => _restoreFromMnemonic(context),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.welcomeFooter,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11.5,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        );
  }
}

class _BrandLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 30,
              spreadRadius: -8,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: const Image(
            image: AssetImage('assets/images/logo_rabochiy.png'),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: LiquidTile(
          borderRadius: AppRadii.tile,
          accent: AppColors.emerald,
          selected: true,
          child: Center(
            child: Text(
              label,
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
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: LiquidTile(
          borderRadius: AppRadii.tile,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
