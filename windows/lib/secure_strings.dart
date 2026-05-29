import 'dart:convert';

/// Runtime string vault.
/// Keeps sensitive constants out of plain-text APK/source snapshots.
class AppSecureText {
  AppSecureText._();

  static const List<int> _a = <int>[87, 19, 169, 196, 46, 123, 129, 15, 210, 54, 156, 68, 225, 90, 104, 183, 35, 240, 29, 142, 202, 4, 121, 177];
  static const List<int> _b = <int>[140, 42, 97, 215, 3, 190, 79, 149, 25, 234, 112, 198, 53, 173, 2, 88, 243, 65, 155, 32, 222, 103, 20, 162, 204, 57, 117, 232, 6, 191, 82, 144];
  static final Map<String, String> _cache = <String, String>{};

  static String s(String blob) {
    final cached = _cache[blob];
    if (cached != null) return cached;
    final padded = blob.padRight(blob.length + ((4 - blob.length % 4) % 4), '=');
    final raw = base64Url.decode(padded);
    final len = raw.length;
    final out = List<int>.filled(len, 0, growable: false);
    for (var i = 0; i < len; i++) {
      final ka = _a[(i * 7 + len) % _a.length];
      final kb = _b[(i * 11 + 13) % _b.length];
      final mask = (ka ^ kb ^ ((i * 131 + len * 17 + 0x5a) & 0xff)) & 0xff;
      out[i] = raw[i] ^ mask;
    }
    final value = utf8.decode(out);
    _cache[blob] = value;
    return value;
  }
}
