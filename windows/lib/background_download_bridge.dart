import 'dart:async';
import 'dart:convert';
import 'pwa/io_compat.dart';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'secure_strings.dart';

class BackgroundDownloadSnapshot {
  final String id;
  final String source;
  final String type;
  final String url;
  final String fileName;
  final String tempPath;
  final String finalPath;
  final String status;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final String? errorMessage;
  final String? qualityLabel;

  const BackgroundDownloadSnapshot({
    required this.id,
    required this.source,
    required this.type,
    required this.url,
    required this.fileName,
    required this.tempPath,
    required this.finalPath,
    required this.status,
    required this.progress,
    required this.downloadedBytes,
    required this.totalBytes,
    this.errorMessage,
    this.qualityLabel,
  });

  factory BackgroundDownloadSnapshot.fromMap(Map<dynamic, dynamic> map) {
    int intValue(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    double doubleValue(Object? value) {
      if (value is double) return value;
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    return BackgroundDownloadSnapshot(
      id: map['id']?.toString() ?? '',
      source: map['source']?.toString() ?? '',
      type: map['type']?.toString() ?? 'downloading',
      url: map['url']?.toString() ?? '',
      fileName: map['fileName']?.toString() ?? '',
      tempPath: map['tempPath']?.toString() ?? '',
      finalPath: map['finalPath']?.toString() ?? '',
      status: map['status']?.toString() ?? 'downloading',
      progress: doubleValue(map['progress']).clamp(0.0, 1.0).toDouble(),
      downloadedBytes: intValue(map['downloadedBytes']),
      totalBytes: intValue(map['totalBytes']),
      errorMessage: map['errorMessage']?.toString(),
      qualityLabel: map['qualityLabel']?.toString(),
    );
  }

  BackgroundDownloadSnapshot copyWith({
    String? status,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    String? errorMessage,
    String? tempPath,
    String? finalPath,
  }) {
    return BackgroundDownloadSnapshot(
      id: id,
      source: source,
      type: type,
      url: url,
      fileName: fileName,
      tempPath: tempPath ?? this.tempPath,
      finalPath: finalPath ?? this.finalPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: errorMessage,
      qualityLabel: qualityLabel,
    );
  }
}

class BackgroundDownloadBridge {
  static final MethodChannel _channel = MethodChannel(AppSecureText.s('3OgZ2S8RoC_0PBcfUgIj0xOPeOq-U_XATQ'));

  static final Map<String, BackgroundDownloadSnapshot> _desktopDownloads = <String, BackgroundDownloadSnapshot>{};
  static final Map<String, Map<String, String>> _desktopHeaders = <String, Map<String, String>>{};
  static final Map<String, String?> _desktopPageUrls = <String, String?>{};
  static final Set<String> _desktopCancelled = <String>{};
  static final Set<String> _desktopPaused = <String>{};

  static Future<void> requestNotificationPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(AppSecureText.s('44JlDjmFxGbUryBds9yKc6Widx8feMNs4Ay0yuk'));
    } catch (_) {}
  }

  static Future<String> enqueue({
    required String id,
    required String source,
    required String type,
    required String url,
    required String fileName,
    required String tempPath,
    required String finalPath,
    Map<String, String> headers = const <String, String>{},
    String? pageUrl,
    String? qualityLabel,
  }) async {
    if (!Platform.isAndroid) {
      final cleanId = id.trim().isEmpty ? DateTime.now().microsecondsSinceEpoch.toString() : id.trim();
      final snapshot = BackgroundDownloadSnapshot(
        id: cleanId,
        source: source,
        type: type,
        url: url,
        fileName: fileName,
        tempPath: tempPath,
        finalPath: finalPath,
        status: kIsWeb ? 'opened_in_browser' : 'queued',
        progress: kIsWeb ? 1.0 : 0.0,
        downloadedBytes: 0,
        totalBytes: 0,
        qualityLabel: qualityLabel,
      );
      _desktopDownloads[cleanId] = snapshot;
      _desktopHeaders[cleanId] = Map<String, String>.from(headers);
      _desktopPageUrls[cleanId] = pageUrl;
      _desktopCancelled.remove(cleanId);
      _desktopPaused.remove(cleanId);

      if (kIsWeb) {
        final target = Uri.tryParse(url);
        if (target != null) {
          unawaited(launchUrl(target, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank'));
        }
        return cleanId;
      }

      unawaited(_runDesktopDownload(cleanId));
      return cleanId;
    }

    await requestNotificationPermission();
    final result = await _channel.invokeMethod<String>(AppSecureText.s('Fp51A8ULzQ'), <String, dynamic>{
      AppSecureText.s('EWE'): id,
      AppSecureText.s('n7qu_QrZ'): source,
      AppSecureText.s('adAeUw'): type,
      AppSecureText.s('kTLY'): url,
      AppSecureText.s('-3cqd3idaFE'): fileName,
      AppSecureText.s('6XsrYmadcVw'): tempPath,
      AppSecureText.s('DvDxnvAb-BUt'): finalPath,
      AppSecureText.s('G5VlEsUM2w'): headers,
      if (pageUrl != null) AppSecureText.s('A5FjE_UMxA'): pageUrl,
      if (qualityLabel != null) AppSecureText.s('G54z90FzmNgrlFUU'): qualityLabel,
    });
    return result ?? id;
  }

  static Future<void> pause(String id) async {
    if (!Platform.isAndroid) {
      final clean = id.trim();
      if (clean.isEmpty) return;
      _desktopPaused.add(clean);
      final snap = _desktopDownloads[clean];
      if (snap != null && snap.status == 'downloading') {
        _desktopDownloads[clean] = snap.copyWith(status: 'paused');
      }
      return;
    }
    if (id.trim().isEmpty) return;
    try {
      await _channel.invokeMethod<void>(AppSecureText.s('CX6Z4NE'), <String, dynamic>{AppSecureText.s('EWE'): id});
    } catch (_) {}
  }

  static Future<void> resume(String id) async {
    if (!Platform.isAndroid) {
      final clean = id.trim();
      if (clean.isEmpty) return;
      final snap = _desktopDownloads[clean];
      if (snap == null || snap.status == 'done') return;
      _desktopPaused.remove(clean);
      _desktopCancelled.remove(clean);
      _desktopDownloads[clean] = snap.copyWith(status: 'queued', errorMessage: null);
      unawaited(_runDesktopDownload(clean));
      return;
    }
    if (id.trim().isEmpty) return;
    try {
      await _channel.invokeMethod<void>(AppSecureText.s('nrCo-gTZ'), <String, dynamic>{AppSecureText.s('EWE'): id});
    } catch (_) {}
  }

  static Future<void> cancel(String id) async {
    if (!Platform.isAndroid) {
      final clean = id.trim();
      if (clean.isEmpty) return;
      _desktopCancelled.add(clean);
      final snap = _desktopDownloads[clean];
      if (snap != null && snap.status != 'done') {
        _desktopDownloads[clean] = snap.copyWith(status: 'cancelled');
      }
      return;
    }
    if (id.trim().isEmpty) return;
    try {
      await _channel.invokeMethod<void>(AppSecureText.s('j7S17AzQ'), <String, dynamic>{AppSecureText.s('EWE'): id});
    } catch (_) {}
  }

  static Future<void> delete(String id) async {
    if (!Platform.isAndroid) {
      final clean = id.trim();
      if (clean.isEmpty) return;
      _desktopCancelled.add(clean);
      final snap = _desktopDownloads.remove(clean);
      _desktopHeaders.remove(clean);
      _desktopPageUrls.remove(clean);
      if (snap != null) {
        for (final path in <String>[snap.tempPath, snap.finalPath]) {
          if (path.trim().isEmpty) continue;
          try {
            final file = File(path);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
      }
      return;
    }
    if (id.trim().isEmpty) return;
    try {
      await _channel.invokeMethod<void>(AppSecureText.s('iLC36h3Z'), <String, dynamic>{AppSecureText.s('EWE'): id});
    } catch (_) {}
  }

  static Future<List<BackgroundDownloadSnapshot>> list({String? source}) async {
    if (!Platform.isAndroid) {
      final filter = source?.trim();
      final values = _desktopDownloads.values.where((e) => filter == null || filter.isEmpty || e.source == filter).toList(growable: false);
      values.sort((a, b) => a.fileName.compareTo(b.fileName));
      return values;
    }
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(AppSecureText.s('ccAdQg'), <String, dynamic>{
        if (source != null && source.trim().isNotEmpty) AppSecureText.s('n7qu_QrZ'): source,
      });
      return (raw ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map(BackgroundDownloadSnapshot.fromMap)
          .toList(growable: false);
    } catch (_) {
      return const <BackgroundDownloadSnapshot>[];
    }
  }

  static Future<void> _runDesktopDownload(String id) async {
    var snap = _desktopDownloads[id];
    if (snap == null || snap.status == 'downloading') return;
    _desktopDownloads[id] = snap.copyWith(status: 'downloading', errorMessage: null);
    final headers = Map<String, String>.from(_desktopHeaders[id] ?? const <String, String>{});
    final pageUrl = _desktopPageUrls[id];
    if (pageUrl != null && pageUrl.trim().isNotEmpty) {
      headers.putIfAbsent('Referer', () => pageUrl);
    }

    try {
      final finalFile = File(snap.finalPath);
      final tempFile = File(snap.tempPath.trim().isEmpty ? '${snap.finalPath}.downloading' : snap.tempPath);
      await tempFile.parent.create(recursive: true);
      await finalFile.parent.create(recursive: true);
      final isHls = snap.type.toLowerCase().contains('hls') || snap.url.toLowerCase().contains('.m3u8');
      if (isHls) {
        await _downloadHls(id, snap.url, tempFile, headers);
      } else {
        await _downloadDirect(id, snap.url, tempFile, headers);
      }
      if (_desktopCancelled.contains(id) || _desktopPaused.contains(id)) return;
      if (await finalFile.exists()) await finalFile.delete();
      if (await tempFile.exists()) await tempFile.rename(finalFile.path);
      snap = _desktopDownloads[id];
      if (snap != null) {
        _desktopDownloads[id] = snap.copyWith(
          status: 'done',
          progress: 1.0,
          downloadedBytes: snap.totalBytes > 0 ? snap.totalBytes : snap.downloadedBytes,
          errorMessage: null,
        );
      }
    } catch (e) {
      final current = _desktopDownloads[id];
      if (current != null && !_desktopCancelled.contains(id) && !_desktopPaused.contains(id)) {
        _desktopDownloads[id] = current.copyWith(status: 'failed', errorMessage: e.toString());
      }
    }
  }

  static Future<void> _downloadDirect(String id, String url, File output, Map<String, String> headers) async {
    final request = await _client().getUrl(Uri.parse(url));
    headers.forEach((key, value) {
      if (key.trim().isNotEmpty && value.trim().isNotEmpty) request.headers.set(key, value);
    });
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    final total = response.contentLength > 0 ? response.contentLength : 0;
    var downloaded = 0;
    final sink = output.openWrite();
    try {
      await for (final chunk in response) {
        if (_desktopCancelled.contains(id)) throw const _DesktopDownloadStopped('cancelled');
        if (_desktopPaused.contains(id)) throw const _DesktopDownloadStopped('paused');
        downloaded += chunk.length;
        sink.add(chunk);
        final current = _desktopDownloads[id];
        if (current != null) {
          _desktopDownloads[id] = current.copyWith(
            status: 'downloading',
            downloadedBytes: downloaded,
            totalBytes: total,
            progress: total > 0 ? (downloaded / total).clamp(0.0, 1.0).toDouble() : current.progress,
          );
        }
      }
    } finally {
      await sink.close();
    }
  }

  static Future<void> _downloadHls(String id, String playlistUrl, File output, Map<String, String> headers) async {
    var mediaUrl = playlistUrl;
    var playlist = await _downloadText(mediaUrl, headers);
    final variant = _selectBestVariant(mediaUrl, playlist);
    if (variant != null) {
      mediaUrl = variant;
      playlist = await _downloadText(mediaUrl, headers);
    }
    if (RegExp(r'#EXT-X-KEY:.*METHOD=(?!NONE)', caseSensitive: false).hasMatch(playlist)) {
      throw const FormatException('Encrypted HLS is not supported by the desktop fallback downloader');
    }
    final base = Uri.parse(mediaUrl);
    final segmentUrls = <String>[];
    String? initSegment;
    for (final raw in const LineSplitter().convert(playlist)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-MAP')) {
        final m = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (m != null) initSegment = base.resolve(m.group(1)!).toString();
      }
      if (line.startsWith('#')) continue;
      segmentUrls.add(base.resolve(line).toString());
    }
    if (segmentUrls.isEmpty) throw const FormatException('No HLS segments found');

    final sink = output.openWrite();
    var done = 0;
    try {
      if (initSegment != null) {
        final bytes = await _downloadBytes(initSegment, headers);
        sink.add(bytes);
      }
      for (final segment in segmentUrls) {
        if (_desktopCancelled.contains(id)) throw const _DesktopDownloadStopped('cancelled');
        if (_desktopPaused.contains(id)) throw const _DesktopDownloadStopped('paused');
        final bytes = await _downloadBytes(segment, headers);
        sink.add(bytes);
        done++;
        final current = _desktopDownloads[id];
        if (current != null) {
          _desktopDownloads[id] = current.copyWith(
            status: 'downloading',
            downloadedBytes: done,
            totalBytes: segmentUrls.length,
            progress: (done / segmentUrls.length).clamp(0.0, 1.0).toDouble(),
          );
        }
      }
    } finally {
      await sink.close();
    }
  }

  static String? _selectBestVariant(String playlistUrl, String playlist) {
    final lines = const LineSplitter().convert(playlist);
    final base = Uri.parse(playlistUrl);
    var bestScore = -1;
    String? bestUrl;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      var score = 0;
      final bandwidth = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      if (bandwidth != null) score += int.tryParse(bandwidth.group(1) ?? '') ?? 0;
      final resolution = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line);
      if (resolution != null) score += (int.tryParse(resolution.group(1) ?? '') ?? 0) * 100000000;
      for (var j = i + 1; j < lines.length; j++) {
        final candidate = lines[j].trim();
        if (candidate.isEmpty) continue;
        if (candidate.startsWith('#')) continue;
        if (score > bestScore) {
          bestScore = score;
          bestUrl = base.resolve(candidate).toString();
        }
        break;
      }
    }
    return bestUrl;
  }

  static Future<String> _downloadText(String url, Map<String, String> headers) async {
    final bytes = await _downloadBytes(url, headers);
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Future<List<int>> _downloadBytes(String url, Map<String, String> headers) async {
    final request = await _client().getUrl(Uri.parse(url));
    headers.forEach((key, value) {
      if (key.trim().isNotEmpty && value.trim().isNotEmpty) request.headers.set(key, value);
    });
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static HttpClient _client() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 25);
    return client;
  }
}

class _DesktopDownloadStopped implements Exception {
  final String reason;
  const _DesktopDownloadStopped(this.reason);
  @override
  String toString() => reason;
}
