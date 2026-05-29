import 'dart:async';
import 'pwa/io_compat.dart' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class UniversalMediaPlayerResult {
  final double positionSeconds;
  final bool completed;

  const UniversalMediaPlayerResult({
    required this.positionSeconds,
    this.completed = false,
  });
}

typedef UniversalOptionCallback = FutureOr<void> Function(Map<String, dynamic> option);

Future<UniversalMediaPlayerResult?> openUniversalMediaPlayer(
  BuildContext context, {
  required String url,
  String? title,
  String? pageUrl,
  String? mimeType,
  Map<String, String> headers = const <String, String>{},
  double currentTime = 0,
  List<Map<String, dynamic>> qualityOptions = const <Map<String, dynamic>>[],
  String? currentQualityLabel,
  List<Map<String, dynamic>> serverOptions = const <Map<String, dynamic>>[],
  String? currentServerLabel,
  List<Map<String, dynamic>> subtitleTracks = const <Map<String, dynamic>>[],
  UniversalOptionCallback? onQualitySelected,
  UniversalOptionCallback? onServerSelected,
}) {
  return Navigator.of(context).push<UniversalMediaPlayerResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => UniversalMediaPlayerPage(
        url: url,
        title: title,
        pageUrl: pageUrl,
        mimeType: mimeType,
        headers: headers,
        currentTime: currentTime,
        qualityOptions: qualityOptions,
        currentQualityLabel: currentQualityLabel,
        serverOptions: serverOptions,
        currentServerLabel: currentServerLabel,
        subtitleTracks: subtitleTracks,
        onQualitySelected: onQualitySelected,
        onServerSelected: onServerSelected,
      ),
    ),
  );
}

class UniversalMediaPlayerPage extends StatefulWidget {
  final String url;
  final String? title;
  final String? pageUrl;
  final String? mimeType;
  final Map<String, String> headers;
  final double currentTime;
  final List<Map<String, dynamic>> qualityOptions;
  final String? currentQualityLabel;
  final List<Map<String, dynamic>> serverOptions;
  final String? currentServerLabel;
  final List<Map<String, dynamic>> subtitleTracks;
  final UniversalOptionCallback? onQualitySelected;
  final UniversalOptionCallback? onServerSelected;

  const UniversalMediaPlayerPage({
    super.key,
    required this.url,
    this.title,
    this.pageUrl,
    this.mimeType,
    this.headers = const <String, String>{},
    this.currentTime = 0,
    this.qualityOptions = const <Map<String, dynamic>>[],
    this.currentQualityLabel,
    this.serverOptions = const <Map<String, dynamic>>[],
    this.currentServerLabel,
    this.subtitleTracks = const <Map<String, dynamic>>[],
    this.onQualitySelected,
    this.onServerSelected,
  });

  @override
  State<UniversalMediaPlayerPage> createState() => _UniversalMediaPlayerPageState();
}

class _UniversalMediaPlayerPageState extends State<UniversalMediaPlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _completedSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _fill = true;
  bool _loading = true;
  String? _error;
  String? _currentQuality;
  String? _currentServer;
  String? _currentSubtitle;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _currentQuality = _normalizeLabel(widget.currentQualityLabel);
    _currentServer = _normalizeLabel(widget.currentServerLabel);
    _positionSub = _player.stream.position.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _durationSub = _player.stream.duration.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
    _completedSub = _player.stream.completed.listen((value) {
      if (mounted) setState(() => _completed = value);
    });
    unawaited(_open(widget.url, seekTo: Duration(milliseconds: (widget.currentTime * 1000).round())));
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completedSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _open(String url, {Duration seekTo = Duration.zero}) async {
    if (url.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final safeHeaders = Map<String, String>.from(widget.headers)
        ..removeWhere((key, value) => key.trim().isEmpty || value.trim().isEmpty);
      await _player.open(Media(url.trim(), httpHeaders: safeHeaders));
      if (seekTo > Duration.zero) {
        await Future.delayed(const Duration(milliseconds: 250));
        await _player.seek(seekTo);
      }
      await _applyFirstSubtitleTrack();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applyFirstSubtitleTrack() async {
    if (widget.subtitleTracks.isEmpty) return;
    for (final item in widget.subtitleTracks) {
      final url = _firstNonEmpty(item, const ['url', 'uri', 'src', 'file']);
      if (url.isEmpty) continue;
      final title = _firstNonEmpty(item, const ['label', 'title', 'name', 'language']);
      final language = _firstNonEmpty(item, const ['language', 'lang']);
      try {
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(
            url,
            title: title.isEmpty ? 'Subtitle' : title,
            language: language.isEmpty ? null : language,
          ),
        );
        if (mounted) setState(() => _currentSubtitle = title.isEmpty ? 'Subtitle' : title);
        return;
      } catch (_) {}
    }
  }

  Future<void> _chooseSubtitle(Map<String, dynamic> item) async {
    final url = _firstNonEmpty(item, const ['url', 'uri', 'src', 'file']);
    if (url.isEmpty) return;
    final title = _firstNonEmpty(item, const ['label', 'title', 'name', 'language']);
    final language = _firstNonEmpty(item, const ['language', 'lang']);
    try {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          url,
          title: title.isEmpty ? 'Subtitle' : title,
          language: language.isEmpty ? null : language,
        ),
      );
      if (mounted) setState(() => _currentSubtitle = title.isEmpty ? 'Subtitle' : title);
    } catch (e) {
      _showSnack('تعذّر تحميل ملف الترجمة');
    }
  }

  Future<void> _chooseQuality(Map<String, dynamic> item) async {
    final label = _firstNonEmpty(item, const ['label', 'quality', 'title', 'name']);
    final directUrl = _firstNonEmpty(item, const ['url', 'src', 'file']);
    if (label.isNotEmpty && mounted) setState(() => _currentQuality = label);
    if (directUrl.isNotEmpty) {
      await _open(directUrl, seekTo: _position);
      return;
    }
    if (widget.onQualitySelected != null) {
      await widget.onQualitySelected!(item);
    } else {
      _showSnack('هذا الخيار يحتاج تغيير من صفحة المشاهدة نفسها');
    }
  }

  Future<void> _chooseServer(Map<String, dynamic> item) async {
    final label = _firstNonEmpty(item, const ['label', 'server', 'title', 'name']);
    final directUrl = _firstNonEmpty(item, const ['url', 'embedUrl', 'src', 'file']);
    if (label.isNotEmpty && mounted) setState(() => _currentServer = label);
    if (directUrl.isNotEmpty && _looksLikePlayableMediaUrl(directUrl)) {
      await _open(directUrl, seekTo: _position);
      return;
    }
    if (widget.onServerSelected != null) {
      await widget.onServerSelected!(item);
    } else {
      _showSnack('هذا السيرفر يحتاج اختيار من صفحة المشاهدة نفسها');
    }
  }

  bool _looksLikePlayableMediaUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.mkv') ||
        lower.contains('.webm') ||
        lower.contains('.mov') ||
        lower.contains('.m4v') ||
        lower.contains('.ts');
  }

  String _firstNonEmpty(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value != 'null') return value;
    }
    return '';
  }

  String? _normalizeLabel(String? value) {
    final clean = value?.trim();
    if (clean == null || clean.isEmpty || clean == 'null') return null;
    return clean;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _close() async {
    final result = UniversalMediaPlayerResult(
      positionSeconds: _position.inMilliseconds / 1000.0,
      completed: _completed,
    );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.title ?? '').trim();
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_close());
      },
      child: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
          LogicalKeySet(LogicalKeyboardKey.keyF): const _ToggleFillIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) { unawaited(_close()); return null; }),
            _ToggleFillIntent: CallbackAction<_ToggleFillIntent>(onInvoke: (_) { setState(() => _fill = !_fill); return null; }),
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Center(
                      child: _error != null
                          ? _ErrorView(message: _error!, onRetry: () => _open(widget.url, seekTo: _position))
                          : Video(
                              controller: _controller,
                              fit: _fill ? BoxFit.cover : BoxFit.contain,
                              controls: isDesktop ? MaterialDesktopVideoControls : MaterialVideoControls,
                              subtitleViewConfiguration: const SubtitleViewConfiguration(
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  height: 1.35,
                                  backgroundColor: Color(0x99000000),
                                  shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                                ),
                                padding: EdgeInsets.only(left: 24, right: 24, bottom: 48),
                                textAlign: TextAlign.center,
                              ),
                            ),
                    ),
                  ),
                  if (_loading)
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 10,
                    child: _TopBar(
                      title: title.isEmpty ? 'Universal Player' : title,
                      fill: _fill,
                      onClose: _close,
                      onToggleFill: () => setState(() => _fill = !_fill),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _OptionBar(
                      currentQuality: _currentQuality,
                      currentServer: _currentServer,
                      currentSubtitle: _currentSubtitle,
                      qualityOptions: widget.qualityOptions,
                      serverOptions: widget.serverOptions,
                      subtitleTracks: widget.subtitleTracks,
                      onQuality: _chooseQuality,
                      onServer: _chooseServer,
                      onSubtitle: _chooseSubtitle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleFillIntent extends Intent {
  const _ToggleFillIntent();
}

class _TopBar extends StatelessWidget {
  final String title;
  final bool fill;
  final VoidCallback onToggleFill;
  final Future<void> Function() onClose;

  const _TopBar({
    required this.title,
    required this.fill,
    required this.onToggleFill,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'إغلاق',
                onPressed: () => unawaited(onClose()),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onToggleFill,
                icon: Icon(fill ? Icons.fit_screen_rounded : Icons.aspect_ratio_rounded, color: Colors.white, size: 18),
                label: Text(fill ? 'Fill' : 'Fit', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionBar extends StatelessWidget {
  final String? currentQuality;
  final String? currentServer;
  final String? currentSubtitle;
  final List<Map<String, dynamic>> qualityOptions;
  final List<Map<String, dynamic>> serverOptions;
  final List<Map<String, dynamic>> subtitleTracks;
  final FutureOr<void> Function(Map<String, dynamic>) onQuality;
  final FutureOr<void> Function(Map<String, dynamic>) onServer;
  final FutureOr<void> Function(Map<String, dynamic>) onSubtitle;

  const _OptionBar({
    required this.currentQuality,
    required this.currentServer,
    required this.currentSubtitle,
    required this.qualityOptions,
    required this.serverOptions,
    required this.subtitleTracks,
    required this.onQuality,
    required this.onServer,
    required this.onSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          if (qualityOptions.isNotEmpty)
            _PopupOptionButton(
              icon: Icons.high_quality_rounded,
              label: currentQuality == null ? 'الجودة' : 'الجودة: $currentQuality',
              options: qualityOptions,
              onSelected: onQuality,
            ),
          if (serverOptions.isNotEmpty)
            _PopupOptionButton(
              icon: Icons.dns_rounded,
              label: currentServer == null ? 'السيرفر' : 'السيرفر: $currentServer',
              options: serverOptions,
              onSelected: onServer,
            ),
          if (subtitleTracks.isNotEmpty)
            _PopupOptionButton(
              icon: Icons.subtitles_rounded,
              label: currentSubtitle == null ? 'الترجمة' : 'الترجمة: $currentSubtitle',
              options: subtitleTracks,
              onSelected: onSubtitle,
            ),
        ],
      ),
    );
  }
}

class _PopupOptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Map<String, dynamic>> options;
  final FutureOr<void> Function(Map<String, dynamic>) onSelected;

  const _PopupOptionButton({
    required this.icon,
    required this.label,
    required this.options,
    required this.onSelected,
  });

  String _titleOf(Map<String, dynamic> item) {
    for (final key in const ['label', 'quality', 'server', 'title', 'name', 'language']) {
      final value = item[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value != 'null') return value;
    }
    return 'Option';
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: label,
      color: const Color(0xFF121212),
      onSelected: (index) {
        if (index >= 0 && index < options.length) unawaited(Future<void>.sync(() => onSelected(options[index])));
      },
      itemBuilder: (_) => [
        for (var i = 0; i < options.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Text(_titleOf(options[i]), style: const TextStyle(color: Colors.white)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            const Text('تعذّر تشغيل الرابط', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('إعادة المحاولة')),
          ],
        ),
      ),
    );
  }
}
