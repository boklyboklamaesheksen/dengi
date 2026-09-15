import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import '../config/api_config.dart';
import '../config/backend_signing.dart';
import 'gw_identity.dart';
import '../models/server_config_model.dart';

/// Client for the GW (SSH-tunnel) server catalogue.
///
/// Contract is 1:1 with the production GW backend
/// (`POST /vpn/api/v1/user/server_vlee`): hash/time/bundleId signature,
/// device pubkey, per-server encrypted envelopes, ECDH secp256k1 +
/// AES-256-GCM decryption. A node that fails to decrypt on this device
/// is dropped (same as in the GW client).
class GwApiService {
  static String get _signSecret => BackendSigning.secret;
  static const String _bundleId = 'app.rabochiy.vpn';

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
        userId.isEmpty) {
      return [];
    }

    try {
      final identity = GwIdentity.fromMnemonic(mnemonic);
      final timeSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final hash =
          sha256.convert(utf8.encode('$timeSeconds|$_signSecret')).toString();

      // Body is key=value&... WITHOUT URL-encoding — matches the GW client
      // and the server parser (values are hex/UUID/numbers).
      final body = 'userId=$userId'
          '&v=2'
          '&pubkey=${identity.publicKeyXyHex}'
          '&hash=$hash'
          '&time=$timeSeconds'
          '&bundleId=$_bundleId';

      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/vpn/api/v1/user/server_vlee'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('GW servers HTTP ${response.statusCode}');
      }

      final Map<String, dynamic> decoded = jsonDecode(response.body);
      if (decoded['success'] != 1) {
        return [];
      }

      final List<dynamic> data =
          (decoded['data'] as List<dynamic>?) ?? const [];
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
    } catch (_) {
      return [];
    }
  }
}
