import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../motion/glass.dart';
import '../l10n/app_localizations.dart';
import '../motion/lite_mode.dart';
import '../motion/press_feedback.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import 'pay_web_screen.dart';
import 'support_screen.dart';
import '../widgets/brand_logos.dart';
import '../widgets/feature_glyphs.dart';
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
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
                perMonthLabel: _perMonthLabel(_tariffs[i], l10n),
                savingsPercent: _savingsPercent(i),
                onTap: () {
                  if (_selectedIndex != i) {
                    setState(() => _selectedIndex = i);
                  }
                },
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            _TrustRow(l10n: l10n),
            const SizedBox(height: 30),
            _FeatureGrid(l10n: l10n),
          ],
        ),
        const _CloseButton(),
        // Fade so the scrolling list never collides with the button.
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 116,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0x0007080A),
                    Color(0xE607080A),
                    AppColors.base,
                  ],
                  stops: <double>[0, 0.45, 1],
                ),
              ),
            ),
          ),
        ),
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
    return _formatRub(tariff.price);
  }

  static const int _dayMs = 24 * 60 * 60 * 1000;

  double? _ratePerDay(TariffInfo tariff) =>
      tariff.price > 0 && tariff.durationMs > 0
      ? tariff.price / (tariff.durationMs / _dayMs)
      : null;

  /// "≈ 83 ₽/мес" for plans of about two months and longer.
  String? _perMonthLabel(TariffInfo tariff, AppLocalizations l10n) {
    final rate = _ratePerDay(tariff);
    if (rate == null || tariff.durationMs / _dayMs < 45) return null;
    final perMonth = rate * 30;
    return '≈ ${_formatRub(perMonth >= 10 ? perMonth.roundToDouble() : perMonth)}'
        '/${l10n.monthShort}';
  }

  /// Saving against the priciest plan per day, when it is worth showing.
  int? _savingsPercent(int index) {
    final rate = _ratePerDay(_tariffs[index]);
    final rates = _tariffs.map(_ratePerDay).whereType<double>().toList();
    if (rate == null || rates.length < 2) return null;
    final percent = ((1 - rate / rates.reduce(math.max)) * 100).round();
    return percent >= 5 ? percent : null;
  }
}

String _formatRub(double value) {
  final rounded = value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
  return '$rounded ₽';
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
        const PremiumEmblem(size: 64),
        const SizedBox(height: 16),
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
        _PlatinumAccent(text: accent),
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

/// "Pro" in the app's platinum ramp with a slow glint sweeping across.
class _PlatinumAccent extends StatefulWidget {
  const _PlatinumAccent({required this.text});

  final String text;

  @override
  State<_PlatinumAccent> createState() => _PlatinumAccentState();
}

class _PlatinumAccentState extends State<_PlatinumAccent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glint = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  @override
  void initState() {
    super.initState();
    LiteMode.instance.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (LiteMode.instance.isEnabled(RabochiyEffect.dialParticles)) {
      if (!_glint.isAnimating) _glint.repeat();
    } else {
      _glint
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    LiteMode.instance.removeListener(_sync);
    _glint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glint,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (Rect bounds) => LinearGradient(
          colors: const <Color>[
            Color(0xFFC9CED6),
            Color(0xFFE9ECF0),
            Colors.white,
            Color(0xFFE9ECF0),
            Color(0xFFC9CED6),
          ],
          stops: const <double>[0, 0.4, 0.5, 0.6, 1],
          // The glint crosses during the first half, then rests off-text.
          transform: _SlideGradient(_glint.value * 4 - 1.5),
        ).createShader(bounds),
        child: child,
      ),
      child: Text(
        widget.text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 34,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.0,
          height: 1.05,
        ),
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.shift);

  /// Offset in widths of the painted bounds.
  final double shift;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * shift, 0, 0);
}

// ─────────────────────────────────────────────────────────────────────────────
// Trust row

class _TrustRow extends StatelessWidget {
  const _TrustRow({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return LiquidTile(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
      borderRadius: const BorderRadius.all(Radius.circular(18)),
      elevated: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: _TrustItem(
              mark: const FeatureGlyphTile(
                glyph: FeatureGlyph.instant,
                size: 34,
              ),
              label: l10n.premiumTrustInstant,
            ),
          ),
          Expanded(
            child: _TrustItem(
              mark: const FeatureGlyphTile(
                glyph: FeatureGlyph.secure,
                size: 34,
              ),
              label: l10n.premiumTrustSecure,
            ),
          ),
          Expanded(
            child: PressScale(
              onTap: () =>
                  SupportScreen.openTelegram(SupportScreen.telegramChatHandle),
              pressedScale: 0.95,
              child: _TrustItem(
                mark: const TelegramLogo(size: 34),
                label: l10n.premiumTrustSupport,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({required this.mark, required this.label});

  final Widget mark;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: <Widget>[
          mark,
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// What PRO includes

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final List<(FeatureGlyph, String)> items = <(FeatureGlyph, String)>[
      (FeatureGlyph.unblock, l10n.premiumFeatureUnblock),
      (FeatureGlyph.speed, l10n.premiumFeatureSpeed),
      (FeatureGlyph.anonymous, l10n.premiumFeatureAnonymous),
      (FeatureGlyph.hd, l10n.premiumFeatureHd),
      (FeatureGlyph.noLogs, l10n.premiumFeatureNoLogs),
      (FeatureGlyph.noAds, l10n.premiumFeatureNoAds),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            l10n.premiumIncluded,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        for (int i = 0; i < items.length; i += 2) ...<Widget>[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _FeatureCard(glyph: items[i].$1, label: items[i].$2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < items.length
                      ? _FeatureCard(
                          glyph: items[i + 1].$1,
                          label: items[i + 1].$2,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          if (i + 2 < items.length) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.glyph, required this.label});

  final FeatureGlyph glyph;
  final String label;

  @override
  Widget build(BuildContext context) {
    return LiquidTile(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      borderRadius: const BorderRadius.all(Radius.circular(18)),
      elevated: false,
      // Full width: the tile's fill only spans its child.
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FeatureGlyphTile(glyph: glyph, size: 38),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
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
    this.perMonthLabel,
    this.savingsPercent,
  });

  final TariffInfo tariff;
  final bool selected;
  final bool bestValue;
  final String bestValueLabel;
  final String priceTbdLabel;
  final VoidCallback onTap;

  /// "≈ 83 ₽/мес" for longer plans.
  final String? perMonthLabel;

  /// Discount against the priciest plan per day.
  final int? savingsPercent;

  String _formatDuration(AppLocalizations l10n) {
    if (tariff.durationMs <= 0) return '';
    const day = 24 * 60 * 60 * 1000;
    final days = (tariff.durationMs / day).round();
    if (days < 28) return '$days ${l10n.dayShort}';
    if (days < 360) {
      final months = (days / 30).round();
      return '$months ${l10n.monthShort}';
    }
    final years = (days / 365).round();
    return '$years ${l10n.yearShort}';
  }

  String _formatPrice() {
    if (tariff.price <= 0) return priceTbdLabel;
    return _formatRub(tariff.price);
  }

  @override
  Widget build(BuildContext context) {
    final dur = <String>[
      _formatDuration(AppLocalizations.of(context)!),
      ?perMonthLabel,
    ].where((part) => part.isNotEmpty).join(' · ');
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  price,
                  style: TextStyle(
                    color: selected ? AppColors.emerald : AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                if (savingsPercent != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '−$savingsPercent%',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ],
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
