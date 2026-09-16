import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rabochiy_vpn/l10n/app_localizations.dart';
import 'package:rabochiy_vpn/l10n/error_messages.dart';
import 'package:rabochiy_vpn/services/vpn_service.dart';

import 'support/catalog_fakes.dart';

/// Exercises the AWG connect path against a scripted native bridge. The
/// engine only reports CONNECTED after a real handshake now, so a server
/// that never answers surfaces as `awg_handshake_timeout` rather than a
/// bogus "connected" state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel control = MethodChannel('rabochiy_vpn/engine');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(control, null));

  test('handshake timeout maps to a stable, localisable error code', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(control, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'initialize':
        case 'requestPermission':
          return true;
        case 'connect':
          throw PlatformException(
            code: 'AWG_HANDSHAKE_TIMEOUT',
            message: 'awg_handshake_timeout',
          );
        case 'disconnect':
          return true;
      }
      return null;
    });

    final service = VpnService(platformSupported: true);
    addTearDown(service.dispose);
    final statuses = <VpnStatus>[];
    service.statusStream.listen(statuses.add);

    expect(await service.connect(awgServer), isFalse);
    await Future<void>.delayed(Duration.zero);

    expect(service.errorMessage, 'awg_handshake_timeout');
    expect(service.status, VpnStatus.error);
    expect(statuses, [VpnStatus.connecting, VpnStatus.error]);
    expect(calls, containsAllInOrder(['requestPermission', 'connect']));

    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      expect(
        localiseError(service.errorMessage, l10n),
        l10n.errorServerUnreachable,
        reason: locale.languageCode,
      );
    }
  });

  test('native false without an exception is still an engine error', () async {
    messenger.setMockMethodCallHandler(control, (call) async {
      switch (call.method) {
        case 'requestPermission':
          return true;
        case 'connect':
          return false;
      }
      return null;
    });

    final service = VpnService(platformSupported: true);
    addTearDown(service.dispose);
    expect(await service.connect(awgServer), isFalse);
    expect(service.errorMessage, 'engine_not_ready');
    expect(service.status, VpnStatus.error);
  });

  test('cancel during the handshake wait wins over the late result', () async {
    final pendingConnect = Completer<bool>();
    messenger.setMockMethodCallHandler(control, (call) async {
      switch (call.method) {
        case 'requestPermission':
        case 'disconnect':
          return true;
        case 'connect':
          return pendingConnect.future;
      }
      return null;
    });

    final service = VpnService(platformSupported: true);
    addTearDown(service.dispose);
    final statuses = <VpnStatus>[];
    service.statusStream.listen(statuses.add);

    final attempt = service.connect(awgServer);
    await Future<void>.delayed(Duration.zero);
    expect(service.status, VpnStatus.connecting);

    // User taps "cancel" while the native side is still polling for the
    // first handshake; the engine then reports the timeout it hit.
    await service.cancelConnect();
    pendingConnect.completeError(
      PlatformException(code: 'AWG_HANDSHAKE_TIMEOUT'),
    );
    expect(await attempt, isFalse);

    expect(service.status, VpnStatus.disconnected);
    expect(service.errorMessage, isNull);
    expect(statuses, isNot(contains(VpnStatus.error)));
  });

  test('successful connect stays in connecting until the engine confirms',
      () async {
    messenger.setMockMethodCallHandler(control, (call) async {
      switch (call.method) {
        case 'requestPermission':
        case 'connect':
          return true;
      }
      return null;
    });

    final service = VpnService(platformSupported: true);
    addTearDown(service.dispose);
    expect(await service.connect(awgServer), isTrue);
    // The CONNECTED transition arrives on the event channel from the
    // native side once the handshake lands — a `true` return alone must
    // not flip the UI.
    expect(service.status, VpnStatus.connecting);
    expect(service.errorMessage, isNull);
  });
}
