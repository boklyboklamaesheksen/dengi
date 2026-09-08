import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';

/// Hybrid payment flow (same recipe as the reference storefront):
///
/// 1. The tariff page hosted on our own backend (`/pay?uid=…`) opens
///    INSIDE the app via WebView.
/// 2. The moment the page redirects to the provider payment form
///    (payment.wata.pro — any foreign host), the link is intercepted and
///    opened in the EXTERNAL browser. That way SBP bank deep links
///    (bank10000000000://…) are handled by the system browser which can
///    forward them into the bank's app — WebView crashes on some devices
///    with ERR_UNKNOWN_URL_SCHEME for those schemes.
///
/// While the user pays, the screen polls `payments/check` (every 3s,
/// up to 10 minutes) and additionally re-checks when the app regains
/// focus after the external browser hop.
class PayWebScreen extends StatefulWidget {
  final String url;
  final String paymentId;

  const PayWebScreen({
    super.key,
    required this.url,
    required this.paymentId,
  });

  @override
  State<PayWebScreen> createState() => _PayWebScreenState();
}

class _PayWebScreenState extends State<PayWebScreen>
    with WidgetsBindingObserver {
  late final ApiService _api;
  late final WebViewController _controller;
  Timer? _pollTimer;
  bool _pageLoading = true;
  bool _rendererCrashed = false;
  bool _closing = false;
  bool _externalOpened = false;

  static const _pollInterval = Duration(seconds: 3);
  static const _timeout = Duration(minutes: 10);

  /// Host of our own storefront — only it stays inside the WebView.
  static String get _inAppHost => Uri.parse(ApiService.defaultBaseUrl).host;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _api = ApiService();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.base)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _handleNavigation,
        onPageStarted: (_) => setState(() {
          _pageLoading = true;
          _rendererCrashed = false;
        }),
        onPageFinished: (_) => setState(() => _pageLoading = false),
        onWebResourceError: (error) {
          if (error.errorCode == -1) {
            // Renderer crash — offer a manual reload.
            if (mounted) {
              setState(() {
                _pageLoading = false;
                _rendererCrashed = true;
              });
            }
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.url));

    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _api.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the external browser — poll right away instead of
    // waiting for the next timer tick.
    if (state == AppLifecycleState.resumed && !_closing) {
      _checkOnce();
    }
  }

  NavigationDecision _handleNavigation(NavigationRequest request) {
    final uri = Uri.parse(request.url);
    if (uri.host == _inAppHost || uri.host.isEmpty) {
      return NavigationDecision.navigate;
    }
    // Foreign host (payment provider form) → hand over to the system
    // browser once, keep the WebView on our storefront behind it.
    if (!_externalOpened) {
      _externalOpened = true;
      launchUrl(uri, mode: LaunchMode.externalApplication)
          .catchError((_) => false);
    }
    return NavigationDecision.prevent;
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(_pollInterval, (_) => _checkOnce());
  }

  Future<void> _checkOnce() async {
    if (_closing) return;
    try {
      final result = await _api.checkPaymentStatus(widget.paymentId);
      if (!mounted || result == null) return;
      if (result.status == 'paid' || result.isPremium) {
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (_) {
      // Best-effort — the next tick will retry.
    }
  }

  Future<void> _finish() async {
    if (_closing) return;
    _closing = true;
    _pollTimer?.cancel();
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.base,
      appBar: AppBar(
        backgroundColor: AppColors.base,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
          onPressed: _finish,
        ),
        title: Text(
          l10n.premiumPaymentTitle,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: <Widget>[
          WebViewWidget(controller: _controller),
          if (_pageLoading && !_rendererCrashed)
            const Center(
              child: CircularProgressIndicator(
                color: AppColors.emerald,
                strokeWidth: 2,
              ),
            ),
          if (_rendererCrashed)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    l10n.payLoadFailed,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _pageLoading = true;
                        _rendererCrashed = false;
                      });
                      _controller.reload();
                    },
                    child: Text(l10n.splashRetry),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
