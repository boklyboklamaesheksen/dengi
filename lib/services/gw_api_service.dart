import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../config/backend_signing.dart';
import '../models/server_config_model.dart';
import 'api_host_service.dart';
import 'api_service.dart';
import 'gw_identity.dart';

/// Client for the GW (SSH-tunnel) server catalogue.
///
/// Contract is 1:1 with the production GW backend
/// (`POST /vpn/api/v1/user/server_vlee`): hash/time/bundleId signature,
/// device pubkey, per-server encrypted envelopes, ECDH secp256k1 +
/// AES-256-GCM decryption. A node that fails to decrypt on this device
/// is dropped (same as in the GW client).
class GwApiService {
  GwApiService({
    http.Client? client,
    this._signing = const BackendSigning(),
    this._baseUrl,
    this._timeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final BackendSigning _signing;
  final String? _baseUrl;
  final Duration _timeout;

  void close() => _client.close();

  String _backendFingerprint() {
    final override = _baseUrl;
    final key = override != null
        ? override.replaceAll(RegExp(r'/+$'), '')
        : ApiHostService.instance.backendKey(ApiConfig.baseUrl);
    return sha256.convert(utf8.encode(key)).toString();
  }

  /// Reads cached GW envelopes for the active account/backend and decrypts them locally.
  Future<List<ServerConfig>> readCachedServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mnemonic = prefs.getString(ApiService.mnemonicPrefsKey);
      final userId = prefs.getString(ApiService.userIdPrefsKey);
      if (mnemonic == null ||
          mnemonic.isEmpty ||
          userId == null ||
          userId.isEmpty ||
          userId == 'pending') {
        return const [];
      }
      final identity = GwIdentity.fromMnemonic(mnemonic);
      return _readCache(prefs, userId, _backendFingerprint(), identity);
    } catch (_) {
      return const [];
    }
  }

  /// Fetches and decrypts the GW nodes for the current user. Returns an
  /// empty list when the user/mnemonic is unavailable or the backend has
  /// no GW fleet yet — this is not an error for the overall server list.
  Future<List<ServerConfig>> fetchServers() async {
    final prefs = await SharedPreferences.getInstance();
    final mnemonic = prefs.getString(ApiService.mnemonicPrefsKey);
    final userId = prefs.getString(ApiService.userIdPrefsKey);
    if (mnemonic == null ||
        mnemonic.isEmpty ||
        userId == null ||
        userId.isEmpty ||
        userId == 'pending') {
      return [];
    }

    final identity = GwIdentity.fromMnemonic(mnemonic);
    final backend = _backendFingerprint();
    final body = _signing.sign({
      'userId': userId,
      'v': '2',
      'pubkey': identity.publicKeyXyHex,
    });

    Future<http.Response> send(String base) => _client
        .post(
          Uri.parse(
            '${base.replaceAll(RegExp(r'/+$'), '')}/vpn/api/v1/user/server_vlee',
          ),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: body,
        )
        .timeout(_timeout);

    try {
      final override = _baseUrl;
      final response = override != null
          ? await send(override)
          : await ApiHostService.instance.withFailover(send);

      if (response.statusCode != 200) {
        throw Exception('GW servers HTTP ${response.statusCode}');
      }

      final Map<String, dynamic> decoded = jsonDecode(response.body);
      if ((decoded['success'] != 1 && decoded['success'] != true) ||
          decoded['data'] is! List) {
        throw const FormatException('Invalid GW catalogue response');
      }

      final List<dynamic> data = (decoded['data'] as List<dynamic>?) ?? const [];
      final servers = _decryptList(data, identity);
      if (data.isNotEmpty && servers.isEmpty) {
        throw const FormatException('Invalid GW server envelopes');
      }
      if (prefs.getString(ApiService.userIdPrefsKey) == userId) {
        try {
          await prefs.setString(
            ApiService.gwCachePrefsKey,
            jsonEncode({'userId': userId, 'backend': backend, 'data': data}),
          );
        } catch (_) {}
      }
      return servers;
    } on BackendConfigurationException {
      rethrow;
    } catch (_) {
      final cached = _readCache(prefs, userId, backend, identity);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  List<ServerConfig> _decryptList(List<dynamic> data, GwIdentity identity) {
    final servers = <ServerConfig>[];
    for (final entry in data) {
      if (entry is! Map<String, dynamic>) continue;
      final meta =
          (entry['meta'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
      final enc = entry['enc'] as Map<String, dynamic>?;
      if (enc == null) continue;
      try {
        final plain = identity.decryptEnvelope(
          ephHex: enc['eph'] as String,
          ctBase64: enc['ct'] as String,
          ivBase64: enc['iv'] as String,
        );
        final config = jsonDecode(plain) as Map<String, dynamic>;
        servers.add(ServerConfig.fromGw(meta: meta, config: config));
      } catch (_) {
        // A node that cannot be decrypted on this device is useless — drop.
      }
    }
    return servers;
  }

  List<ServerConfig> _readCache(
    SharedPreferences prefs,
    String userId,
    String backend,
    GwIdentity identity,
  ) {
    try {
      final raw = prefs.getString(ApiService.gwCachePrefsKey);
      if (raw == null || raw.isEmpty) return const [];
      final body = jsonDecode(raw) as Map<String, dynamic>;
      if (body['userId'] != userId || body['backend'] != backend) {
        return const [];
      }
      final list = body['data'];
      if (list is List) {
        return _decryptList(list, identity);
      }
    } catch (_) {}
    return const [];
  }
}
