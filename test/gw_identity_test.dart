import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:rabochiy_vpn/services/gw_identity.dart';

void main() {
  test('GW decrypts compressed, raw and SEC1 uncompressed ephemeral keys', () {
    final identity = GwIdentity.fromMnemonic('test-only recovery phrase');
    final domain = ECDomainParameters('secp256k1');
    final peerPrivate = BigInt.from(7);
    final peerPublic = (domain.G * peerPrivate)!;
    final clientPoint = domain.curve.decodePoint(
      Uint8List.fromList([
        4,
        for (var i = 0; i < identity.publicKeyXyHex.length; i += 2)
          int.parse(identity.publicKeyXyHex.substring(i, i + 2), radix: 16),
      ]),
    )!;
    final shared = (clientPoint * peerPrivate)!.x!.toBigInteger()!;
    final sharedHex = shared.toRadixString(16).padLeft(64, '0');
    final key = Uint8List.fromList(
      sha256.convert([
        for (var i = 0; i < 64; i += 2)
          int.parse(sharedHex.substring(i, i + 2), radix: 16),
        ...utf8.encode(GwIdentity.keyLabel),
      ]).bytes,
    );
    final iv = Uint8List.fromList(List.generate(12, (i) => i));
    const payload = '{"test":"GW catalogue fixture"}';
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128,
          iv,
          Uint8List.fromList(utf8.encode(GwIdentity.aad)),
        ),
      );
    final ciphertext = base64Encode(
      cipher.process(Uint8List.fromList(utf8.encode(payload))),
    );
    final uncompressed = peerPublic.getEncoded(false);
    for (final point in [
      peerPublic.getEncoded(true),
      uncompressed,
      uncompressed.sublist(1),
      Uint8List.fromList([0, ...uncompressed.sublist(1)]),
    ]) {
      final hex = point.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(
        identity.decryptEnvelope(
          ephHex: hex,
          ctBase64: ciphertext,
          ivBase64: base64Encode(iv),
        ),
        payload,
      );
    }
    expect(
      () => identity.decryptEnvelope(
        ephHex: 'abc',
        ctBase64: ciphertext,
        ivBase64: base64Encode(iv),
      ),
      throwsFormatException,
    );
  });
}
