import 'secret_codec.dart';

/// Central store for the backend domain.
///
/// No plain-text URL lives in the build: every baked-in address is gwenc1
/// encoded (see [SecretCodec]) and decoded only right before use. The live
/// value comes from Firebase Remote Config (`encrypted_api_url`) and is
/// applied exclusively through `ApiHostService`, which also handles
/// wildcard subdomains and failover.
class ApiConfig {
  ApiConfig._();

  /// Protective default used until Remote Config answers (first launch
  /// without network, Firebase blocked). Remote Config always wins once
  /// it delivers a valid `encrypted_api_url`.
  static const String defaultBaseUrlEncrypted =
      'gwenc1:aL2Yanp9uWGRq713iNqxr2ra1Gm0l7tijLw=';

  /// Built-in VLESS subscription list (gwenc1, whitespace/comma separated)
  /// used until Remote Config delivers `encrypted_vless_sub_urls`.
  static const String defaultVlessSubscriptionsEncrypted =
      'gwenc1:v3VwaL2Yanp9uWGRq713iNqxr2ra1Gm0l7tijLw=';

  /// Local backend for development only, e.g.
  /// `--dart-define=RABOCHIY_API_BASE=http://10.0.2.2:3002` (plain or
  /// gwenc1). When set, Remote Config and failover are disabled.
  static const String _devOverride = String.fromEnvironment(
    'RABOCHIY_API_BASE',
  );

  static bool get hasDevOverride => _devOverride.trim().isNotEmpty;

  static String get defaultBaseUrl =>
      SecretCodec.decode(defaultBaseUrlEncrypted);

  /// Current backend base URL without a trailing slash. Written only by
  /// `ApiHostService` (and tests).
  static String baseUrl = hasDevOverride
      ? SecretCodec.decode(_devOverride).replaceAll(RegExp(r'/+$'), '')
      : defaultBaseUrl;
}
