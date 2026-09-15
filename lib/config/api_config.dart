/// Central store for the backend domain.
///
/// IMPORTANT: the value below is ONLY the default (fallback). On app start
/// [RemoteConfigService] fetches the current domain from Firebase Remote
/// Config and overwrites this field. If the domain ever gets blocked, change
/// the value in the Firebase console — no Play Store release needed.
///
/// The field is intentionally NOT `const`/`final` so it can be reassigned at
/// runtime (see RemoteConfigService._apply).
class ApiConfig {
  /// Backend domain (auth, server catalogue, tariffs, payments, GW nodes).
  /// Remote Config key: `api_base_url`
  static const _override = String.fromEnvironment('RABOCHIY_API_BASE');
  static String baseUrl = _override.isEmpty
      ? 'https://mc.yarik.app'
      : _override;

  static bool applyRemoteBaseUrl(String value) {
    if (_override.isNotEmpty) return false;
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    baseUrl = uri.toString().replaceAll(RegExp(r'/+$'), '');
    return true;
  }

  // Local debugging (set manually when needed):
  //   Android emulator:      'http://10.0.2.2:3004'
  //   Real device on LAN:    'http://192.168.x.x:3004'
}
