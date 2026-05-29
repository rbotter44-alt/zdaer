import 'package:path_provider/path_provider.dart' as path_provider;
import 'io_compat.dart';

Future<Directory> getApplicationDocumentsDirectory() => path_provider.getApplicationDocumentsDirectory();
Future<Directory> getTemporaryDirectory() => path_provider.getTemporaryDirectory();
Future<Directory?> getExternalStorageDirectory() => path_provider.getExternalStorageDirectory();
Future<Directory?> getDownloadsDirectory() => path_provider.getDownloadsDirectory();
