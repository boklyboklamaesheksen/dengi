/// Cleans error text before it reaches the UI.
///
/// Raw native/network exceptions carry the backend host or a node IP
/// ("Failed host lookup: 'api…'", "Failed to connect to /203.0.113.7:443").
/// Network failures become a generic localised message; anything else is
/// shown with addresses replaced by "server".
class ErrorSanitizer {
  ErrorSanitizer._();

  static final RegExp _url = RegExp(
    r'\b[a-z][a-z0-9+.-]*://\S+',
    caseSensitive: false,
  );
  static final RegExp _ipv4 = RegExp(
    r'\b\d{1,3}(?:\.\d{1,3}){3}(?::\d{1,5})?\b',
  );
  static final RegExp _ipv6 = RegExp(
    r'\[?\b[0-9a-f]{1,4}(?::[0-9a-f]{0,4}){2,7}\]?(?::\d{1,5})?',
    caseSensitive: false,
  );
  static final RegExp _host = RegExp(
    r'\b(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}(?::\d{1,5})?\b',
    caseSensitive: false,
  );

  static const List<String> _networkPatterns = <String>[
    'unable to resolve host',
    'failed host lookup',
    'no address associated with hostname',
    'failed to connect',
    'connection refused',
    'connection reset',
    'connection closed',
    'connection timed out',
    'connection abort',
    'timed out',
    'timeout',
    'network is unreachable',
    'network unreachable',
    'broken pipe',
    'unexpected end of stream',
    'hostname not verified',
    'handshake',
    'socketexception',
    'clientexception',
    'ssl',
    'econnrefused',
    'econnreset',
    'enetunreach',
    'ehostunreach',
    'etimedout',
  ];

  static bool isNetworkError(String? message) {
    if (message == null || message.trim().isEmpty) return false;
    final lowered = message.toLowerCase();
    return _networkPatterns.any(lowered.contains);
  }

  /// Replaces URLs, IPs and host names with "server".
  static String stripEndpoints(String message) => message
      .replaceAll(_url, 'server')
      .replaceAll(_ipv4, 'server')
      .replaceAll(_ipv6, 'server')
      .replaceAll(_host, 'server');
}
