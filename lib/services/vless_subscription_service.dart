import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../config/secret_codec.dart';
import '../models/server_config_model.dart';
import 'vless_catalogue_client.dart';

/// VLESS subscription URLs. Only gwenc1-encoded values are accepted (the
/// same policy as `encrypted_api_url`): plain `https://…` strings never live
/// in the APK or the Remote Config JSON.
class VlessSubscriptionSources {
  VlessSubscriptionSources._();
  static final VlessSubscriptionSources instance = VlessSubscriptionSources._();

  final ValueNotifier<List<String>> urls = ValueNotifier<List<String>>(
    parse(ApiConfig.defaultVlessSubscriptionsEncrypted),
  );

  static const String _prefsKey = 'vless_subscription_sources_enc';
  static final RegExp _separators = RegExp(r'[\s,;]+');

  /// Restores the last Remote Config subscription sources before first fetch.
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved == null) return;
      apply(saved, remember: false);
    } catch (_) {}
  }

  /// Applies a Remote Config value. An empty value disables VLESS
  /// subscriptions; a non-empty value without a single valid URL is
  /// rejected (returns false) and the current list stays.
  bool apply(String raw, {bool remember = true}) {
    final trimmed = raw.trim();
    final next = parse(trimmed);
    if (trimmed.isNotEmpty && next.isEmpty) return false;
    if (!listEquals(next, urls.value)) urls.value = next;
    if (remember) {
      unawaited(_store(trimmed));
    }
    return true;
  }

  Future<void> _store(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, value);
    } catch (_) {}
  }

  /// Decodes every gwenc1 token; a decoded token may itself hold several
  /// URLs. Plain-text tokens are ignored. Only https URLs survive.
  static List<String> parse(String raw) {
    final out = <String>[];
    for (final token in raw.split(_separators)) {
      if (!SecretCodec.isEncoded(token)) continue;
      final decoded = SecretCodec.tryDecode(token);
      if (decoded == null) continue;
      for (final candidate in decoded.split(_separators)) {
        final uri = Uri.tryParse(candidate.trim());
        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
        final url = uri.toString();
        if (!out.contains(url)) out.add(url);
      }
    }
    return out;
  }
}

/// Raised when no subscription could be fetched and nothing is cached.
class VlessSubscriptionException implements Exception {
  const VlessSubscriptionException();
  @override
  String toString() => 'VlessSubscriptionException';
}

/// Downloads VLESS subscriptions and turns them into [ServerConfig]s.
///
/// Our own subscription (`…/bs`) is public and lists free servers only.
/// While it is configured, the service reads the same servers from the
/// API catalogue instead, which also lists PRO servers ([catalogue]); the
/// public list remains the fallback when the API cannot be reached.
class VlessSubscriptionService {
  VlessSubscriptionService({
    http.Client? client,
    VlessSubscriptionSources? sources,
    VlessCatalogueClient? catalogue,
    this.timeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _sources = sources ?? VlessSubscriptionSources.instance,
       // A test that injects its HTTP client opts out of the real backend.
       _catalogue =
           catalogue ?? (client == null ? VlessCatalogueClient() : null),
       _ownsCatalogue = catalogue == null && client == null;

  static const String _cacheKey = 'vless_subscription_cache_v1';
  static const String _catalogueCacheKey = 'vless_catalogue_cache_v1';
  static const int _maxBodyBytes = 2 * 1024 * 1024;
  static const int _maxServers = 500;

  final http.Client _client;
  final bool _ownsClient;
  final VlessSubscriptionSources _sources;
  final VlessCatalogueClient? _catalogue;
  final bool _ownsCatalogue;

  /// Our public free-only subscription, superseded by the API catalogue.
  static bool isOwnSubscription(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    return path == '/bs' || path == '/bs/';
  }

  /// Per-download limit.
  final Duration timeout;

  VlessSubscriptionSources get sources => _sources;

  /// Reads the last cached VLESS servers for the current sources without network I/O.
  Future<List<ServerConfig>> readCachedServers() async {
    final urls = List<String>.from(_sources.urls.value);
    if (urls.isEmpty) return const <ServerConfig>[];
    final catalogue = await _readCatalogueCache(urls);
    final cached = await _readCache(urls);
    return merge(
      catalogue ?? const <ServerConfig>[],
      toServers(cached ?? const []),
    );
  }

  /// Servers in subscription order. Falls back to the last good result when
  /// every source fails (blocked network, server down).
  Future<List<ServerConfig>> fetchServers() async {
    final urls = List<String>.from(_sources.urls.value);
    if (urls.isEmpty) return const <ServerConfig>[];

    final catalogue = urls.any(isOwnSubscription)
        ? await _fetchCatalogue(urls)
        : null;
    // With the catalogue in hand our public list would only repeat it.
    final downloads = catalogue == null
        ? urls
        : urls.where((url) => !isOwnSubscription(url)).toList();

    final bodies = await Future.wait(downloads.map(_download));
    final fetched = bodies.whereType<String>().toList();
    if (downloads.isNotEmpty && fetched.isEmpty) {
      final cached = await _readCache(urls);
      if (catalogue != null) {
        return merge(catalogue, toServers(cached ?? const []));
      }
      final cachedCatalogue = await _readCatalogueCache(urls);
      if (cached == null && cachedCatalogue == null) {
        throw const VlessSubscriptionException();
      }
      return merge(
        cachedCatalogue ?? const <ServerConfig>[],
        toServers(cached ?? const []),
      );
    }

    final links = <String>[];
    for (final body in fetched) {
      links.addAll(extractLinks(body));
    }
    final servers = toServers(links);
    if (servers.isNotEmpty) {
      await _writeCache(urls, servers.map((s) => s.originalUrl).toList());
    }
    return catalogue == null ? servers : merge(catalogue, servers);
  }

  /// Catalogue entries first (they carry the PRO flags), then other
  /// subscriptions; duplicates keep their first occurrence.
  static List<ServerConfig> merge(
    List<ServerConfig> first,
    List<ServerConfig> second,
  ) {
    final out = <ServerConfig>[];
    final seen = <String>{};
    for (final server in <ServerConfig>[...first, ...second]) {
      if (!seen.add(server.id)) continue;
      out.add(server);
      if (out.length >= _maxServers) break;
    }
    return out;
  }

  /// Null when the API cannot answer: the caller falls back to `/bs`.
  Future<List<ServerConfig>?> _fetchCatalogue(List<String> urls) async {
    final client = _catalogue;
    if (client == null) return null;
    try {
      final userId = await client.currentUserId();
      final raw = await client.fetchRaw(userId);
      final servers = VlessCatalogueClient.parse(raw);
      if (raw.isNotEmpty && servers.isEmpty) return null;
      await _writeCatalogueCache(urls, userId, raw);
      return servers;
    } catch (_) {
      return null;
    }
  }

  Future<List<ServerConfig>?> _readCatalogueCache(List<String> urls) async {
    final client = _catalogue;
    if (client == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_catalogueCacheKey);
      if (raw == null) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['sources'] != _sourcesKey(urls) ||
          data['user'] != _userKey(await client.currentUserId())) {
        return null;
      }
      return VlessCatalogueClient.parse(data['servers'] as List<dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCatalogueCache(
    List<String> urls,
    String userId,
    List<dynamic> servers,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _catalogueCacheKey,
        jsonEncode(<String, dynamic>{
          'sources': _sourcesKey(urls),
          'user': _userKey(userId),
          'servers': servers,
        }),
      );
    } catch (_) {
      // Cache is best-effort.
    }
  }

  static String _userKey(String userId) => SecretCodec.encode('u:$userId');

  Future<String?> _download(String url) async {
    try {
      final response = await _client
          .get(
            Uri.parse(url),
            headers: const <String, String>{
              // Panels pick the share-link format from the User-Agent.
              'User-Agent': 'ZapretVPN v2rayNG/1.10',
              'Accept': 'text/plain, */*',
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      if (response.bodyBytes.length > _maxBodyBytes) return null;
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  /// Returns the `vless://` lines of a subscription body, plain or base64.
  static List<String> extractLinks(String body) {
    var text = body.trim();
    if (!text.contains('://')) {
      text = _tryBase64(text) ?? '';
    }
    return text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.toLowerCase().startsWith('vless://'))
        .toList();
  }

  /// Parses links, dropping malformed ones and duplicates (same link body).
  static List<ServerConfig> toServers(Iterable<String> links) {
    final out = <ServerConfig>[];
    final seen = <String>{};
    for (final link in links) {
      final server = ServerConfig.fromVlessUri(link);
      if (server == null || !seen.add(server.id)) continue;
      out.add(server);
      if (out.length >= _maxServers) break;
    }
    return out;
  }

  static String? _tryBase64(String text) {
    try {
      final compact = text.replaceAll(RegExp(r'\s+'), '');
      final normalized = base64.normalize(
        compact.replaceAll('-', '+').replaceAll('_', '/'),
      );
      return utf8.decode(base64.decode(normalized), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  Future<List<String>?> _readCache(List<String> urls) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['sources'] != _sourcesKey(urls)) return null;
      return (data['links'] as List<dynamic>).cast<String>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(List<String> urls, List<String> links) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(<String, dynamic>{
          'sources': _sourcesKey(urls),
          'links': links,
        }),
      );
    } catch (_) {
      // Cache is best-effort.
    }
  }

  // Cache is bound to the source set without storing the URLs in clear.
  static String _sourcesKey(List<String> urls) =>
      SecretCodec.encode(urls.join('\n'));

  void close() {
    if (_ownsClient) _client.close();
    if (_ownsCatalogue) _catalogue?.close();
  }
}
