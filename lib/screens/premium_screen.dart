import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../motion/glass.dart';
import '../l10n/app_localizations.dart';
import '../motion/press_feedback.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import 'pay_web_screen.dart';
import '../widgets/glass_card.dart';
import '../widgets/halo_field.dart';

/// Premium tariffs picker.
///
/// Layout flow (top → bottom): hero with shader-tinted "Premium" word,
/// six-bullet feature list, dynamic radio-style tariff cards, sticky
/// emerald CTA pinned to the bottom of the safe area.
///
/// We keep the live tariff list from `/vpn/api/v3/client/tariff/get`
/// so prices and plans can be edited on the backend without an app
/// release, but the *visual structure* mirrors the legacy billing
/// screen the original design system was tuned for: hero → benefits →
/// plan picker → single CTA.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> with WidgetsBindingObserver {
  late final ApiService _api;
  bool _ownsApi = false;

  bool _loading = true;
  String? _error;
  List<TariffInfo> _tariffs = const <TariffInfo>[];
  int _selectedIndex = 0;
  int _bestValueIndex = -1;
  bool _purchasing = false;
  String? _pendingPaymentId;
  DateTime? _leftAt;
  bool _checkingPayment = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Re-use the AppProvider's [ApiService] so we don't open a parallel
    // HTTP client just for this screen. Falls back to a local instance
    // if the provider tree is not present (e.g. in widget tests).
    try {
      _api = context.read<AppProvider>().apiService;
    } catch (_) {
      _api = ApiService();
      _ownsApi = true;
    }
    _loadTariffs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsApi) _api.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _leftAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_pendingPaymentId != null && _leftAt != null) {
        final away = DateTime.now().difference(_leftAt!);
        if (away >= const Duration(seconds: 3)) {
          _checkPendingPayment();
        }
      }
      _leftAt = null;
    }
  }

  Future<void> _checkPendingPayment() async {
    if (_checkingPayment || _pendingPaymentId == null) return;
    _checkingPayment = true;
    try {
      final result = await _api.checkPaymentStatus(_pendingPaymentId!);
      final paid = result != null &&
          (result.status == 'paid' || result.isPremium);
      if (!mounted) return;
      if (paid) {
        final l10n = AppLocalizations.of(context)!;
        _showSnack(l10n.premiumActivated, isError: false);
        await context.read<AppProvider>().refreshUserState();
        setState(() => _pendingPaymentId = null);
      }
    } catch (_) {
      // Best-effort — keep invoice pending for next resume.
    } finally {
      if (mounted) setState(() => _checkingPayment = false);
    }
  }

  Future<void> _loadTariffs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.fetchTariffs();
      if (!mounted) return;
      setState(() {
        _tariffs = list;
        _selectedIndex = _defaultSelectedIndex(list);
        _bestValueIndex = _detectBestValueIndex(list);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context)!.accountTariffsError;
      });
    }
  }

  /// Pre-select the best-value plan when possible (cheapest per day);
  /// otherwise fall back to the first tariff to mirror the legacy
  /// behaviour where the longest plan was the default.
  int _defaultSelectedIndex(List<TariffInfo> list) {
    if (list.isEmpty) return 0;
    final best = _detectBestValueIndex(list);
    return best >= 0 ? best : 0;
  }

  /// Returns the index of the plan with the lowest price-per-day,
  /// considering only entries with a positive price and duration.
  /// Returns -1 when no comparison is possible.
  int _detectBestValueIndex(List<TariffInfo> list) {
    int idx = -1;
    double bestRate = double.infinity;
    for (int i = 0; i < list.length; i++) {
      final t = list[i];
      if (t.price <= 0 || t.durationMs <= 0) continue;
      // price per millisecond — units cancel out in the comparison.
      final rate = t.price / t.durationMs;
      if (rate < bestRate) {
        bestRate = rate;
        idx = i;
      }
    }
    return idx;
  }

  Future<void> _purchaseSelected() async {
    if (_purchasing) return;
    if (_selectedIndex < 0 || _selectedIndex >= _tariffs.length) return;
    final tariff = _tariffs[_selectedIndex];
    final l10n = AppLocalizations.of(context)!;

    setState(() => _purchasing = true);
    try {
      final payment = await _api.initiatePayment(
        tariffTechnicalName: tariff.technicalName,
      );
      if (!mounted) return;
      if (payment == null || payment.paymentId.isEmpty) {
        _showSnack(l10n.accountPaymentOpenError, isError: true);
        return;
      }

      if (payment.status == 'paid') {
        // Instant activation path (backend test mode) — nothing to open.
        _showSnack(l10n.premiumActivated, isError: false);
        await context.read<AppProvider>().refreshUserState();
        return;
      }

      if (payment.payUrl.isEmpty) {
        _showSnack(l10n.accountPaymentOpenError, isError: true);
        return;
      }

      setState(() => _pendingPaymentId = payment.paymentId);

      // Storefront WebView: our own /pay page stays inside the app, the
      // provider form hops to the external browser (see [PayWebScreen]).
      // Returns true when the poller sees a successful payment.
      final paid = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => PayWebScreen(
            url: payment.payUrl,
            paymentId: payment.paymentId,
          ),
        ),
      );
      if (!mounted) return;
      if (paid == true) {
        _showSnack(l10n.premiumActivated, isError: false);
        await context.read<AppProvider>().refreshUserState();
        setState(() => _pendingPaymentId = null);
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.emerald,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.tile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.base,
      body: HaloField(
        active: true,
        child: SafeArea(
          child: _buildBody(l10n),
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return Stack(
        children: <Widget>[
          const _CloseButton(),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CircularProgressIndicator(
                  color: AppColors.emerald,
                  strokeWidth: 2,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.accountTariffsLoading,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_error != null) {
      return Stack(
        children: <Widget>[
          const _CloseButton(),
          Center(
            child: _ErrorBlock(
              message: _error!,
              retryLabel: l10n.splashRetry,
              onRetry: _loadTariffs,
            ),
          ),
        ],
      );
    }

    if (_tariffs.isEmpty) {
      return Stack(
        children: <Widget>[
          const _CloseButton(),
          Center(
            child: _ErrorBlock(
              message: l10n.accountTariffsEmpty,
              retryLabel: l10n.splashRetry,
              onRetry: _loadTariffs,
            ),
          ),
        ],
      );
    }

    final selected = _tariffs[_selectedIndex];

    return Stack(
      children: <Widget>[
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: <Widget>[
            const SizedBox(height: 36),
            _Hero(
              title: l10n.premiumHeroTitle,
              accent: l10n.premiumHeroAccent,
              subtitle: l10n.premiumHeroSubtitle,
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                l10n.premiumPickPlan,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            for (int i = 0; i < _tariffs.length; i++) ...<Widget>[
              _TariffRadioCard(
                tariff: _tariffs[i],
                selected: i == _selectedIndex,
                bestValue: i == _bestValueIndex,
                bestValueLabel: l10n.premiumBadgeBest,
                priceTbdLabel: l10n.premiumPriceTbd,
                onTap: () {
                  if (_selectedIndex != i) {
                    setState(() => _selectedIndex = i);
                  }
                },
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 28),
            _FeatureList(l10n: l10n),
          ],
        ),
        const _CloseButton(),
        Align(
          alignment: Alignment.bottomCenter,
          child: _BottomCta(
            label: l10n.premiumBuyForLabel,
            priceLabel: _formatPrice(selected, l10n),
            loading: _purchasing,
            onPressed: _purchaseSelected,
          ),
        ),
      ],
    );
  }

  String _formatPrice(TariffInfo tariff, AppLocalizations l10n) {
    if (tariff.price <= 0) return l10n.premiumPriceTbd;
    final rounded = tariff.price.toStringAsFixed(
      tariff.price == tariff.price.roundToDouble() ? 0 : 2,
    );
    return '$rounded ₽';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero block

class _Hero extends StatelessWidget {
  const _Hero({
    required this.title,
    required this.accent,
    required this.subtitle,
  });

  final String title;
  final String accent;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.signalSoft,
            border: Border.all(color: AppColors.borderStrong),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x40FFFFFF),
                blurRadius: 28,
                spreadRadius: -4,
              ),
            ],
          ),
          child: const Icon(
            Icons.workspace_premium_rounded,
            color: AppColors.emerald,
            size: 28,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 2),
        ShaderMask(
          shaderCallback: (Rect bounds) => const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: <Color>[
              Color(0xFFE0115C), // cherry
              Color(0xFFFF4D2E), // vermilion
              Color(0xFFFFA01E), // orange
            ],
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Text(
            accent,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.0,
              height: 1.05,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.45,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feature list

class _FeatureList extends StatelessWidget {
  const _FeatureList({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final List<_FeatureSpec> items = <_FeatureSpec>[
      _FeatureSpec(Icons.public_rounded, l10n.premiumFeatureUnblock),
      _FeatureSpec(Icons.bolt_rounded, l10n.premiumFeatureSpeed),
      _FeatureSpec(Icons.visibility_off_rounded, l10n.premiumFeatureAnonymous),
      _FeatureSpec(Icons.high_quality_rounded, l10n.premiumFeatureHd),
      _FeatureSpec(Icons.shield_rounded, l10n.premiumFeatureNoLogs),
      _FeatureSpec(Icons.block_rounded, l10n.premiumFeatureNoAds),
    ];
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < items.length; i++) ...<Widget>[
            _FeatureRow(spec: items[i]),
            if (i != items.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(
                  color: AppColors.border,
                  height: 1,
                  thickness: 1,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _FeatureSpec {
  const _FeatureSpec(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.spec});

  final _FeatureSpec spec;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: AppColors.signalSoft,
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Icon(spec.icon, color: AppColors.emerald, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            spec.label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tariff radio card

class _TariffRadioCard extends StatelessWidget {
  const _TariffRadioCard({
    required this.tariff,
    required this.selected,
    required this.bestValue,
    required this.bestValueLabel,
    required this.priceTbdLabel,
    required this.onTap,
  });

  final TariffInfo tariff;
  final bool selected;
  final bool bestValue;
  final String bestValueLabel;
  final String priceTbdLabel;
  final VoidCallback onTap;

  String _formatDuration() {
    if (tariff.durationMs <= 0) return '';
    const day = 24 * 60 * 60 * 1000;
    final days = (tariff.durationMs / day).round();
    if (days < 28) return '$days д';
    if (days < 360) {
      final months = (days / 30).round();
      return '$months мес';
    }
    final years = (days / 365).round();
    return '$years г';
  }

  String _formatPrice() {
    if (tariff.price <= 0) return priceTbdLabel;
    final rounded = tariff.price.toStringAsFixed(
      tariff.price == tariff.price.roundToDouble() ? 0 : 2,
    );
    return '$rounded ₽';
  }

  @override
  Widget build(BuildContext context) {
    final dur = _formatDuration();
    final price = _formatPrice();

    return PressScale(
      onTap: onTap,
      pressedScale: 0.985,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0x22FFFFFF),
                    Color(0x10FFFFFF),
                    Color(0x06FFFFFF),
                  ],
                )
              : null,
          color: selected ? null : AppColors.surface.withValues(alpha: 0.6),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.75)
                : AppColors.borderStrong,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x26FFFFFF),
                    blurRadius: 18,
                    spreadRadius: -6,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          children: <Widget>[
            // Radio indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? Colors.white
                      : AppColors.borderStrong,
                  width: 2,
                ),
                color: selected
                    ? Colors.white
                    : Colors.transparent,
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Color(0xFF07080A),
                      size: 14,
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          tariff.name.isNotEmpty
                              ? tariff.name
                              : tariff.technicalName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      if (bestValue) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.borderStrong),
                          ),
                          child: Text(
                            bestValueLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (dur.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      dur,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (tariff.description.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      tariff.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              price,
              style: TextStyle(
                color: selected
                    ? AppColors.emerald
                    : AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky bottom CTA

class _BottomCta extends StatelessWidget {
  const _BottomCta({
    required this.label,
    required this.priceLabel,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final String priceLabel;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: PressScale(
        enabled: !loading,
        onTap: loading ? () {} : onPressed,
        pressedScale: 0.98,
        child: SizedBox(
          height: 56,
          child: LiquidTile(
            borderRadius: BorderRadius.circular(18),
            accent: AppColors.emerald,
            selected: true,
            child: Center(
              child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.4,
                  ),
                )
                : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        priceLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Close button (top-right)

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      right: 12,
      child: PressScale(
        onTap: () => Navigator.of(context).maybePop(),
        pressedScale: 0.92,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: AppColors.surface.withValues(alpha: 0.7),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: const Icon(
            Icons.close_rounded,
            color: AppColors.textPrimary,
            size: 24,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline error fallback

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.cloud_off_rounded,
            color: AppColors.error,
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          PressScale(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: AppRadii.tile,
                border: Border.all(color: AppColors.borderStrong),
              ),
              child: Text(
                retryLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
