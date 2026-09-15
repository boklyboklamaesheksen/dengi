import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../services/api_service.dart';

/// Payment flow — the provider form opens in the SYSTEM BROWSER
/// (LaunchMode.externalApplication), exactly like the VLESS VPN app did.
/// This screen stays in the app as a lightweight status overlay: it polls
/// `payments/check` every 3 s (10 min budget) and pops with `true` the
/// moment the webhook activates the premium.
class PayWebScreen extends StatefulWidget {
  const PayWebScreen({
    super.key,
    required this.url,
    required this.paymentId,
  });

  final String url;
  final String paymentId;

  @override
  State<PayWebScreen> createState() => _PayWebScreenState();
}

class _PayWebScreenState extends State<PayWebScreen> {
  late final ApiService _api;
  Timer? _pollTimer;
  bool _closing = false;
  bool _externalOpened = false;

  static const _pollInterval = Duration(seconds: 3);
  static const _timeout = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _api = ApiService();
    _openExternal();
    _startPolling();
  }

  Future<void> _openExternal() async {
    // Give the status screen one frame so the browser opens on top of it.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted || _externalOpened) return;
    _externalOpened = true;
    await openUrlExternal(widget.url);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _api.close();
    super.dispose();
  }

  /// Any link (deep links, tg:, mailto:) hops to the system handler.
  static Future<void> openUrlExternal(String raw) async {
    final Uri uri = Uri.tryParse(raw) ?? Uri.parse('https://$raw');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Nothing sensible to do if the platform refuses the link.
    }
  }

  Future<void> _startPolling() async {
    final deadline = DateTime.now().add(_timeout);
    _pollTimer = Timer.periodic(_pollInterval, (timer) async {
      if (_closing || !mounted) {
        timer.cancel();
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        _close(paid: false);
        return;
      }
      try {
        final result = await _api.checkPaymentStatus(widget.paymentId);
        if (result != null && result.isPremium && mounted) {
          _close(paid: true);
        }
      } catch (_) {
        // Transient network error — keep polling until the deadline.
      }
    });
  }

  void _close({required bool paid}) {
    if (_closing) return;
    _closing = true;
    _pollTimer?.cancel();
    Navigator.of(context).pop(paid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      appBar: AppBar(
        title: const Text('Оплата'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => _close(paid: false),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(
                color: AppColors.emerald,
                strokeWidth: 2.4,
              ),
              const SizedBox(height: 24),
              Text(
                'Страница оплаты открыта в браузере.'
                ' Завершите платёж там — премиум активируется автоматически.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => openUrlExternal(widget.url),
                child: const Text('Открыть страницу оплаты'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
