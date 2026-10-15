import 'dart:convert';
import 'dart:typed_data';

/// gwenc1 — symmetric string codec shared with the GW and VLESS apps.
///
/// Keeps plain `https://…` strings out of the APK and out of the Remote
/// Config JSON (exactly what DPI parsers and reverse engineers grep for).
/// This is obfuscation, not cryptographic secrecy.
///
/// Format: `gwenc1:` + base64( reverse( ((plain[i] XOR key[i mod 16]) + 0x5D) mod 256 ) )
class SecretCodec {
  SecretCodec._();

  static const String prefix = 'gwenc1:';
  static const int _offset = 0x5D;
  static const List<int> _key = <int>[
    0x37,
    0x5B,
    0x71,
    0x2E,
    0x49,
    0x6D,
    0x23,
    0x58,
    0x0F,
    0x66,
    0x3C,
    0x7A,
    0x11,
    0x44,
    0x69,
    0x05,
  ];

  static final RegExp _whitespace = RegExp(r'\s+');

  /// Console copy/paste tolerance: surrounding blanks and quotes.
  static String _clean(String? raw) {
    var value = raw?.trim() ?? '';
    while (value.length >= 2 &&
        (value.startsWith('"') || value.startsWith("'")) &&
        value.endsWith(value[0])) {
      value = value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  static bool isEncoded(String? raw) => _clean(raw).startsWith(prefix);

  /// Decodes a gwenc1 value. Returns `null` for broken payloads and the
  /// cleaned input unchanged when it carries no gwenc1 prefix.
  static String? tryDecode(String? raw) {
    final value = _clean(raw);
    if (!value.startsWith(prefix)) return value;
    try {
      final payload = value
          .substring(prefix.length)
          .replaceAll(_whitespace, '');
      final data = base64.decode(base64.normalize(payload));
      if (data.isEmpty) return null;
      final out = Uint8List(data.length);
      for (var i = 0; i < data.length; i++) {
        final shifted = (data[data.length - 1 - i] - _offset) & 0xFF;
        out[i] = (shifted ^ _key[i % _key.length]) & 0xFF;
      }
      return utf8.decode(out);
    } catch (_) {
      return null;
    }
  }

  /// Like [tryDecode], but never loses a value: broken payloads come back
  /// as the cleaned input.
  static String decode(String? raw) => tryDecode(raw) ?? _clean(raw);

  /// Produces values for the Firebase console and baked-in defaults.
  static String encode(String plain) {
    final data = utf8.encode(plain);
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      final shifted = ((data[i] ^ _key[i % _key.length]) + _offset) & 0xFF;
      out[data.length - 1 - i] = shifted;
    }
    return prefix + base64.encode(out);
  }
}
