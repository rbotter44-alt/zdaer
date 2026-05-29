abstract class WebBackGuard {
  void dispose();
}

WebBackGuard createWebBackGuard(Future<bool> Function() onBrowserBack) => _NoopWebBackGuard();

class _NoopWebBackGuard implements WebBackGuard {
  @override
  void dispose() {}
}
