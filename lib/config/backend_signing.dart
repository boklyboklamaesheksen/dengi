import 'dart:convert';

import 'package:crypto/crypto.dart';

class BackendConfigurationException implements Exception {
  const BackendConfigurationException();

  @override
  String toString() => 'RABOCHIY_SIGNING_SECRET is not configured';
}

class BackendSigning {
  const BackendSigning({
    this._secret = const String.fromEnvironment('RABOCHIY_SIGNING_SECRET'),
  });

  final String _secret;

  Map<String, String> sign(Map<String, String> fields, {DateTime? now}) {
    if (_secret.trim().isEmpty) throw const BackendConfigurationException();
    final time = ((now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000)
        .toString();
    return {
      ...fields,
      'hash': sha256.convert(utf8.encode('$time|$_secret')).toString(),
      'time': time,
      'bundleId': 'app.rabochiy.vpn',
    };
  }
}
