import 'app_localizations.dart';

/// Translates an error code stored on `AppProvider.errorMessage` (or
/// `VpnService.errorMessage`) into a user-facing localised string.
///
/// Keeping the mapping here keeps the provider/service free of
/// `BuildContext` (which they don't and shouldn't have): they store
/// stable codes like `vpn_permission_denied`, the UI translates only
/// at render time.
String localiseError(String? code, AppLocalizations l10n) {
  if (code == null || code.isEmpty) return '';
  switch (code) {
    case 'load_servers_failed':
      return l10n.errorLoadServers;
    case 'no_servers_available':
      return l10n.errorNoServers;
    case 'no_server_selected':
      return l10n.errorNoServerSelected;
    case 'vpn_permission_denied':
      return l10n.errorVpnPermission;
    case 'engine_not_ready':
      return l10n.errorEngineNotReady;
    case 'platform_unsupported':
      return l10n.errorPlatformUnsupported;
    default:
      // Unknown code or a raw native error message — surface verbatim
      // wrapped in the generic prefix so operators see what the
      // backend reported.
      return l10n.errorGeneric(code);
  }
}
