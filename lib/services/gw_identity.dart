import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Crypto identity of the device for the GW protocol (SSH-tunnel servers).
///
/// The scheme is 1:1 with the production GW backend:
///   key = SHA-256(ECDH_shared_X || "gw|key"), AES-256-GCM, AAD "gw-config-v1".
///
/// The key pair is derived deterministically from the user's mnemonic:
///   privateKey = SHA-256(utf8(mnemonic.trim())).
/// Reinstalling the app with the same mnemonic yields the same pubkey, so
/// per-server envelopes keep decrypting across reinstalls.
class GwIdentity {
  static const String keyLabel = 'gw|key';
  static const String aad = 'gw-config-v1';

  final BigInt privateKey;
  final String publicKeyXyHex; // x||y, 128 hex chars — as the GW client sends

  GwIdentity._(this.privateKey, this.publicKeyXyHex);

  static final ECDomainParameters _domain = ECDomainParameters('secp256k1');
  static final BigInt _n = _domain.n;
  static final ECPoint _G = _domain.G;

  /// Identity derived from the mnemonic phrase.
  static GwIdentity fromMnemonic(String mnemonic) {
    final digest = sha256.convert(utf8.encode(mnemonic.trim())).bytes;
    final priv = _bytesToBigInt(Uint8List.fromList(digest)) % _n;
    final pubPoint = (_G * priv)!;
    final x = _bigIntTo32(pubPoint.x!.toBigInteger()!);
    final y = _bigIntTo32(pubPoint.y!.toBigInteger()!);
    return GwIdentity._(priv, _toHex(x) + _toHex(y));
  }

  /// Decrypts a per-server envelope {eph, ct, iv} -> plaintext JSON string.
  String decryptEnvelope({
    required String ephHex,
    required String ctBase64,
    required String ivBase64,
  }) {
    final ephBytes = _hexToBytes(ephHex);
    final curve = _domain.curve;
    final ECPoint ephPoint;
    if (ephBytes.length == 33) {
      ephPoint = curve.decodePoint(ephBytes)!;
    } else if (ephBytes.length == 64) {
      final uncompressed = Uint8List(65)..[0] = 4;
      uncompressed.setRange(1, 65, ephBytes);
      ephPoint = curve.decodePoint(uncompressed)!;
    } else if (ephBytes.length == 65 && ephBytes[0] == 0) {
      final uncompressed = Uint8List(65)..[0] = 4;
      uncompressed.setRange(1, 65, ephBytes.sublist(1));
      ephPoint = curve.decodePoint(uncompressed)!;
    } else {
      throw ArgumentError('unsupported eph point length ${ephBytes.length}');
    }

    // ECDH: shared = privateKey * ephPoint, take the X coordinate (32 bytes).
    final sharedPoint = ephPoint * privateKey;
    final sharedX = _bigIntTo32(sharedPoint!.x!.toBigInteger()!);

    // key = SHA-256(shared_X || "gw|key")
    final keyMaterial =
        Uint8List.fromList([...sharedX, ...utf8.encode(keyLabel)]);
    final aesKey = Uint8List.fromList(sha256.convert(keyMaterial).bytes);

    final iv = base64Decode(ivBase64);
    final ct = base64Decode(ctBase64);

    // AES-256-GCM with AAD = "gw-config-v1".
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false, // decrypt
        AEADParameters(
          KeyParameter(aesKey),
          128,
          iv,
          Uint8List.fromList(utf8.encode(aad)),
        ),
      );

    final plain = cipher.process(ct);
    return utf8.decode(plain);
  }

  // ── math helpers ────────────────────────────────────────────────────
  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static Uint8List _bigIntTo32(BigInt value) {
    final bytes = <int>[];
    var v = value;
    while (v > BigInt.zero) {
      bytes.insert(0, (v & BigInt.from(0xff)).toInt());
      v = v >> 8;
    }
    final out = Uint8List(32);
    final start = 32 - bytes.length;
    for (var i = 0; i < bytes.length; i++) {
      out[start + i] = bytes[i];
    }
    return out;
  }

  static String _toHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.trim().toLowerCase().startsWith('0x')
        ? hex.trim().substring(2)
        : hex.trim();
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
