import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

abstract class WebBackGuard {
  void dispose();
}

WebBackGuard createWebBackGuard(Future<bool> Function() onBrowserBack) =>
    _BrowserHistoryBackGuard(onBrowserBack);

class _BrowserHistoryBackGuard implements WebBackGuard {
  _BrowserHistoryBackGuard(this._onBrowserBack) {
    _pushGuardState();
    _sub = html.window.onPopState.listen(_handlePopState);
  }

  final Future<bool> Function() _onBrowserBack;
  StreamSubscription<html.PopStateEvent>? _sub;
  bool _disposed = false;
  bool _handling = false;

  void _pushGuardState() {
    if (_disposed) return;
    try {
      html.window.history.pushState(<String, Object>{
        'lightonBackGuard': true,
        't': DateTime.now().microsecondsSinceEpoch,
      }, '', html.window.location.href);
    } catch (_) {}
  }

  Future<void> _handlePopState(html.PopStateEvent event) async {
    if (_disposed || _handling) return;
    _handling = true;
    var shouldLeaveLightOn = false;
    try {
      shouldLeaveLightOn = await _onBrowserBack();
    } catch (_) {
      shouldLeaveLightOn = false;
    } finally {
      _handling = false;
    }

    // إذا رجعنا داخل Light On فقط، نرجّع guard state حتى زر Back القادم
    // يبقى تحت سيطرة Flutter ولا يخرج من الموقع مباشرة.
    if (!_disposed && !shouldLeaveLightOn) {
      _pushGuardState();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
  }
}
