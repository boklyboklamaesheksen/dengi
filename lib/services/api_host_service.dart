import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../config/secret_codec.dart';

/// A validated backend address: a plain URL or a wildcard template
/// `https://*.api.example.com[/prefix]`.
///
/// Only HTTPS is accepted, without credentials, query or fragment.
/// Internationalised hosts are converted to punycode (dart:io does not do
/// IDNA). A trailing `/vpn/api/...` path is cut off, because the client
/// appends `/vpn/api/v1|v3/...` itself; a prefix in front of it
/// (`https://host/gw/vpn/api/v1/` → `https://host/gw`) is kept.
@immutable
class ApiEndpoint {
  const ApiEndpoint._(this.canonical, {required this.isTemplate});

  /// `https://host[:port][/prefix]`; for templates the host starts with `*.`.
  final String canonical;
  final bool isTemplate;

  static final RegExp _labelPattern = RegExp(
    r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
  );
  static final RegExp _apiSuffix = RegExp(
    r'/vpn/api(?:/.*)?$',
    caseSensitive: false,
  );
  static final RegExp _digits = RegExp(r'^\d{1,5}$');

  /// Base URL for a wildcard label (plain URLs ignore [label]).
  String build(String label) =>
      isTemplate ? canonical.replaceFirst('*', label) : canonical;

  /// Whether [baseUrl] was produced by this endpoint (any label for templates).
  bool owns(String baseUrl) {
    if (!isTemplate) return baseUrl == canonical;
    final star = canonical.indexOf('*');
    final head = canonical.substring(0, star);
    final tail = canonical.substring(star + 1);
    if (!baseUrl.startsWith(head) || !baseUrl.endsWith(tail)) return false;
    final label = baseUrl.substring(head.length, baseUrl.length - tail.length);
    return _labelPattern.hasMatch(label);
  }

  static ApiEndpoint? tryParse(String? raw) {
    var value = raw?.trim() ?? '';
    if (value.isEmpty || value.contains(RegExp(r'\s'))) return null;
    if (!value.contains('://')) value = 'https://$value';

    final schemeEnd = value.indexOf('://');
    if (value.substring(0, schemeEnd).toLowerCase() != 'https') return null;
    final rest = value.substring(schemeEnd + 3);
    if (rest.contains('?') || rest.contains('#')) return null;

    final slash = rest.indexOf('/');
    final authority = slash < 0 ? rest : rest.substring(0, slash);
    var path = slash < 0 ? '' : rest.substring(slash);
    if (authority.isEmpty ||
        authority.contains('@') ||
        authority.contains('[')) {
      return null;
    }

    var host = authority;
    int? port;
    final colon = authority.lastIndexOf(':');
    if (colon >= 0) {
      final portText = authority.substring(colon + 1);
      if (!_digits.hasMatch(portText)) return null;
      port = int.parse(portText);
      if (port < 1 || port > 65535) return null;
      if (port == 443) port = null;
      host = authority.substring(0, colon);
    }

    host = host.toLowerCase();
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    final labels = host.split('.');
    final isTemplate = labels.first == '*';
    final asciiLabels = <String>[];
    for (final label in isTemplate ? labels.skip(1) : labels) {
      final ascii = Punycode.toAsciiLabel(label);
      if (ascii == null || !_labelPattern.hasMatch(ascii)) return null;
      asciiLabels.add(ascii);
    }
    // A wildcard certificate covers exactly one label: `*.com` is invalid.
    if (asciiLabels.isEmpty || (isTemplate && asciiLabels.length < 2)) {
      return null;
    }
    final asciiHost = [if (isTemplate) '*', ...asciiLabels].join('.');
    final portPart = port == null ? '' : ':$port';

    path = path.replaceFirst(_apiSuffix, '');
    final probeHost = isTemplate ? 'x${asciiHost.substring(1)}' : asciiHost;
    final probe = Uri.tryParse('https://$probeHost$portPart$path');
    if (probe == null || probe.host.isEmpty) return null;
    final normalizedPath = probe.path.replaceFirst(RegExp(r'/+$'), '');

    return ApiEndpoint._(
      'https://$asciiHost$portPart$normalizedPath',
      isTemplate: isTemplate,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ApiEndpoint && other.canonical == canonical;

  @override
  int get hashCode => canonical.hashCode;
}

/// Owner of [ApiConfig.baseUrl].
///
/// Sources, in priority order: Remote Config `encrypted_api_url` (persisted
/// gwenc1-encoded between launches), then the encoded default baked into
/// the build. A wildcard template gets a random per-device label.
///
/// Failover: a connection failure or a gateway-level error rotates the
/// wildcard label, or moves to the next address in the cycle
/// primary ↔ baked default ↔ optional reserve (`encrypted_api_fallback_url`),
/// and repeats the request once.
class ApiHostService {
  ApiHostService({Random? random}) : _random = random ?? Random.secure();

  static final ApiHostService instance = ApiHostService();

  // Values are stored gwenc1-encoded: no plain URL in shared_prefs.
  static const String _sourceKey = 'api_host_source_enc';
  static const String _reserveKey = 'api_host_reserve_enc';
  static const String _labelKey = 'api_host_label';

  static const String _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static const int _labelLength = 12;
  static final RegExp _labelPattern = RegExp(r'^[a-z][a-z0-9]{11}$');

  /// Template failures in a row before leaving the template for the next
  /// address (the whole parent domain may be blocked).
  static const int _maxTemplateRotations = 2;

  final Random _random;

  ApiEndpoint? _primary;
  ApiEndpoint? _reserve;
  String? _label;
  bool _hasRemoteSource = false;
  int _templateFailures = 0;

  /// True once a Remote Config value was applied on this device (now or in
  /// an earlier launch).
  bool get hasRemoteSource => _hasRemoteSource;

  ApiEndpoint? get _defaultEndpoint =>
      ApiEndpoint.tryParse(ApiConfig.defaultBaseUrl);

  /// Restores the last Remote Config address before the first request:
  /// Firebase may answer late or never (it gets blocked too).
  Future<void> restore() async {
    if (ApiConfig.hasDevOverride) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final label = prefs.getString(_labelKey);
      if (label != null && _labelPattern.hasMatch(label)) _label = label;
      _reserve = ApiEndpoint.tryParse(
        SecretCodec.tryDecode(prefs.getString(_reserveKey)),
      );
      final saved = SecretCodec.tryDecode(prefs.getString(_sourceKey));
      final endpoint = ApiEndpoint.tryParse(saved);
      if (endpoint != null) {
        _primary = endpoint;
        _hasRemoteSource = true;
        ApiConfig.baseUrl = _resolve(endpoint);
        return;
      }
    } catch (e) {
      _log('restore failed: ${e.runtimeType}');
    }
    _primary = null;
    final fallback = _defaultEndpoint;
    if (fallback != null) ApiConfig.baseUrl = _resolve(fallback);
  }

  /// Applies a decoded `encrypted_api_url` value (plain URL or wildcard
  /// template). Invalid values are ignored and return false.
  bool apply(String raw, {bool remember = true}) {
    if (ApiConfig.hasDevOverride) return false;
    final endpoint = ApiEndpoint.tryParse(raw);
    if (endpoint == null) return false;

    final unchanged = endpoint == _primary;
    _primary = endpoint;
    _hasRemoteSource = true;
    // A periodic re-fetch of the same value must not cancel an active
    // failover: the primary may still be blocked.
    if (!unchanged || !_isKnownBase(ApiConfig.baseUrl)) {
      _templateFailures = 0;
      ApiConfig.baseUrl = _resolve(endpoint);
    }
    if (remember) {
      unawaited(_store(_sourceKey, SecretCodec.encode(endpoint.canonical)));
    }
    return true;
  }

  /// Sets the optional reserve address; null or empty clears it.
  bool applyReserve(String? raw, {bool remember = true}) {
    if (ApiConfig.hasDevOverride) return false;
    final value = raw?.trim() ?? '';
    final endpoint = value.isEmpty ? null : ApiEndpoint.tryParse(value);
    if (value.isNotEmpty && endpoint == null) return false;
    _reserve = endpoint;
    if (remember) {
      unawaited(
        _store(
          _reserveKey,
          endpoint == null ? null : SecretCodec.encode(endpoint.canonical),
        ),
      );
    }
    return true;
  }

  /// Runs [send] against the current base URL with one failover retry.
  ///
  /// Pass `idempotent: false` for requests that must not be repeated
  /// blindly: they are retried only when the failure proves the request
  /// never reached a server (DNS, refused connection, TLS handshake).
  Future<http.Response> withFailover(
    Future<http.Response> Function(String baseUrl) send, {
    bool idempotent = true,
  }) async {
    final baseUrl = ApiConfig.baseUrl;
    final http.Response response;
    try {
      response = await send(baseUrl);
    } catch (error) {
      if (!isConnectionFailure(error)) rethrow;
      final switched = switchHost(baseUrl);
      if (!switched || (!idempotent && !neverReachedServer(error))) rethrow;
      return send(ApiConfig.baseUrl);
    }

    if (isGatewayFailure(response.statusCode)) {
      if (switchHost(baseUrl) && idempotent) return send(ApiConfig.baseUrl);
    } else {
      _templateFailures = 0;
    }
    return response;
  }

  /// Moves away from [failedBase]. False when there is nowhere to go.
  @visibleForTesting
  bool switchHost(String failedBase) {
    if (ApiConfig.hasDevOverride) return false;
    // Another request already switched while this one was failing.
    if (ApiConfig.baseUrl != failedBase) return true;

    final candidates = _candidates();
    if (candidates.isEmpty) return false;
    final index = candidates.indexWhere((e) => e.owns(failedBase));
    final current = index < 0 ? null : candidates[index];

    if (current != null &&
        current.isTemplate &&
        (_templateFailures < _maxTemplateRotations || candidates.length == 1)) {
      _templateFailures++;
      final label = _label = _newLabel();
      unawaited(_store(_labelKey, label));
      ApiConfig.baseUrl = current.build(label);
      _log('rotated wildcard label');
      return true;
    }

    final next = candidates[(index + 1) % candidates.length];
    if (next.owns(failedBase)) return false;
    _templateFailures = 0;
    ApiConfig.baseUrl = _resolve(next);
    _log('failover to candidate ${candidates.indexOf(next)}');
    return true;
  }

  /// Stable identity of the backend behind [baseUrl]: wildcard labels and
  /// trailing slashes do not change it. Used to scope local caches.
  String backendKey(String baseUrl) {
    final trimmed = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    for (final endpoint in _candidates()) {
      if (endpoint.owns(trimmed)) return endpoint.canonical;
    }
    return trimmed;
  }

  /// Connection-level errors: DNS, TCP, TLS, broken stream, timeout.
  static bool isConnectionFailure(Object error) =>
      error is SocketException ||
      error is TlsException ||
      error is HttpException ||
      error is TimeoutException ||
      error is http.ClientException;

  /// Failures that happen before any byte of the request is sent.
  static bool neverReachedServer(Object error) {
    if (error is TlsException) return true;
    if (error is! SocketException && error is! http.ClientException) {
      return false;
    }
    final message = error.toString().toLowerCase();
    return const <String>[
      'failed host lookup',
      'no address associated',
      'connection refused',
      'network is unreachable',
      'handshake',
    ].any(message.contains);
  }

  /// Statuses produced by proxies/CDN or blocking middleboxes rather than
  /// by the backend's business logic (404/400/500 stay with the caller).
  static bool isGatewayFailure(int status) =>
      status == 421 ||
      status == 451 ||
      status == 502 ||
      status == 503 ||
      status == 504 ||
      (status >= 520 && status <= 530);

  List<ApiEndpoint> _candidates() {
    final out = <ApiEndpoint>[];
    for (final endpoint in [_primary, _defaultEndpoint, _reserve]) {
      if (endpoint != null && !out.contains(endpoint)) out.add(endpoint);
    }
    return out;
  }

  bool _isKnownBase(String baseUrl) =>
      _candidates().any((e) => e.owns(baseUrl));

  String _resolve(ApiEndpoint endpoint) {
    if (!endpoint.isTemplate) return endpoint.canonical;
    var label = _label;
    if (label == null) {
      label = _label = _newLabel();
      unawaited(_store(_labelKey, label));
    }
    return endpoint.build(label);
  }

  // First character is a letter: some resolvers dislike leading digits.
  String _newLabel() => String.fromCharCodes([
    _alphabet.codeUnitAt(_random.nextInt(26)),
    for (var i = 1; i < _labelLength; i++)
      _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
  ]);

  Future<void> _store(String key, String? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value);
      }
    } catch (e) {
      _log('cannot persist $key: ${e.runtimeType}');
    }
  }

  @visibleForTesting
  void resetForTest() {
    _primary = null;
    _reserve = null;
    _label = null;
    _hasRemoteSource = false;
    _templateFailures = 0;
  }

  // Never log addresses, not even in debug builds.
  void _log(String message) {
    if (kDebugMode) debugPrint('ApiHostService: $message');
  }
}

/// RFC 3492 punycode for a single DNS label (`пример` → `xn--e1afmkfd`).
class Punycode {
  Punycode._();

  static const int _base = 36;
  static const int _tMin = 1;
  static const int _tMax = 26;
  static const int _skew = 38;
  static const int _damp = 700;

  /// ASCII labels pass through; others become `xn--…`; null if empty.
  static String? toAsciiLabel(String label) {
    if (label.isEmpty) return null;
    if (label.codeUnits.every((c) => c < 0x80)) return label;
    return 'xn--${encode(label)}';
  }

  static String encode(String input) {
    final codePoints = input.runes.toList();
    final output = StringBuffer();
    for (final cp in codePoints) {
      if (cp < 0x80) output.writeCharCode(cp);
    }
    final basicCount = output.length;
    var handled = basicCount;
    if (basicCount > 0) output.write('-');

    var n = 0x80;
    var delta = 0;
    var bias = 72;
    while (handled < codePoints.length) {
      var m = 0x10FFFF + 1;
      for (final cp in codePoints) {
        if (cp >= n && cp < m) m = cp;
      }
      delta += (m - n) * (handled + 1);
      n = m;
      for (final cp in codePoints) {
        if (cp < n) delta++;
        if (cp != n) continue;
        var q = delta;
        for (var k = _base; ; k += _base) {
          final t = k <= bias ? _tMin : (k >= bias + _tMax ? _tMax : k - bias);
          if (q < t) break;
          output.writeCharCode(_digit(t + (q - t) % (_base - t)));
          q = (q - t) ~/ (_base - t);
        }
        output.writeCharCode(_digit(q));
        bias = _adapt(delta, handled + 1, handled == basicCount);
        delta = 0;
        handled++;
      }
      delta++;
      n++;
    }
    return output.toString();
  }

  static int _digit(int d) => d < 26 ? 0x61 + d : 0x30 + d - 26;

  static int _adapt(int delta, int numPoints, bool firstTime) {
    var d = firstTime ? delta ~/ _damp : delta ~/ 2;
    d += d ~/ numPoints;
    var k = 0;
    while (d > ((_base - _tMin) * _tMax) ~/ 2) {
      d ~/= _base - _tMin;
      k += _base;
    }
    return k + ((_base - _tMin + 1) * d) ~/ (d + _skew);
  }
}
