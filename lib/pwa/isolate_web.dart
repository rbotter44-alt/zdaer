import 'dart:async';

class Isolate {
  static Future<T> run<T>(FutureOr<T> Function() computation) async {
    return await computation();
  }
}
