import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../motion/press_feedback.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import '../services/remote_config_service.dart';

/// Login screen: lets users restore their account by typing the BIP39
/// recovery phrase. Legacy longer phrases are still accepted for older
/// accounts, while the visible copy guides current users to the 12-word
/// phrase. On success the central [AppProvider] is told to re-load the
/// server catalogue against the freshly restored user_id.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _mnemonicController = TextEditingController();
  bool _loading = false;
  String? _error;
  ApiService? _apiOwned;

  @override
  void dispose() {
    _mnemonicController.dispose();
    _apiOwned?.close();
    super.dispose();
  }

  Future<void> _login() async {
    final l10n = AppLocalizations.of(context)!;
    final raw = _mnemonicController.text.trim();
    final cleaned = raw.toLowerCase();

    if (cleaned.isEmpty) {
      setState(() => _error = l10n.loginErrorEmpty);
      return;
    }
    final words = cleaned.split(RegExp(r'\s+'));
    if (words.length != 12 && words.length != 24) {
      setState(() => _error = l10n.loginErrorWords);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    await RemoteConfigService.instance.ensureReady();
    if (!mounted) return;
    final api = _apiOwned ??= ApiService();
    final result = await api.login(cleaned);

    if (!mounted) return;
    if (result.ok) {
      // Tell the central provider to refresh the server list against
      // the new user_id so the home screen lands on a populated state.
      try {
        await context.read<AppProvider>().loadServers();
      } catch (_) {
        /* provider may not be ready in tests — ignore */
      }
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
      return;
    }

    setState(() {
      _loading = false;
      _error = _errorMessageFor(result.errorCode, l10n);
    });
  }

  String _errorMessageFor(String? code, AppLocalizations l10n) {
    switch (code) {
      case ApiService.loginInvalidMnemonic:
        return l10n.loginErrorInvalid;
      case ApiService.loginNetworkError:
        return l10n.loginErrorNetwork;
      case ApiService.loginServerError:
        return l10n.loginErrorServer;
      default:
        return l10n.loginErrorServer;
    }
  }

  void _createNewAccount() {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 40),
              PressScale(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                l10n.loginTitle,
                style: const TextStyle(
                  fontSize: 28,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.loginSubtitle,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.6),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              _MnemonicField(
                controller: _mnemonicController,
                hasError: _error != null,
                placeholder: l10n.loginPlaceholder,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              _LoginButton(
                loading: _loading,
                label: l10n.loginRestoreButton,
                onTap: _loading ? null : _login,
              ),
              const Spacer(),
              Center(
                child: PressScale(
                  onTap: _createNewAccount,
                  child: Text(
                    l10n.loginCreateNew,
                    style: const TextStyle(
                      color: AppColors.emerald,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _MnemonicField extends StatelessWidget {
  const _MnemonicField({
    required this.controller,
    required this.hasError,
    required this.placeholder,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool hasError;
  final String placeholder;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasError
              ? AppColors.error.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: TextField(
        controller: controller,
        maxLines: 4,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.none,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.6),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.30),
            fontSize: 14,
          ),
          contentPadding: const EdgeInsets.all(16),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({
    required this.loading,
    required this.label,
    required this.onTap,
  });

  final bool loading;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              AppColors.emerald,
              AppColors.emerald.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.emerald.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: AppColors.base,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.base,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}
