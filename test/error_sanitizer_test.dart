import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rabochiy_vpn/l10n/app_localizations.dart';
import 'package:rabochiy_vpn/l10n/error_messages.dart';
import 'package:rabochiy_vpn/services/error_sanitizer.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('network failures become the generic unreachable message', () {
    for (final raw in [
      "ClientException with SocketException: Failed host lookup: 'api.example.com'",
      'Failed to connect to /203.0.113.7:443',
      'java.net.SocketTimeoutException: timeout',
      'HandshakeException: Connection terminated during handshake',
    ]) {
      expect(
        localiseError(raw, l10n),
        l10n.errorServerUnreachable,
        reason: raw,
      );
    }
  });

  test('other raw errors are shown without addresses', () {
    final text = localiseError(
      'Bad config for https://api.example.com/x node 203.0.113.7:51820 '
      'host vpn.example.org [2001:db8::1]:443',
      l10n,
    );
    expect(text, isNot(contains('example')));
    expect(text, isNot(contains('203.0.113.7')));
    expect(text, isNot(contains('2001:db8')));
    expect(text, contains('Bad config'));
  });

  test('stable codes are untouched', () {
    expect(localiseError('engine_not_ready', l10n), l10n.errorEngineNotReady);
    expect(ErrorSanitizer.isNetworkError(null), isFalse);
    expect(ErrorSanitizer.stripEndpoints('plain words'), 'plain words');
  });
}
