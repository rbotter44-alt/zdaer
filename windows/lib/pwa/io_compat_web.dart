
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

void exit(int code) {
  throw UnsupportedError('exit() is not available in PWA/web builds.');
}

class Platform {
  static const bool isAndroid = false;
  static const bool isIOS = false;
  static const bool isWindows = false;
  static const bool isLinux = false;
  static const bool isMacOS = false;
  static const String pathSeparator = '/';
}

class FileSystemEntity {
  final String path;
  const FileSystemEntity(this.path);
  Uri get uri => Uri(path: path);
  Future<FileStat> stat() async => const FileStat();

  Directory get parent {
    final index = path.lastIndexOf('/');
    if (index <= 0) return Directory('/');
    return Directory(path.substring(0, index));
  }
}

class File extends FileSystemEntity {
  File(super.path);
  factory File.fromUri(Uri uri) => File(uri.toFilePath());

  Future<bool> exists() async => false;
  bool existsSync() => false;
  Future<File> create({bool recursive = false, bool exclusive = false}) async => this;
  void createSync({bool recursive = false, bool exclusive = false}) {}
  Future<void> delete({bool recursive = false}) async {}
  void deleteSync({bool recursive = false}) {}
  Future<String> readAsString({Encoding encoding = utf8}) async => '';
  Future<Uint8List> readAsBytes() async => Uint8List(0);
  Future<File> writeAsString(String contents, {FileMode mode = FileMode.write, Encoding encoding = utf8, bool flush = false}) async => this;
  Future<File> writeAsBytes(List<int> bytes, {FileMode mode = FileMode.write, bool flush = false}) async => this;
  Stream<List<int>> openRead([int? start, int? end]) => const Stream<List<int>>.empty();
  IOSink openWrite({FileMode mode = FileMode.write, Encoding encoding = utf8}) => IOSink();
  Future<int> length() async => 0;
  int lengthSync() => 0;
  Future<File> copy(String newPath) async => File(newPath);
  Future<File> rename(String newPath) async => File(newPath);
  Future<FileStat> stat() async => const FileStat();
  File get absolute => this;
}

class Directory extends FileSystemEntity {
  Directory(super.path);

  Future<bool> exists() async => false;
  bool existsSync() => false;
  Future<Directory> create({bool recursive = false}) async => this;
  void createSync({bool recursive = false}) {}
  Future<void> delete({bool recursive = false}) async {}
  void deleteSync({bool recursive = false}) {}
  Stream<FileSystemEntity> list({bool recursive = false, bool followLinks = true}) => const Stream<FileSystemEntity>.empty();
  List<FileSystemEntity> listSync({bool recursive = false, bool followLinks = true}) => <FileSystemEntity>[];
  Directory get absolute => this;
}

class FileStat {
  const FileStat();
  DateTime get modified => DateTime.fromMillisecondsSinceEpoch(0);
  int get size => 0;
}

class FileMode {
  final String _name;
  const FileMode._(this._name);
  static const FileMode write = FileMode._('write');
  static const FileMode append = FileMode._('append');
  static const FileMode read = FileMode._('read');
  @override
  String toString() => _name;
}

class IOSink {
  final Completer<void> _done = Completer<void>();
  Future<void> get done => _done.future;
  void add(List<int> data) {}
  void addError(Object error, [StackTrace? stackTrace]) {
    if (!_done.isCompleted) _done.completeError(error, stackTrace);
  }
  Future<void> flush() async {}
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }
}

class HttpException implements Exception {
  final String message;
  final Uri? uri;
  const HttpException(this.message, {this.uri});
  @override
  String toString() => uri == null ? message : '$message, uri = $uri';
}

class HttpClient {
  Duration? connectionTimeout;
  Future<HttpClientRequest> getUrl(Uri url) async => HttpClientRequest(url);
  Future<HttpClientRequest> openUrl(String method, Uri url) async => HttpClientRequest(url);
  void close({bool force = false}) {}
}

class HttpClientRequest {
  final Uri url;
  final HttpHeaders headers = HttpHeaders();
  HttpClientRequest(this.url);
  Future<HttpClientResponse> close() async => HttpClientResponse();
}

class HttpClientResponse extends Stream<List<int>> {
  final int statusCode = 0;
  final int contentLength = 0;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return const Stream<List<int>>.empty().listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

class HttpHeaders {
  static const String userAgentHeader = 'user-agent';
  static const String refererHeader = 'referer';
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}
