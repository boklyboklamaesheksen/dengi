import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_config_model.dart';

/// Rabochiy VPN backend client.
///
/// Talks to the FastAPI service hosted on `https://rabochiy.yarik.app`. The
/// backend exposes two flavours of routes that we mix-and-match:
///
///   * **`/vpn/api/v3/client/*`** — JSON-based, mnemonic accounts.
///     Used for: user create / login / get, IKEv2 server catalogue,
///     tariff list, payment URL.
///   * **`/vpn/api/v1/user/*`**   — legacy form-encoded, signed POST.
///     Used for: AmneziaWG server catalogue, connection heartbeat,
///     per-server load percentages.
///
/// Every `/vpn/api/v1/user/*` POST is signed with `hash`, `time`,
/// `bundleId` form fields. The shared secret and bundle whitelist are
/// fixed by the backend middleware — see [_signatureSecret] /
/// [_signatureBundleId] for the exact values that the server checks.
class ApiService {
  /// Base URL of the production backend. Override at build time with
  /// `flutter run --dart-define=RABOCHIY_API_BASE=http://10.0.2.2:3002`
  /// when pointing at a local FastAPI instance.
  static const String defaultBaseUrl = String.fromEnvironment(
    'RABOCHIY_API_BASE',
    defaultValue: 'https://rabochiy.yarik.app',
  );

  /// BundleId expected by the backend's request-signature middleware.
  /// The server-side whitelist is fixed, so we always send this exact
  /// value regardless of the actual Android `applicationId`.
  static const String _signatureBundleId = 'app.rabochiy.vpn';

  /// Shared secret baked into the backend signature middleware.
  /// Required for the SHA-256 hash. Compromise of this string only
  /// allows forging request timestamps; it does not unlock any user
  /// data on its own.
  static const String _signatureSecret = 'strongVPN!@#';

  static const userIdPrefsKey = 'rabochiy_user_id';
  static const mnemonicPrefsKey = 'rabochiy_mnemonic';
  static const mnemonicConfirmedPrefsKey = 'rabochiy_mnemonic_confirmed';

  static const _kAwgCacheKey = 'rabochiy_servers_cache_awg_v1';
  static const _kUserIdKey = userIdPrefsKey;
  static const _kMnemonicKey = mnemonicPrefsKey;
  static const _kMnemonicConfirmedKey = mnemonicConfirmedPrefsKey;
  static const _kIsPremiumKey = 'rabochiy_is_premium';
  static const _kPremiumEndKey = 'rabochiy_premium_end_ms';

  /// Outcome codes for [login]. The UI maps them to localised strings.
  static const loginInvalidMnemonic = 'invalid_mnemonic';
  static const loginNetworkError = 'network_error';
  static const loginServerError = 'server_error';

  final String baseUrl;
  final http.Client _client;
  final Duration _timeout;

  ApiService({String? baseUrl, http.Client? client, Duration? timeout})
    : baseUrl = (baseUrl ?? defaultBaseUrl).replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 15);

  // ──────────────────────────────────────────────────────────────────
  //  Servers catalogue
  // ──────────────────────────────────────────────────────────────────

  /// Loads the live server catalogue from both protocols (IKEv2 via v3
  /// client API, AmneziaWG via v1 user API) and merges them into a
  /// single sorted list. On any network failure we transparently fall
  /// back to the cached snapshot so the UI is never empty on cold
  /// start.
  Future<List<ServerConfig>> fetchServerConfigs() async {
    final userId = await _ensureUserId();
    if (userId == 'pending') {
      // Backend not reachable on first launch. Show whatever we cached
      // last time, if anything.
      final cached = await _readMergedCache();
      return cached;
    }

    Object? lastError;

    final awg = await _fetchAwgServers(userId).catchError((Object e) {
      lastError = e;
      return <ServerConfig>[];
    });

    if (awg.isEmpty) {
      // The endpoint failed — surface cached snapshot if present.
      final cached = await _readMergedCache();
      if (cached.isNotEmpty) return cached;
      if (lastError != null) {
        throw lastError!;
      }
      return const [];
    }

    final merged = <ServerConfig>[...awg];
    merged.sort((a, b) => b.priority.compareTo(a.priority));
    return merged;
  }

  Future<List<ServerConfig>> _fetchAwgServers(String userId) async {
    final res = await _signedPost(
      '/vpn/api/v1/user/server_awg',
      <String, String>{'userId': userId},
    );
    if (res.statusCode != 200) {
      throw Exception('server_awg returned HTTP ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['data'];
    if (raw is! List) {
      await _writeCache(_kAwgCacheKey, res.body);
      return const [];
    }
    await _writeCache(_kAwgCacheKey, res.body);
    return _parseList(raw, defaultProtocol: 'awg');
  }

  // ──────────────────────────────────────────────────────────────────
  //  User session
  // ──────────────────────────────────────────────────────────────────

  /// Returns the cached `user_id`. When missing, registers a new user
  /// against the backend and persists `user_id` + `mnemonic` locally
  /// in `SharedPreferences`.
  Future<String> _ensureUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kUserIdKey);
    if (cached != null && cached.isNotEmpty && cached != 'pending') {
      return cached;
    }

    final created = await _createUser();
    if (created != null &&
        created.userId.isNotEmpty &&
        created.userId != 'pending') {
      await _persistSession(created, mnemonicConfirmed: false);
      return created.userId;
    }

    // Backend unavailable on first launch. Cache 'pending' so we don't
    // hammer the API with registration attempts on every request.
    await prefs.setString(_kUserIdKey, 'pending');
    return 'pending';
  }

  Future<UserSession?> _createUser() async {
    try {
      final uri = _buildUri('/vpn/api/v3/client/user/create', const {});
      final res = await _client.post(uri).timeout(_timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>?;
        if (data == null) return null;
        // The backend returns the mnemonic in a custom response header
        // because the body never echoes it back (security policy of
        // the create endpoint).
        final mnemonic = res.headers['mnemonic'] ?? '';
        final userId = (data['user_id'] ?? '').toString();
        // Persist premium flag if the freshly-created user already has
        // it (rare but possible if a code activation followed quickly).
        if (data['is_premium'] is bool) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_kIsPremiumKey, data['is_premium'] as bool);
          final endMs = _parseEpochMs(data['premium_end']);
          if (endMs != null) {
            await prefs.setInt(_kPremiumEndKey, endMs);
          }
        }
        return UserSession(userId: userId, mnemonic: mnemonic);
      }
    } catch (_) {
      // Swallow — caller decides whether to retry.
    }
    return null;
  }

  Future<void> _persistSession(
    UserSession session, {
    required bool mnemonicConfirmed,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserIdKey, session.userId);
    if (session.mnemonic.isNotEmpty) {
      await prefs.setString(_kMnemonicKey, session.mnemonic);
    }
    await prefs.setBool(_kMnemonicConfirmedKey, mnemonicConfirmed);
    await prefs.remove(_kAwgCacheKey);
  }

  /// Creates a new user via API, persists the credentials locally, and
  /// marks the recovery phrase as not yet confirmed by the user.
  /// Public — called by the splash screen before entering the app.
  Future<UserSession?> createUser() async {
    final created = await _createUser();
    if (created != null &&
        created.userId.isNotEmpty &&
        created.userId != 'pending') {
      await _persistSession(created, mnemonicConfirmed: false);
    }
    return created;
  }

  /// Records that the user explicitly confirmed saving the freshly
  /// created recovery phrase.
  Future<void> confirmMnemonicSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMnemonicConfirmedKey, true);
  }

  /// Public wrapper for screens that want to surface the current user
  /// id (e.g. for the QR / mnemonic screen).
  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserIdKey);
  }

  /// Public wrapper for the mnemonic — purely a local lookup, the
  /// backend never returns it again after `create`.
  Future<String?> getMnemonic() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kMnemonicKey);
  }

  /// Reads the cached premium flag persisted alongside the user_id.
  /// Returns `false` when missing so the UI defaults to "free".
  Future<bool> getIsPremium() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kIsPremiumKey) ?? false;
  }

  /// Returns the unix epoch (ms) at which the current premium plan
  /// expires, or `null` when the user has no plan.
  Future<int?> getPremiumEndMillis() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_kPremiumEndKey);
    if (stored == null || stored <= 0) return null;
    return stored;
  }

  /// Refreshes premium / traffic state by calling
  /// `/vpn/api/v3/client/user/get?user_id=...`. Updates the local
  /// `isPremium` and `premium_end` caches in place. Used by Account /
  /// Premium screens to keep the badge in sync with the backend.
  Future<UserState?> refreshUserState() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_kUserIdKey);
    if (userId == null || userId.isEmpty || userId == 'pending') return null;
    try {
      final uri = _buildUri('/vpn/api/v3/client/user/get', {'user_id': userId});
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = body['data'];
      if (data is! Map<String, dynamic>) return null;
      final isPremium = data['is_premium'] == true;
      final premiumEndMs = _parseEpochMs(data['premium_end']);
      await prefs.setBool(_kIsPremiumKey, isPremium);
      if (premiumEndMs != null) {
        await prefs.setInt(_kPremiumEndKey, premiumEndMs);
      } else {
        await prefs.remove(_kPremiumEndKey);
      }
      return UserState(
        userId: userId,
        isPremium: isPremium,
        premiumEndMs: premiumEndMs,
        totalDownload: _toInt(data['total_download']),
        totalUpload: _toInt(data['total_upload']),
      );
    } catch (_) {
      return null;
    }
  }

  /// Restores an existing account by replaying the BIP-39 mnemonic
  /// against the backend. On success the local `user_id` + `mnemonic`
  /// cache is overwritten and the new session is returned to the
  /// caller; on failure a typed [LoginResult.error] wraps the reason
  /// so the UI can show a precise message.
  Future<LoginResult> login(String mnemonic) async {
    final cleaned = mnemonic.trim();
    if (cleaned.isEmpty) {
      return LoginResult.error(loginInvalidMnemonic);
    }

    try {
      final uri = _buildUri('/vpn/api/v3/client/user/login', {
        'mnemonic': cleaned,
      });
      final res = await _client.get(uri).timeout(_timeout);
      Map<String, dynamic>? body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>?;
      } catch (_) {
        body = null;
      }

      if (res.statusCode == 200 && body?['data'] is Map<String, dynamic>) {
        final data = body!['data'] as Map<String, dynamic>;
        final userId = (data['user_id'] ?? '').toString();
        final isPremium = data['is_premium'] == true;
        final premiumEndMs = _parseEpochMs(data['premium_end']);
        if (userId.isEmpty) {
          return LoginResult.error(loginServerError);
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kUserIdKey, userId);
        await prefs.setString(_kMnemonicKey, cleaned);
        await prefs.setBool(_kMnemonicConfirmedKey, true);
        await prefs.setBool(_kIsPremiumKey, isPremium);
        if (premiumEndMs != null) {
          await prefs.setInt(_kPremiumEndKey, premiumEndMs);
        } else {
          await prefs.remove(_kPremiumEndKey);
        }
        // Force a fresh server-list fetch on next start so the new
        // account sees its own catalogue (premium gate, regional pool).
            await prefs.remove(_kAwgCacheKey);

        return LoginResult.success(
          userId: userId,
          mnemonic: cleaned,
          isPremium: isPremium,
          premiumEndMs: premiumEndMs,
        );
      }

      if (res.statusCode == 404 || res.statusCode == 400) {
        return LoginResult.error(loginInvalidMnemonic);
      }
      return LoginResult.error(loginServerError);
    } on TimeoutException {
      return LoginResult.error(loginNetworkError);
    } catch (_) {
      return LoginResult.error(loginNetworkError);
    }
  }

  /// Wipes the locally cached user identity / mnemonic / premium flags.
  /// Used by the "Log out" affordance on the Account screen. The
  /// backend keeps the user record (it's keyed by mnemonic, not
  /// device), so the same mnemonic restores the session intact.
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserIdKey);
    await prefs.remove(_kMnemonicKey);
    await prefs.remove(_kMnemonicConfirmedKey);
    await prefs.remove(_kIsPremiumKey);
    await prefs.remove(_kPremiumEndKey);
    await prefs.remove(_kAwgCacheKey);
  }

  /// Outcome codes for [deleteAccount].
  static const deleteAccountNotFound = 'not_found';
  static const deleteAccountNetwork = 'network';
  static const deleteAccountServer = 'server';

  /// Permanently deletes the current user account on the backend and
  /// then wipes local credentials (so the app drops to the welcome /
  /// login flow on the next frame).
  ///
  /// Returns `null` on success, or a typed error code from the
  /// `deleteAccount*` constants.
  Future<String?> deleteAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_kUserIdKey);
    if (userId == null || userId.isEmpty || userId == 'pending') {
      // Nothing on the server to delete — just clear local state.
      await logout();
      return null;
    }
    try {
      final uri = _buildUri('/vpn/api/v3/client/user/delete', <String, String>{
        'user_id': userId,
      });
      final res = await _client.delete(uri).timeout(_timeout);
      if (res.statusCode == 200) {
        await logout();
        return null;
      }
      if (res.statusCode == 404) {
        // The account is already gone server-side — still wipe locally.
        await logout();
        return deleteAccountNotFound;
      }
      return deleteAccountServer;
    } on TimeoutException {
      return deleteAccountNetwork;
    } catch (_) {
      return deleteAccountNetwork;
    }
  }

  // ──────────────────────────────────────────────────────────────────
  //  Premium tariffs / payments
  // ──────────────────────────────────────────────────────────────────

  /// Loads the active tariff list from `/vpn/api/v3/client/tariff/get`.
  /// Returns an empty list on any failure so the UI can show a "no
  /// tariffs" state instead of breaking.
  Future<List<TariffInfo>> fetchTariffs() async {
    try {
      final uri = _buildUri('/vpn/api/v3/client/tariff/get', const {});
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = body['data'];
      if (data is! List) return const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map<TariffInfo?>((m) {
            try {
              return TariffInfo.fromJson(m);
            } catch (_) {
              return null;
            }
          })
          .whereType<TariffInfo>()
          .where((t) => t.enabled)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Outcome codes for [activateCode]. The UI maps them to localised
  /// strings.
  static const codeActivateInvalid = 'invalid';
  static const codeActivateUsed = 'used';
  static const codeActivateNetwork = 'network';
  static const codeActivateServer = 'server';

  /// Activates a premium subscription code via
  /// `PUT /vpn/api/v3/client/user/activatecode`.
  ///
  /// Returns `null` on success (the local premium flag will be updated
  /// on the next [refreshUserState] call) or one of the typed
  /// `codeActivate*` constants on failure.
  Future<String?> activateCode(String code) async {
    final cleaned = code.trim();
    if (cleaned.isEmpty) return codeActivateInvalid;
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_kUserIdKey);
    if (userId == null || userId.isEmpty || userId == 'pending') {
      return codeActivateServer;
    }
    try {
      final uri = _buildUri(
        '/vpn/api/v3/client/user/activatecode',
        <String, String>{'user_id': userId, 'code': cleaned},
      );
      final res = await _client.put(uri).timeout(_timeout);
      if (res.statusCode == 200) {
        // Refresh local premium state so the UI reflects the change
        // without an extra round-trip from the caller.
        await refreshUserState();
        return null;
      }
      if (res.statusCode == 404) return codeActivateInvalid;
      if (res.statusCode == 400) return codeActivateUsed;
      return codeActivateServer;
    } on TimeoutException {
      return codeActivateNetwork;
    } catch (_) {
      return codeActivateNetwork;
    }
  }

  /// Creates a payment (WATA / SBP form) for the given tariff.
  /// Returns `{paymentId, status, payUrl, amount, currency}` or `null`.
  Future<PaymentInitiation?> initiatePayment({
    required String tariffTechnicalName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_kUserIdKey);
    if (userId == null || userId.isEmpty || userId == 'pending') return null;
    try {
      final uri = _buildUri(
        '/vpn/api/v3/client/payments/initiate',
        const {},
      );
      final res = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId, 'tariff_id': tariffTechnicalName}),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] != true) return null;
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      return PaymentInitiation(
        paymentId: (data['payment_id'] ?? '').toString(),
        status: (data['status'] ?? 'pending').toString(),
        payUrl: (data['pay_url'] ?? '').toString(),
        amount: (data['amount'] ?? 0).toDouble(),
        currency: (data['currency'] ?? 'RUB').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Polls a payment status. Returns `null` on transport/server failure;
  /// a found payment yields `status` = pending / paid / failed plus the
  /// user's current premium flag.
  Future<PaymentStatusResult?> checkPaymentStatus(String paymentId) async {
    try {
      final uri = _buildUri('/vpn/api/v3/client/payments/check', {
        'payment_id': paymentId,
      });
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] != true) return null;
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return null;
      return PaymentStatusResult(
        paymentId: (data['payment_id'] ?? paymentId).toString(),
        status: (data['status'] ?? 'pending').toString(),
        isPremium: data['is_premium'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────
  //  Connection heartbeat (admin online count + per-server load)
  // ──────────────────────────────────────────────────────────────────

  /// Pushes the user's current connection state to the backend so the
  /// admin panel and the per-server load endpoint can see them online.
  ///
  /// The wire shape matches the legacy `/vpn/api/v1/user/connection/update`
  /// route — form-encoded fields with the standard signature triplet.
  ///
  /// Call sites:
  ///   * `connect`    — fire once when the tunnel comes up.
  ///   * `heartbeat`  — fire every ~30 s while the tunnel is up so we
  ///     stay inside the 2-minute "online" window the API uses.
  ///   * `disconnect` — fire once when the tunnel comes down.
  Future<void> reportConnection({
    required String userId,
    String? serverIp,
    String action = 'connect',
    String protocol = 'awg',
  }) async {
    if (userId.isEmpty || userId == 'pending') return;
    if ((action == 'connect' || action == 'heartbeat') &&
        (serverIp == null || serverIp.isEmpty)) {
      return; // Backend rejects connect/heartbeat without a server.
    }
    try {
      await _signedPost('/vpn/api/v1/user/connection/update', <String, String>{
        'userId': userId,
        'action': action,
        'protocol': protocol,
        if (serverIp != null && serverIp.isNotEmpty) 'serverIp': serverIp,
      });
    } catch (_) {
      // Heartbeats are best-effort — losing one doesn't matter.
    }
  }

  // ──────────────────────────────────────────────────────────────────
  //  Server load (per-server online ratio)
  // ──────────────────────────────────────────────────────────────────

  /// Asks the backend for the live load percentage of every active
  /// server. Returns a map keyed by IP address with values clamped to
  /// `0..100`. On failure we return an empty map so the UI gracefully
  /// falls back to "no load data" instead of breaking.
  Future<Map<String, int>> fetchServerLoads() async {
    try {
      // The backend ignores any payload but the signature middleware
      // still requires the standard hash/time/bundleId triplet.
      final res = await _signedPost(
        '/vpn/api/v1/user/servers/load',
        const <String, String>{},
      );
      if (res.statusCode != 200) return const {};
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = body['data'];
      if (data is! Map) return const {};
      return data.map((key, value) {
        final intValue = value is int
            ? value
            : value is num
            ? value.toInt()
            : int.tryParse(value.toString()) ?? 0;
        return MapEntry(key.toString(), intValue.clamp(0, 100));
      });
    } catch (_) {
      return const {};
    }
  }

  // ──────────────────────────────────────────────────────────────────
  //  Internals
  // ──────────────────────────────────────────────────────────────────

  Uri _buildUri(String path, Map<String, String> qs) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse(
      '$baseUrl$cleanPath',
    ).replace(queryParameters: qs.isEmpty ? null : qs);
  }

  /// Performs a signed `application/x-www-form-urlencoded` POST against
  /// the legacy v1 routes. Adds the `hash`/`time`/`bundleId` triplet
  /// that the server-side middleware verifies before forwarding the
  /// request to the actual handler.
  Future<http.Response> _signedPost(
    String path,
    Map<String, String> fields,
  ) async {
    final unixSeconds = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();
    final raw = '$unixSeconds|$_signatureSecret';
    final hashHex = sha256.convert(utf8.encode(raw)).toString();

    final body = <String, String>{
      ...fields,
      'hash': hashHex,
      'time': unixSeconds,
      'bundleId': _signatureBundleId,
    };

    final uri = _buildUri(path, const {});
    return _client
        .post(
          uri,
          headers: const {
            'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
          },
          body: body,
        )
        .timeout(_timeout);
  }

  List<ServerConfig> _parseList(
    List<dynamic> raw, {
    required String defaultProtocol,
  }) {
    final out = <ServerConfig>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        try {
          // Per-protocol hint so models without an explicit `protocol`
          // field are still routed to the right native engine.
          final patched = <String, dynamic>{
            ...item,
            'protocol': item['protocol'] ?? defaultProtocol,
          };
          out.add(ServerConfig.fromJson(patched));
        } catch (_) {
          // Skip malformed records — a single broken doc must not
          // poison the whole list.
        }
      }
    }
    return out;
  }

  Future<void> _writeCache(String key, String json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, json);
    } catch (_) {
      /* best-effort */
    }
  }

  Future<List<ServerConfig>> _readMergedCache() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <ServerConfig>[];
    out.addAll(await _readCache(prefs, _kAwgCacheKey, 'awg'));
    out.sort((a, b) => b.priority.compareTo(a.priority));
    return out;
  }

  Future<List<ServerConfig>> _readCache(
    SharedPreferences prefs,
    String key,
    String defaultProtocol,
  ) async {
    try {
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return const [];
      final body = jsonDecode(raw) as Map<String, dynamic>;
      final list = body['data'];
      if (list is List) {
        return _parseList(list, defaultProtocol: defaultProtocol);
      }
    } catch (_) {
      /* ignore */
    }
    return const [];
  }

  static int? _parseEpochMs(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      final n = int.tryParse(raw);
      if (n != null) return n;
    }
    return null;
  }

  static int _toInt(dynamic raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  void close() {
    _client.close();
  }
}

// ─────────────────────────────────────────────────────────────────────
//  Public DTOs returned by [ApiService]
// ─────────────────────────────────────────────────────────────────────

/// Lightweight tuple returned by [ApiService.createUser]. Mirrors the
/// shape used by the splash screen so `created.userId` /
/// `created.mnemonic` still compile after a rename of the underlying
/// fields.
class UserSession {
  final String userId;
  final String mnemonic;
  const UserSession({required this.userId, required this.mnemonic});
}

/// Snapshot of the user record returned by `client/user/get`.
class UserState {
  final String userId;
  final bool isPremium;
  final int? premiumEndMs;
  final int totalDownload;
  final int totalUpload;

  const UserState({
    required this.userId,
    required this.isPremium,
    this.premiumEndMs,
    this.totalDownload = 0,
    this.totalUpload = 0,
  });
}

/// One row of `client/tariff/get`.
class TariffInfo {
  final String name;
  final String technicalName;
  final String description;
  final double price;
  final bool enabled;

  /// Plan duration in milliseconds. 30-day plan = `30 * 86400 * 1000`.
  final int durationMs;

  const TariffInfo({
    required this.name,
    required this.technicalName,
    required this.description,
    required this.price,
    required this.enabled,
    required this.durationMs,
  });

  factory TariffInfo.fromJson(Map<String, dynamic> json) {
    double parsePrice(dynamic raw) {
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw) ?? 0.0;
      return 0.0;
    }

    int parseDuration(dynamic raw) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw) ?? 0;
      return 0;
    }

    return TariffInfo(
      name: (json['name'] ?? '').toString(),
      technicalName: (json['technical_name'] ?? json['technicalName'] ?? '')
          .toString(),
      description: (json['description'] ?? '').toString(),
      price: parsePrice(json['price']),
      enabled: json['enabled'] == true,
      durationMs: parseDuration(json['duration']),
    );
  }
}

/// Result of [ApiService.login]. Either a success payload with the
/// restored session or one of the typed error codes (see the
/// `loginInvalidMnemonic` / `loginNetworkError` / `loginServerError`
/// constants on [ApiService]).
class LoginResult {
  final bool ok;
  final String? errorCode;
  final String userId;
  final String mnemonic;
  final bool isPremium;
  final int? premiumEndMs;

  const LoginResult._({
    required this.ok,
    this.errorCode,
    this.userId = '',
    this.mnemonic = '',
    this.isPremium = false,
    this.premiumEndMs,
  });

  factory LoginResult.success({
    required String userId,
    required String mnemonic,
    required bool isPremium,
    int? premiumEndMs,
  }) => LoginResult._(
    ok: true,
    userId: userId,
    mnemonic: mnemonic,
    isPremium: isPremium,
    premiumEndMs: premiumEndMs,
  );

  factory LoginResult.error(String code) =>
      LoginResult._(ok: false, errorCode: code);
}

/// Payment created via `payments/initiate` (WATA / SBP form).
class PaymentInitiation {
  final String paymentId;
  final String status;
  final String payUrl;
  final double amount;
  final String currency;

  const PaymentInitiation({
    required this.paymentId,
    required this.status,
    required this.payUrl,
    required this.amount,
    required this.currency,
  });
}

/// Result of `payments/check` polling.
class PaymentStatusResult {
  final String paymentId;
  final String status; // pending / paid / failed
  final bool isPremium;

  const PaymentStatusResult({
    required this.paymentId,
    required this.status,
    required this.isPremium,
  });
}
