import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/app_theme.dart';
import '../motion/glass.dart';
import '../l10n/app_localizations.dart';
import '../motion/press_feedback.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import 'premium_screen.dart';

/// Account tab: displays user ID, mnemonic (QR + text), current plan
/// status, and the management actions (Buy Premium, Activate code,
/// Log out). Visually consistent with the rest of the app — same
/// `GlassCard`, `PressScale`, `AppColors`, `AppRadii`.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  String? _userId;
  String? _mnemonic;
  bool _loading = true;
  bool _showMnemonic = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    // Refresh premium state in the background so the badge reflects any
    // out-of-band changes (code activation, plan extension, manual
    // admin update).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        context.read<AppProvider>().refreshUserState();
      } catch (_) {
        // Provider not in tree (tests) — silently skip.
      }
    });
  }

  Future<void> _loadUserData() async {
    final api = _api();
    final userId = await api.getUserId();
    final mnemonic = await api.getMnemonic();
    if (!mounted) return;
    setState(() {
      _userId = userId;
      _mnemonic = mnemonic;
      _loading = false;
    });
  }

  ApiService _api() {
    try {
      return context.read<AppProvider>().apiService;
    } catch (_) {
      return ApiService();
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // contentTextStyle was removed from SnackBar in newer Flutter;
        // style the content directly instead (same white-on-emerald look).
        content: DefaultTextStyle(
          style: const TextStyle(color: AppColors.base),
          child: Text('$label ${AppLocalizations.of(context)!.accountCopied}'),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.emerald,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.tile),
      ),
    );
  }

  void _openPremium() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const PremiumScreen()),
    );
  }

  /// Asks the user to confirm before showing the recovery phrase.
  /// Anyone seeing the phrase can take over the account, so we treat
  /// reveal as a deliberate action and gate it with an explanatory
  /// dialog (matches the GW-style "Show phrase" flow).
  Future<void> _onRevealMnemonic() async {
    if (_showMnemonic) {
      setState(() => _showMnemonic = false);
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _MnemonicWarningDialog(l10n: l10n),
    );
    if (ok == true && mounted) setState(() => _showMnemonic = true);
  }

  /// Pushes a non-dismissible glass spinner onto the **root** navigator.
  /// Always pushed via `useRootNavigator: true` so the later
  /// `pushNamedAndRemoveUntil(..., (_) => false)` reliably tears the
  /// overlay down — even if AccountScreen has already been disposed
  /// because of the route change.
  void _showRootLoading() {
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              color: AppColors.emerald,
              strokeWidth: 2.4,
            ),
          ),
        ),
      ),
    );
  }

  /// Permanently deletes the account on the server, then drops local
  /// credentials and bounces back to /welcome.
  ///
  /// **Order matters** — we hit on-disk storage *first* and the native
  /// VPN engine *last* so that a stuck IPSec disconnect or a thrown
  /// `PlatformException` cannot leave the user re-logged on the next
  /// launch (the previous version would clear creds only after a 2-s
  /// disconnect timeout, racing with the activity teardown which
  /// users were experiencing as "выкидывает с прилы").
  Future<void> _deleteAccount() async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _DestructiveDialog(
        icon: Icons.delete_forever_rounded,
        iconColor: AppColors.error,
        title: l10n.accountDeleteConfirmTitle,
        body: l10n.accountDeleteConfirmBody,
        cancelLabel: l10n.accountDeleteKeep,
        actionLabel: l10n.accountDeleteConfirmAction,
        actionGradient: null,
        actionColor: AppColors.error,
      ),
    );
    if (confirm != true || !mounted) return;

    // Snapshot every InheritedWidget read we'll need *before* the
    // first `await`. After the spinner pushes a route, AccountScreen's
    // own context becomes a defunct lookup point — anything pulled
    // through `context.read` past that point can throw or, worse,
    // resolve to a navigator inside a torn-down route.
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<AppProvider>();
    final api = provider.apiService;

    setState(() => _deleting = true);
    _showRootLoading();

    // Hit the backend first — on success it's gone server-side; on
    // 404 it was already gone; both cases proceed to local cleanup.
    String? deleteResult;
    try {
      deleteResult = await api.deleteAccount();
    } catch (_) {
      deleteResult = ApiService.deleteAccountNetwork;
    }

    final bool serverGone = deleteResult == null ||
        deleteResult == ApiService.deleteAccountNotFound;

    // Local cleanup is unconditional once the user confirmed — even
    // a network failure shouldn't trap them in an account they asked
    // to delete. ApiService.logout() already wipes prefs.
    try {
      await api.logout();
    } catch (_) {/* prefs unavailable — last resort below */}

    // In-memory provider state (premium flag, selected server, etc.)
    // and any running heartbeat / timer / tunnel are cleared here.
    try {
      await provider.resetSession();
    } catch (_) {/* best effort */}

    // pushNamedAndRemoveUntil with a (_) => false predicate also
    // tears down the spinner dialog — no manual pop needed and no
    // race against AccountScreen's dispose.
    rootNavigator.pushNamedAndRemoveUntil('/welcome', (_) => false);

    // Toast last so the user sees feedback on /welcome.
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          serverGone ? l10n.accountDeleteSuccess : l10n.accountDeleteError,
        ),
        backgroundColor:
            serverGone ? AppColors.emerald : AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.tile),
      ),
    );
  }

  Future<void> _logout() async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _DestructiveDialog(
        icon: Icons.logout_rounded,
        iconColor: AppColors.error,
        title: l10n.accountLogoutConfirmTitle,
        body: l10n.accountLogoutConfirmBody,
        cancelLabel: l10n.accountCancel,
        actionLabel: l10n.accountLogoutConfirmAction,
        actionGradient: null,
        actionColor: AppColors.error,
      ),
    );
    if (confirm != true || !mounted) return;

    // Same pattern as _deleteAccount: capture every InheritedWidget
    // dependency before the first await.
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final provider = context.read<AppProvider>();
    final api = provider.apiService;

    _showRootLoading();

    // 1) Wipe persistent credentials FIRST so an ANR / kill at any
    //    later point still results in /welcome on next launch.
    try {
      await api.logout();
    } catch (_) {/* prefs unavailable — extremely rare */}

    // 2) Reset in-memory state (also drops the tunnel with a 2-s
    //    timeout — see AppProvider.resetSession).
    try {
      await provider.resetSession();
    } catch (_) {/* best effort */}

    // 3) Hop to /welcome. The (_) => false predicate also pops the
    //    spinner dialog so we don't have to dismiss it manually.
    rootNavigator.pushNamedAndRemoveUntil('/welcome', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 120),
            children: <Widget>[
              Text(
                l10n.accountTitle,
                style: const TextStyle(
                  fontSize: 26,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 24),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 64),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.emerald,
                      strokeWidth: 2,
                    ),
                  ),
                )
              else ...<Widget>[
                _PlanCard(
                  l10n: l10n,
                  onBuy: _openPremium,
                ),
                const SizedBox(height: 16),
                _QrCard(l10n: l10n, userId: _userId),
                const SizedBox(height: 16),
                _MnemonicCard(
                  l10n: l10n,
                  mnemonic: _mnemonic,
                  showMnemonic: _showMnemonic,
                  onToggle: _onRevealMnemonic,
                  onCopy: _mnemonic == null
                      ? null
                      : () => _copyToClipboard(
                            _mnemonic!,
                            l10n.accountRecoveryPhrase,
                          ),
                ),
                const SizedBox(height: 24),
                _LogoutButton(label: l10n.accountLogout, onTap: _logout),
                const SizedBox(height: 12),
                _DeleteAccountButton(
                  label: l10n.accountDeleteAccount,
                  loading: _deleting,
                  onTap: _deleting ? null : _deleteAccount,
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    l10n.accountSaveMnemonicHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
//  Plan card — premium status, expiry date, action row.
// ─────────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.l10n,
    required this.onBuy,
  });

  final AppLocalizations l10n;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final bool isPremium = provider.isPremium;
    final Color accent = isPremium ? AppColors.emerald : AppColors.textMuted;

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: isPremium
                        ? AppColors.signalSoft
                        : null,
                    color: isPremium
                        ? null
                        : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPremium
                        ? Icons.workspace_premium_rounded
                        : Icons.shield_outlined,
                    color: accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.accountPlanTitle,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isPremium
                            ? l10n.accountPlanPremium
                            : l10n.accountPlanFree,
                        style: TextStyle(
                          color: isPremium
                              ? AppColors.emerald
                              : AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      _ExpiryLine(l10n: l10n, isPremium: isPremium),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const GlassDivider(inset: 0),
            const SizedBox(height: 12),
            _PrimaryButton(
              label: l10n.accountBuyPremium,
              icon: Icons.workspace_premium_rounded,
              onTap: onBuy,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpiryLine extends StatefulWidget {
  const _ExpiryLine({required this.l10n, required this.isPremium});

  final AppLocalizations l10n;
  final bool isPremium;

  @override
  State<_ExpiryLine> createState() => _ExpiryLineState();
}

class _ExpiryLineState extends State<_ExpiryLine> {
  int? _premiumEndMs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.read<AppProvider>().apiService;
      final ms = await api.getPremiumEndMillis();
      if (!mounted) return;
      setState(() => _premiumEndMs = ms);
    } catch (_) {/* ignore */}
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isPremium) return const SizedBox.shrink();
    final ms = _premiumEndMs;
    final String suffix;
    if (ms == null || ms <= 0) {
      suffix = widget.l10n.accountPlanUnlimited;
    } else {
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      suffix = '$y-$m-$d';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '${widget.l10n.accountPlanExpires}: $suffix',
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      pressedScale: 0.98,
      child: SizedBox(
        height: 44,
        child: LiquidTile(
          borderRadius: AppRadii.tile,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
//  QR card — encodes the user_id (NOT the recovery phrase!) so the
//  user can import this account on another device by scanning. Showing
//  the QR is safe; showing the mnemonic in QR form would let anyone who
//  saw the screen take over the account.
// ─────────────────────────────────────────────────────────────────────

class _QrCard extends StatelessWidget {
  const _QrCard({
    required this.l10n,
    required this.userId,
  });

  final AppLocalizations l10n;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final hasId = userId != null && userId!.isNotEmpty;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      tint: AppColors.emerald.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.qr_code_2_rounded,
                color: AppColors.emerald,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.accountQrTitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (hasId) ...<Widget>[
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: userId!,
                  version: QrVersions.auto,
                  size: 180,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                l10n.accountQrSubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
            ),
          ] else ...<Widget>[
            Center(
              child: Text(
                l10n.accountNotRegistered,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
//  Mnemonic card — recovery phrase, hidden by default. "Show" gates a
//  warning dialog before revealing (handled in the parent state).
// ─────────────────────────────────────────────────────────────────────

class _MnemonicCard extends StatelessWidget {
  const _MnemonicCard({
    required this.l10n,
    required this.mnemonic,
    required this.showMnemonic,
    required this.onToggle,
    required this.onCopy,
  });

  final AppLocalizations l10n;
  final String? mnemonic;
  final bool showMnemonic;
  final VoidCallback onToggle;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      tint: AppColors.emerald.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.vpn_key_outlined,
                color: AppColors.emerald,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.accountRecoveryPhrase,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (mnemonic != null)
                PressScale(
                  onTap: onToggle,
                  child: LiquidTile(
                    borderRadius: BorderRadius.circular(8),

                    accent: AppColors.emerald,
                    selected: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      showMnemonic
                          ? l10n.accountHide
                          : l10n.accountRevealMnemonic,
                      style: const TextStyle(
                        color: AppColors.emerald,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (mnemonic == null)
            Center(
              child: Text(
                l10n.accountNoMnemonic,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
            )
          else if (!showMnemonic)
            Center(
              child: Text(
                l10n.accountTapToReveal,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      mnemonic!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: AppFonts.body,
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (onCopy != null)
                    PressScale(
                      onTap: onCopy!,
                      child: const Icon(
                        Icons.copy,
                        color: AppColors.emerald,
                        size: 20,
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

// ─────────────────────────────────────────────────────────────────────
//  Delete-account button — destructive, only shown after the
//  confirmation dialog returns true.
// ─────────────────────────────────────────────────────────────────────

class _DeleteAccountButton extends StatelessWidget {
  const _DeleteAccountButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      pressedScale: 0.985,
      child: LiquidTile(
        borderRadius: AppRadii.tile,

        accent: AppColors.error,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  color: AppColors.error,
                  strokeWidth: 2,
                ),
              )
            else
              const Icon(
                Icons.delete_forever_rounded,
                color: AppColors.error,
                size: 18,
              ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: AppColors.error.withValues(alpha: 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
//  Reusable destructive confirmation dialog
// ─────────────────────────────────────────────────────────────────────

class _DestructiveDialog extends StatelessWidget {
  const _DestructiveDialog({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.cancelLabel,
    required this.actionLabel,
    this.actionGradient,
    this.actionColor,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String cancelLabel;
  final String actionLabel;
  final Gradient? actionGradient;
  final Color? actionColor;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              body,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: PressScale(
                    onTap: () => Navigator.of(context).pop(false),
                    pressedScale: 0.97,
                    child: SizedBox(
                      height: 44,
                      child: LiquidTile(
                        borderRadius: AppRadii.tile,
                        child: Center(
                          child: Text(
                            cancelLabel,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PressScale(
                    onTap: () => Navigator.of(context).pop(true),
                    pressedScale: 0.97,
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: actionGradient,
                        color: actionGradient == null ? actionColor : null,
                        borderRadius: AppRadii.tile,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        actionLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
//  Mnemonic warning dialog — custom styled to match app UI
// ─────────────────────────────────────────────────────────────────────

class _MnemonicWarningDialog extends StatelessWidget {
  const _MnemonicWarningDialog({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.accountMnemonicWarningTitle,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              l10n.accountMnemonicWarningBody,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: PressScale(
                    onTap: () => Navigator.of(context).pop(false),
                    pressedScale: 0.97,
                    child: SizedBox(
                      height: 44,
                      child: LiquidTile(
                        borderRadius: AppRadii.tile,
                        child: Center(
                          child: Text(
                            l10n.accountCancel,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PressScale(
                    onTap: () => Navigator.of(context).pop(true),
                    pressedScale: 0.97,
                    child: SizedBox(
                      height: 44,
                      child: LiquidTile(
                        borderRadius: AppRadii.tile,
                        child: Center(
                          child: Text(
                            l10n.accountMnemonicWarningContinue,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
//  Logout button
// ─────────────────────────────────────────────────────────────────────

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      pressedScale: 0.985,
      child: LiquidTile(
        borderRadius: AppRadii.tile,

        accent: AppColors.error,
        selected: true,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.logout_rounded,
              color: AppColors.error,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

