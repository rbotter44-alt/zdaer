import 'io_compat.dart';

Future<Directory> getApplicationDocumentsDirectory() async => Directory('/pwa/documents');
Future<Directory> getTemporaryDirectory() async => Directory('/pwa/tmp');
Future<Directory?> getExternalStorageDirectory() async => null;
Future<Directory?> getDownloadsDirectory() async => Directory('/pwa/downloads');
