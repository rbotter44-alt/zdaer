import 'dart:async';
import 'pwa/io_compat.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'secure_strings.dart';

class NativeSecurityGuard {
  NativeSecurityGuard._();

  static final MethodChannel _channel =
      MethodChannel(AppSecureText.s('XaDnjqsGRK_BixWqXwicB-2y'));

  static bool _checked = false;

  // Strict by default: modified/resigned/debug/tampered builds must not continue.
  // You can temporarily disable only for local testing with:
  // --dart-define=APP_STRICT_SECURITY=false
  static const bool _strictSecurity = bool.fromEnvironment(
    'APP_STRICT_SECURITY',
    defaultValue: true,
  );

  static Future<void> ensureClean() async {
    if (!Platform.isAndroid) return;
    if (_checked) return;
    _checked = true;

    const bool productMode = bool.fromEnvironment('dart.vm.product');

    if (!kReleaseMode || kDebugMode || kProfileMode || !productMode) {
      if (_strictSecurity) _terminate();
      return;
    }

    try {
      // نؤخر الفحص بعد ظهور الواجهة حتى لا يبقى التطبيق صافن على شاشة البداية.
      await Future<void>.delayed(const Duration(seconds: 2));

      final Map<String, dynamic>? status = await _channel
          .invokeMapMethod<String, dynamic>(AppSecureText.s('GneJ8N8'))
          .timeout(const Duration(seconds: 2));

      final bool ok = status?[AppSecureText.s('F24')] == true;
      if (!ok && _strictSecurity) _terminate();
    } catch (_) {
      // لا نوقف التطبيق بسبب تأخر القناة أو أول تشغيل؛ هذا يمنع freeze/false crash.
      return;
    }
  }

  static Never _terminate() {
    if (Platform.isAndroid) {
      exit(0);
    }
    throw StateError(AppSecureText.s('mLS2_wzO'));
  }
}
