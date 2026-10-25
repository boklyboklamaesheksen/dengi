import 'app_localizations.dart';
import '../services/error_sanitizer.dart';

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
    case 'awg_handshake_timeout':
      return l10n.errorServerUnreachable;
    case 'auto_pick_failed':
      return l10n.errorAutoPickFailed;
    case 'no_internet':
      return l10n.errorNoInternet;
    default:
      // Unknown code or a raw native error message. Raw text may carry the
      // backend host or a node IP: network failures get the generic
      // "unreachable" text, anything else is shown without addresses.
      if (ErrorSanitizer.isNetworkError(code)) {
        return l10n.errorServerUnreachable;
      }
      return l10n.errorGeneric(ErrorSanitizer.stripEndpoints(code));
  }
}
