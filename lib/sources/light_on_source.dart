import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import '../pwa/io_compat.dart';
import '../pwa/isolate_compat.dart';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../pwa/path_provider_compat.dart';
import '../pwa/refresh_rate_compat.dart';
import '../pwa/video_thumbnail_compat.dart';

import '../background_download_bridge.dart';
import '../secure_strings.dart';
import '../native_security_guard.dart';
import '../universal_media_player.dart';
import '../pwa/file_image_compat.dart';

@pragma('vm:entry-point')
void lightOnSourceMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(NativeSecurityGuard.ensureClean());

  PaintingBinding.instance.imageCache.maximumSize = 160;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 96 << 20;

  try {
    RefreshRate.enable();
    RefreshRate.preferMax();
  } catch (_) {}

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const CinemaTmdbApp());
}

void main() => lightOnSourceMain();



ThemeData _lightOnCinemaTheme() {
  const primaryRed = Color(0xFFC62828);
  const appBg = Color(0xFF252526);
  const surfaceBase = Color(0xFF2D2D30);
  const surfaceAlt = Color(0xFF333337);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: primaryRed,
      secondary: primaryRed,
      surface: surfaceBase,
      surfaceContainerHighest: surfaceAlt,
      error: Color(0xFFE53935),
    ),
    scaffoldBackgroundColor: appBg,
    canvasColor: appBg,
    cardColor: surfaceBase,
    dividerColor: const Color(0xFF3A3A3D),
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primaryRed,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryRed,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryRed,
      foregroundColor: Colors.white,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryRed,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: surfaceBase,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Color(0x33C62828),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: WidgetStatePropertyAll(
        IconThemeData(color: Colors.white70),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: surfaceAlt,
      hintStyle: TextStyle(color: Colors.white54),
      prefixIconColor: Colors.white60,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFF3A3A3D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: primaryRed),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surfaceBase,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

/// Light On root used when this source is opened from the selector on Web/PWA.
///
/// Important: do not create a nested MaterialApp/Navigator here. Details and
/// player routes must be pushed on the same Navigator that opened Light On.
/// This keeps Android Chrome Back in the normal order:
/// player -> details -> current Light On tab.
class CinemaTmdbRoot extends StatelessWidget {
  const CinemaTmdbRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _lightOnCinemaTheme(),
      child: const AppShell(),
    );
  }
}

class CinemaTmdbApp extends StatelessWidget {
  const CinemaTmdbApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryRed = Color(0xFFC62828);
    const appBg = Color(0xFF252526);
    const surfaceBase = Color(0xFF2D2D30);
    const surfaceAlt = Color(0xFF333337);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cinema TMDB',
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: primaryRed,
          secondary: primaryRed,
          surface: surfaceBase,
          surfaceContainerHighest: surfaceAlt,
          error: Color(0xFFE53935),
        ),
        scaffoldBackgroundColor: appBg,
        canvasColor: appBg,
        cardColor: surfaceBase,
        dividerColor: const Color(0xFF3A3A3D),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
          foregroundColor: Colors.white,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primaryRed,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryRed,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: primaryRed,
          foregroundColor: Colors.white,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: primaryRed,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: surfaceBase,
          surfaceTintColor: Colors.transparent,
          indicatorColor: Color(0x33C62828),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          iconTheme: WidgetStatePropertyAll(
            IconThemeData(color: Colors.white70),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: surfaceAlt,
          hintStyle: TextStyle(color: Colors.white54),
          prefixIconColor: Colors.white60,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFF3A3A3D)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: primaryRed),
          ),
          contentPadding:
              EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: surfaceBase,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const AppShell(),
    );
  }
}

class CinematicBackground extends StatelessWidget {
  final Widget child;

  const CinematicBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF252526),
      child: child,
    );
  }
}

BoxDecoration cinematicPanelDecoration({double radius = 18}) {
  return BoxDecoration(
    color: const Color(0xFF2D2D30),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: const Color(0xFF3A3A3D)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  STREAMING SOURCES
// ══════════════════════════════════════════════════════════════════════════════

class StreamingSource {
  final String name;
  final String description;
  final Color color;
  final IconData icon;
  final String Function(int tmdbId, {int? season, int? episode}) buildUrl;

  const StreamingSource({
    required this.name,
    required this.description,
    required this.color,
    required this.icon,
    required this.buildUrl,
  });
}

final List<StreamingSource> kStreamingSources = [
  StreamingSource(
    name: 'vidfast',
    description: 'VidFast للأفلام والمسلسلات',
    color: const Color(0xFFB3202A),
    icon: Icons.play_circle_fill_rounded,
    buildUrl: (id, {season, episode}) {
      final params = <String, String>{
        'autoPlay': 'true',
        'title': 'false',
        'poster': 'true',
        'sub': 'ar',
        'theme': 'E50914',
      };
      if (season != null && episode != null) {
        params['nextButton'] = 'true';
        params['autoNext'] = 'true';
        return Uri(
          scheme: 'https',
          host: 'vidfast.pro',
          path: '/tv/$id/$season/$episode',
          queryParameters: params,
        ).toString();
      }
      return Uri(
        scheme: 'https',
        host: 'vidfast.pro',
        path: '/movie/$id',
        queryParameters: params,
      ).toString();
    },
  ),
];


Route<T> _buildDirectHiddenPlayerRoute<T>(Widget child) {
  return PageRouteBuilder<T>(
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, __, ___) => child,
  );
}

Route<T> _buildDirectDownloaderRoute<T>(Widget child) {
  return PageRouteBuilder<T>(
    opaque: false,
    barrierColor: null,
    barrierDismissible: false,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, __, ___) => IgnorePointer(
      ignoring: true,
      child: child,
    ),
  );
}

// ──────────────────────────────────────────────────────────────────────────
//  Player Sources Sheet
// ──────────────────────────────────────────────────────────────────────────


class PlayerSourcesSheet extends StatelessWidget {
  final int tmdbId;
  final String title;
  final MediaType mediaType;
  final int? season;
  final int? episode;
  final String? posterUrl;

  const PlayerSourcesSheet({
    super.key,
    required this.tmdbId,
    required this.title,
    required this.mediaType,
    this.season,
    this.episode,
    this.posterUrl,
  });

  static Future<void> show(
    BuildContext context, {
    required int tmdbId,
    required String title,
    required MediaType mediaType,
    int? season,
    int? episode,
    String? posterUrl,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2D2D30),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => PlayerSourcesSheet(
        tmdbId: tmdbId,
        title: title,
        mediaType: mediaType,
        season: season,
        episode: episode,
        posterUrl: posterUrl,
      ),
    );
  }

  Future<void> _openInternalPlayer(BuildContext context, String url) async {
    final sheetNavigator = Navigator.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    sheetNavigator.pop();

    await Future<void>.delayed(Duration.zero);

    if (kIsWeb) {
      final source = kStreamingSources.firstWhere(
        (e) => e.buildUrl(tmdbId, season: season, episode: episode) == url,
        orElse: () => kStreamingSources.first,
      );
      await openUniversalMediaPlayer(
        rootNavigator.context,
        url: url,
        title: title,
        pageUrl: url,
        serverOptions: <Map<String, dynamic>>[
          <String, dynamic>{
            'label': source.name,
            'embedUrl': url,
            'selected': 'true',
          },
        ],
      );
      return;
    }

    await rootNavigator.push(
      _buildDirectHiddenPlayerRoute(
        AsdPicsPlayer(
          initialUrl: url,
          headerTitle: title,
          launchHidden: true,
          downloadOnlyMode: false,
          autoDownloadPrompt: false,
          loadingPosterUrl: posterUrl,
          preferredSourceName: kStreamingSources.firstWhere(
            (e) => e.buildUrl(tmdbId, season: season, episode: episode) == url,
            orElse: () => kStreamingSources.first,
          ).name,
          tmdbId: tmdbId,
          mediaType: mediaType,
          season: season,
          episode: episode,
        ),
      ),
    );
  }

  void _copyUrl(BuildContext context, String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ تم نسخ الرابط'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showSubSourceApiSettings(BuildContext context) async {
    final controller = TextEditingController(text: await SubSourceApiKeyStore.savedKey());
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF2D2D30),
            title: const Text('تفعيل ترجمات SubSource'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'حتى تعمل الترجمة بدون استهلاك مفتاح مشترك، أنشئ مفتاح API مجاني من SubSource ثم الصقه هنا. المفتاح يبقى محفوظًا داخل جهازك فقط.',
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    SubSourceApiKeyStore.docsUrl,
                    style: const TextStyle(color: Color(0xFFFF8A80)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'SubSource API Key',
                      hintText: 'sk_...',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'بعد الحفظ: إذا الترجمة محفوظة سابقًا لن يطلب API مرة ثانية. إذا ملف الترجمة انحذف أو صار تالفًا، سيطلب ترجمة جديدة تلقائيًا.',
                    style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.45),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(const ClipboardData(text: SubSourceApiKeyStore.docsUrl));
                },
                child: const Text('نسخ رابط التسجيل'),
              ),
              TextButton(
                onPressed: () async {
                  await SubSourceApiKeyStore.clearKey();
                  controller.clear();
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('حذف المفتاح'),
              ),
              FilledButton(
                onPressed: () async {
                  await SubSourceApiKeyStore.saveKey(controller.text);
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEpisode = season != null && episode != null;
    final subtitle = isEpisode
        ? 'الموسم $season • الحلقة $episode'
        : (mediaType == MediaType.movie ? 'فيلم' : 'مسلسل');

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(
                  Icons.play_circle_fill_rounded,
                  color: Color(0xFFB3202A),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Divider(color: Colors.white10, height: 28),
            const Text(
              'اختر مصدر التشغيل',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white54,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            ...kStreamingSources.map((source) {
              final url = source.buildUrl(
                tmdbId,
                season: season,
                episode: episode,
              );
              return _SourceButton(
                source: source,
                onPlay: () => _openInternalPlayer(context, url),
                onCopy: () => _copyUrl(context, url),
              );
            }),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'TMDB ID: $tmdbId  •  يفتح داخل المشغل مباشرة',
                style: const TextStyle(
                  color: Colors.white30,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  final StreamingSource source;
  final VoidCallback onPlay;
  final VoidCallback onCopy;

  const _SourceButton({
    required this.source,
    required this.onPlay,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFC62828).withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC62828).withOpacity(0.22)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFC62828).withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(source.icon, color: const Color(0xFFC62828), size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      source.description,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onCopy,
                tooltip: 'نسخ الرابط',
                icon: const Icon(
                  Icons.copy_rounded,
                  size: 18,
                  color: Colors.white38,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFC62828),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 4),
                    Text(
                      'تشغيل',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ENUMS & CONFIG
// ══════════════════════════════════════════════════════════════════════════════

enum MediaType { movie, tv }

enum SortMode { smart, newest, oldest, ratingHigh, ratingLow, titleAZ }

extension SortModeLabel on SortMode {
  String get label {
    switch (this) {
      case SortMode.smart:
        return 'ذكي';
      case SortMode.newest:
        return 'الأحدث';
      case SortMode.oldest:
        return 'الأقدم';
      case SortMode.ratingHigh:
        return 'الأعلى تقييمًا';
      case SortMode.ratingLow:
        return 'الأقل تقييمًا';
      case SortMode.titleAZ:
        return 'أبجديًا';
    }
  }
}

extension _StringIfEmptyExtension on String {
  String ifEmpty(String fallback) {
    return trim().isEmpty ? fallback : this;
  }
}

class TmdbConfig {
  static final String tmdbApiKeyV3 = AppSecureText.s('RvUCCLXSehpNHojZywiIL1XpVOSk');
  static final String tmdbReadAccessToken = AppSecureText.s('QIj4YtoQgIWvJvHyDYGsni_lfng_6qTnP21MhQr2qGpW9n5DoXjS39PwXvgZoSesrJnPi8lU_x7-2RcJsRU4rpuEKSzIbw-_L7zmVutzK1_wh2KHrTbsf6J_rm6eA4Pdd9-BHqk4h5mzJvXVSUJsBrclvvjENXkEQmd_k3bUpkZ21Ss40wzEpOqQPph7lheHnbnGo6hz9RcDAvbyD9vbbDV-ygv6YQKUWKXoadAAZUCd8SjkyUGANstwjSa8JY3bHdej5BvRWV9Swzg1xwJNA-0KxrfhEC4HJyUj-kC9wgkVgmkZwgDogpu_LKIESO0');
  static final String contentLanguage = AppSecureText.s('GG3BwPU');
  static final String imageW500 = AppSecureText.s('ozzIrnvcH3bh43XDJ5FEw_Pmy9X5DeR99qBad-ZYQg');
  static final String imageW780 = AppSecureText.s('ozzIrnvcH3bh43XDJ5FEw_Pmy9X5DeR99qBad-RQQg');

  static bool get hasBearer =>
      tmdbReadAccessToken.trim().isNotEmpty &&
      !tmdbReadAccessToken.contains('PUT_TMDB');

  static bool get hasApiKey =>
      tmdbApiKeyV3.trim().isNotEmpty && !tmdbApiKeyV3.contains('PUT_TMDB');
}

// ══════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ══════════════════════════════════════════════════════════════════════════════

class MediaItem {
  final int id;
  final MediaType type;
  final String title;
  final String originalTitle;
  final String overview;
  final String posterPath;
  final String backdropPath;
  final List<int> genreIds;
  final double rating;
  final int voteCount;
  final double popularity;
  final DateTime? releaseDate;
  final String originalLanguage;
  final List<String> originCountries;

  const MediaItem({
    required this.id,
    required this.type,
    required this.title,
    required this.originalTitle,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.genreIds,
    required this.rating,
    required this.voteCount,
    required this.popularity,
    required this.releaseDate,
    required this.originalLanguage,
    required this.originCountries,
  });

  String get key => '${type.name}:$id';
  String get displayTitle {
    final preferred = originalTitle.trim();
    if (preferred.isNotEmpty) return preferred;
    return title.trim().isEmpty ? title : title.trim();
  }

  String get yearText =>
      releaseDate == null ? '—' : '${releaseDate!.year}';
  bool get hasVisibleRating => voteCount > 0 && rating > 0;
  String get posterUrl =>
      posterPath.isEmpty ? '' : '${TmdbConfig.imageW500}$posterPath';
  String get backdropUrl =>
      backdropPath.isEmpty ? '' : '${TmdbConfig.imageW780}$backdropPath';

  Map<String, dynamic> toStorageJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'originalTitle': originalTitle,
        'overview': overview,
        'posterPath': posterPath,
        'backdropPath': backdropPath,
        'genreIds': genreIds,
        'rating': rating,
        'voteCount': voteCount,
        'popularity': popularity,
        'releaseDate': releaseDate?.toIso8601String(),
        'originalLanguage': originalLanguage,
        'originCountries': originCountries,
      };

  factory MediaItem.fromStorageJson(Map<String, dynamic> json) => MediaItem(
        id: (json['id'] as num? ?? 0).toInt(),
        type: (json['type'] ?? 'movie').toString() == 'tv'
            ? MediaType.tv
            : MediaType.movie,
        title: (json['title'] ?? '').toString(),
        originalTitle: (json['originalTitle'] ?? json['title'] ?? '').toString(),
        overview: (json['overview'] ?? '').toString(),
        posterPath: (json['posterPath'] ?? '').toString(),
        backdropPath: (json['backdropPath'] ?? '').toString(),
        genreIds: ((json['genreIds'] ?? const []) as List)
            .map((e) => (e as num).toInt())
            .toList(),
        rating: ((json['rating'] ?? 0) as num).toDouble(),
        voteCount: (json['voteCount'] as num? ?? 0).toInt(),
        popularity: ((json['popularity'] ?? 0) as num).toDouble(),
        releaseDate: _parseDate((json['releaseDate'] ?? '').toString()),
        originalLanguage: (json['originalLanguage'] ?? '').toString(),
        originCountries: ((json['originCountries'] ?? const []) as List)
            .map((e) => e.toString())
            .toList(),
      );

  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  factory MediaItem.fromMovieJson(Map<String, dynamic> json) => MediaItem(
        id: (json['id'] as num? ?? 0).toInt(),
        type: MediaType.movie,
        title: (json['title'] ?? json['original_title'] ?? '').toString(),
        originalTitle:
            (json['original_title'] ?? json['title'] ?? '').toString(),
        overview: (json['overview'] ?? '').toString(),
        posterPath: (json['poster_path'] ?? '').toString(),
        backdropPath: (json['backdrop_path'] ?? '').toString(),
        genreIds: ((json['genre_ids'] ?? const []) as List)
            .map((e) => (e as num).toInt())
            .toList(),
        rating: ((json['vote_average'] ?? 0) as num).toDouble(),
        voteCount: (json['vote_count'] as num? ?? 0).toInt(),
        popularity: ((json['popularity'] ?? 0) as num).toDouble(),
        releaseDate: _parseDate((json['release_date'] ?? '').toString()),
        originalLanguage: (json['original_language'] ?? '').toString(),
        originCountries: const [],
      );

  factory MediaItem.fromTvJson(Map<String, dynamic> json) => MediaItem(
        id: (json['id'] as num? ?? 0).toInt(),
        type: MediaType.tv,
        title: (json['name'] ?? json['original_name'] ?? '').toString(),
        originalTitle:
            (json['original_name'] ?? json['name'] ?? '').toString(),
        overview: (json['overview'] ?? '').toString(),
        posterPath: (json['poster_path'] ?? '').toString(),
        backdropPath: (json['backdrop_path'] ?? '').toString(),
        genreIds: ((json['genre_ids'] ?? const []) as List)
            .map((e) => (e as num).toInt())
            .toList(),
        rating: ((json['vote_average'] ?? 0) as num).toDouble(),
        voteCount: (json['vote_count'] as num? ?? 0).toInt(),
        popularity: ((json['popularity'] ?? 0) as num).toDouble(),
        releaseDate: _parseDate((json['first_air_date'] ?? '').toString()),
        originalLanguage: (json['original_language'] ?? '').toString(),
        originCountries: ((json['origin_country'] ?? const []) as List)
            .map((e) => e.toString())
            .toList(),
      );

  factory MediaItem.fromTrendingJson(Map<String, dynamic> json) {
    final mediaType = (json['media_type'] ?? '').toString();
    if (mediaType == 'movie') return MediaItem.fromMovieJson(json);
    return MediaItem.fromTvJson(json);
  }
}

class CastMember {
  final String name;
  final String character;
  final String profilePath;

  const CastMember({
    required this.name,
    required this.character,
    required this.profilePath,
  });

  String get profileUrl =>
      profilePath.isEmpty ? '' : '${TmdbConfig.imageW500}$profilePath';
}

class SeasonSummary {
  final int seasonNumber;
  final String name;
  final String overview;
  final String posterPath;
  final int episodeCount;
  final DateTime? airDate;

  const SeasonSummary({
    required this.seasonNumber,
    required this.name,
    required this.overview,
    required this.posterPath,
    required this.episodeCount,
    required this.airDate,
  });

  bool get isSpecial => seasonNumber == 0;
  String get posterUrl =>
      posterPath.isEmpty ? '' : '${TmdbConfig.imageW500}$posterPath';

  factory SeasonSummary.fromJson(Map<String, dynamic> json) => SeasonSummary(
        seasonNumber: (json['season_number'] as num? ?? 0).toInt(),
        name: (json['name'] ?? '').toString(),
        overview: (json['overview'] ?? '').toString(),
        posterPath: (json['poster_path'] ?? '').toString(),
        episodeCount: (json['episode_count'] as num? ?? 0).toInt(),
        airDate: DateTime.tryParse((json['air_date'] ?? '').toString()),
      );
}

class EpisodeItem {
  final int episodeNumber;
  final String name;
  final String overview;
  final String stillPath;
  final double rating;
  final DateTime? airDate;
  final int? runtimeMinutes;

  const EpisodeItem({
    required this.episodeNumber,
    required this.name,
    required this.overview,
    required this.stillPath,
    required this.rating,
    required this.airDate,
    required this.runtimeMinutes,
  });

  String get stillUrl =>
      stillPath.isEmpty ? '' : '${TmdbConfig.imageW780}$stillPath';

  factory EpisodeItem.fromJson(Map<String, dynamic> json) => EpisodeItem(
        episodeNumber: (json['episode_number'] as num? ?? 0).toInt(),
        name: (json['name'] ?? '').toString(),
        overview: (json['overview'] ?? '').toString(),
        stillPath: (json['still_path'] ?? '').toString(),
        rating: ((json['vote_average'] ?? 0) as num).toDouble(),
        airDate: DateTime.tryParse((json['air_date'] ?? '').toString()),
        runtimeMinutes: (json['runtime'] as num?)?.toInt(),
      );
}

class SeasonDetails {
  final SeasonSummary season;
  final List<EpisodeItem> episodes;

  const SeasonDetails({required this.season, required this.episodes});
}

class MediaDetails {
  final MediaItem item;
  final List<String> genres;
  final List<CastMember> cast;
  final int? runtimeMinutes;
  final int? seasons;
  final int? episodes;
  final String? trailerKey;
  final List<SeasonSummary> seasonList;

  const MediaDetails({
    required this.item,
    required this.genres,
    required this.cast,
    required this.runtimeMinutes,
    required this.seasons,
    required this.episodes,
    required this.trailerKey,
    required this.seasonList,
  });
}

class GenreMaps {
  final Map<int, String> movie;
  final Map<int, String> tv;

  const GenreMaps({required this.movie, required this.tv});
}

class HomeData {
  final GenreMaps genres;
  final List<MediaItem> featured;
  final List<MediaItem> latest;
  final List<MediaItem> featuredSeries;
  final List<MediaItem> latestSeries;
  final List<MediaItem> featuredMovies;
  final List<MediaItem> topRatedMovies;
  final List<MediaItem> topRatedSeries;

  const HomeData({
    required this.genres,
    required this.featured,
    required this.latest,
    required this.featuredSeries,
    required this.latestSeries,
    required this.featuredMovies,
    required this.topRatedMovies,
    required this.topRatedSeries,
  });
}

enum HomeFetchProfile { preview, full }

class WatchHistoryStore {
  WatchHistoryStore._();

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/recent_watch_history.json');
  }

  static Future<List<MediaItem>> loadRecent() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const <MediaItem>[];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const <MediaItem>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <MediaItem>[];
      return decoded
          .whereType<Map>()
          .map((e) => MediaItem.fromStorageJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id != 0 && e.hasVisibleRating)
          .toList(growable: false);
    } catch (_) {
      return const <MediaItem>[];
    }
  }

  static Future<void> push(MediaItem item) async {
    try {
      final current = await loadRecent();
      final next = <MediaItem>[item, ...current.where((e) => e.key != item.key)]
          .take(24)
          .toList(growable: false);
      final file = await _file();
      await file.writeAsString(jsonEncode(next.map((e) => e.toStorageJson()).toList()));
    } catch (_) {}
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TMDB SERVICE
// ══════════════════════════════════════════════════════════════════════════════

class TmdbService {
  TmdbService._();
  static final TmdbService instance = TmdbService._();
  final HttpClient _client = HttpClient();
  final Dio _webClient = Dio(
    BaseOptions(
      responseType: ResponseType.plain,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (status) => status != null && status < 600,
    ),
  );

  static const Set<String> _blockedCountries = {
    'AE','SA','IQ','KW','QA','BH','OM','YE','JO','SY','LB','PS',
    'EG','SD','LY','TN','DZ','MA','MR','SO','DJ','KM',

    'IN','TR','KR','KP','JP','CN','TW','HK','MO','PH','TH',
  };

  static const Set<String> _blockedLanguages = {
    'ar','tr','ko','ja','zh','tl','fil','th',

    'hi','ta','te','ml','kn','bn','mr','gu','pa','or','as',
  };

  static const String _homeReleaseRegion = 'US';
  static const String _movieHomeReleaseTypes = '4|5|6';
  static const String _tvAllowedStatuses = '0|2|3|4';
  static const String _watchMonetizationTypes = 'flatrate|free|ads';
  static const double _minimumSeriesListRating = 6.0;
  static const int _tvHorrorPseudoGenreId = 27;

  static const Set<int> _blockedListOnlyMovieGenreIds = {
    10770,
  };

  String _withoutListOnlyMovieGenresParam() => _blockedListOnlyMovieGenreIds.join(',');

  String _minimumSeriesListRatingText() => _minimumSeriesListRating.toStringAsFixed(1);

  String _effectiveListMinRatingText(double requested) {
    final value = requested > 0 ? requested : 0;
    return value.toStringAsFixed(1);
  }

  String _effectiveSeriesListMinRatingText(double requested) {
    final value = requested > _minimumSeriesListRating ? requested : _minimumSeriesListRating;
    return value.toStringAsFixed(1);
  }

  static const Set<int> _blockedMovieGenreIds = {
    16,   // Animation
    99,   // Documentary
    10402 // Music
  };

  static const Set<int> _blockedTvGenreIds = {
    16, // Animation
    99, // Documentary
  };

  static const Set<int> _blockedSoftTvGenreIds = {
    10762, // Kids
    10764, // Reality
  };

  static const Set<String> _blockedExactNormalizedTitles = {
    'margo s got money troubles',
    'margos got money troubles',
    'salish jordan matter',
    'salish and jordan matter',
    'jury duty presents company retreat',
    'jury duty company retreat',
    'luka makan cinta',
    'made with love',
    'the ultimate baking championship',
    'ultimate baking championship',
  };

  static const List<String> _blockedSoftTitleMarkers = [
    'salish matter',
    'jordan matter',
    'salish jordan',
    'salish and jordan',
    'jury duty presents',
    'company retreat',
    'luka makan cinta',
    'baking championship',
    'ultimate baking championship',
    'bake off',
    'masterchef',
    'master chef',
    'top chef',
    'iron chef',
    'cooking competition',
    'baking competition',
    'cooking show',
    'baking show',
  ];

  static const Set<String> _blockedAlwaysListExactTitles = {
    'the ultimate baking championship',
    'ultimate baking championship',
  };

  static const List<String> _blockedAlwaysListTitleMarkers = [
    'baking championship',
    'ultimate baking championship',
    'bake off',
    'masterchef',
    'master chef',
    'top chef',
    'iron chef',
    'cooking competition',
    'baking competition',
    'cooking show',
    'baking show',
  ];


  static const List<String> _protectedMovieSearchQueries = [
    'Normal',
  ];

  static const List<String> _protectedSeriesSearchQueries = [
    'One Piece',
    "Stranger Things: Tales from '85",
    'Stranger Things Tales From 85',
  ];

  static const Set<String> _blockedSoftTvLanguages = {
    'id', // Indonesian
  };

  static const Set<String> _blockedSoftTvCountries = {
    'ID', // Indonesia
  };

  static const List<String> _blockedSoftTvGenreQuery = [
    '10762', // Kids
    '10764', // Reality
  ];

  static const List<String> _tvHorrorKeywordSearchTerms = [
    'horror',
    'supernatural horror',
    'haunted house',
    'ghost',
    'possession',
    'slasher',
  ];

  Future<String>? _tvHorrorKeywordIdsFuture;

  static const List<String> _blockedDiscoverKeywordSearchTerms = [
    'stand-up comedy',
    'stand up comedy',
    'comedy special',
    'stand-up special',
    'concert film',
    'concert movie',
    'live performance',
    'one man show',
    'one-person show',
    'music special',
    'onlyfans',
    'influencer',
    'youtuber',
    'youtube star',
    'social media influencer',
    'content creator',
    'family vlog',
    'cooking competition',
    'baking competition',
    'baking championship',
    'cooking show',
    'baking show',
    'cookery',
    'culinary competition',
  ];

  static const List<String> _blockedKeywordMarkers = [
    'stand-up',
    'stand up',
    'comedy special',
    'stand-up special',
    'concert film',
    'concert movie',
    'concert',
    'live performance',
    'music special',
    'one man show',
    'one-person show',
    'solo performance',
    'tour',
    'onlyfans',
    'influencer',
    'youtuber',
    'youtube star',
    'youtube personality',
    'social media influencer',
    'content creator',
    'family vlog',
    'vlogger',
    'cooking competition',
    'baking competition',
    'baking championship',
    'cooking show',
    'baking show',
    'cookery',
    'culinary competition',
  ];

  final Map<String, bool> _movieHomeReleaseCache = <String, bool>{};
  final Map<String, bool> _watchAvailabilityCache = <String, bool>{};
  final Map<String, bool> _actualAvailabilityCache = <String, bool>{};
  final Map<String, bool> _blockedKeywordMatchCache = <String, bool>{};
  final Map<String, int?> _keywordIdSearchCache = <String, int?>{};
  Future<String>? _blockedDiscoverKeywordIdsFuture;
  final Map<HomeFetchProfile, HomeData> _homeCacheByProfile = <HomeFetchProfile, HomeData>{};
  final Map<HomeFetchProfile, DateTime> _homeCacheAtByProfile = <HomeFetchProfile, DateTime>{};
  static const Duration _homeCacheTtl = Duration(minutes: 15);

  Map<String, String> _headers() {
    final h = <String, String>{'accept': 'application/json'};
    if (TmdbConfig.hasBearer) {
      h['Authorization'] = 'Bearer ${TmdbConfig.tmdbReadAccessToken}';
    }
    return h;
  }

  Uri _buildUri(String path, [Map<String, String>? query]) {
    final q = <String, String>{...(query ?? {})};
    if (!TmdbConfig.hasBearer && TmdbConfig.hasApiKey) {
      q['api_key'] = TmdbConfig.tmdbApiKeyV3;
    }
    return Uri.https('api.themoviedb.org', '/3/$path', q);
  }

  Future<dynamic> _getJson(String path, [Map<String, String>? query]) async {
    if (!TmdbConfig.hasBearer && !TmdbConfig.hasApiKey) {
      throw Exception('ضع مفاتيح TMDB داخل TmdbConfig أولاً.');
    }
    final uri = _buildUri(path, query);
    if (kIsWeb) {
      final response = await _webClient.getUri<String>(
        uri,
        options: Options(headers: _headers()),
      );
      final statusCode = response.statusCode ?? 0;
      final body = response.data?.toString() ?? '';
      if (statusCode < 200 || statusCode >= 300) {
        throw Exception('TMDB $statusCode: $body');
      }
      return await Isolate.run<dynamic>(() => jsonDecode(body));
    }

    final request = await _client.getUrl(uri);
    final headers = _headers();
    headers.forEach(request.headers.set);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('TMDB ${response.statusCode}: $body');
    }
    return await Isolate.run<dynamic>(() => jsonDecode(body));
  }

  String _normalizeTitleForBlock(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r"[^a-z0-9]+"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _hasBlockedExactOrMarkerTitle(MediaItem item) {
    final titles = <String>{
      _normalizeTitleForBlock(item.title),
      _normalizeTitleForBlock(item.originalTitle),
      _normalizeTitleForBlock(item.displayTitle),
    }..removeWhere((e) => e.isEmpty);

    for (final title in titles) {
      if (_blockedExactNormalizedTitles.contains(title)) return true;
      for (final marker in _blockedSoftTitleMarkers) {
        if (title.contains(marker)) return true;
      }
    }
    return false;
  }

  bool _hasBlockedAlwaysListTitle(MediaItem item) {
    final titles = <String>{
      _normalizeTitleForBlock(item.title),
      _normalizeTitleForBlock(item.originalTitle),
      _normalizeTitleForBlock(item.displayTitle),
    }..removeWhere((e) => e.isEmpty);

    for (final title in titles) {
      if (_blockedAlwaysListExactTitles.contains(title)) return true;
      for (final marker in _blockedAlwaysListTitleMarkers) {
        if (title.contains(marker)) return true;
      }
    }
    return false;
  }

  Set<String> _normalizedTitleSet(MediaItem item) {
    return <String>{
      _normalizeTitleForBlock(item.title),
      _normalizeTitleForBlock(item.originalTitle),
      _normalizeTitleForBlock(item.displayTitle),
    }..removeWhere((e) => e.isEmpty);
  }

  bool _isNormalMovieCandidate(MediaItem item) {
    if (item.type != MediaType.movie) return false;
    final titles = _normalizedTitleSet(item);
    return titles.contains('normal');
  }

  bool _isOnePieceLiveActionCandidate(MediaItem item) {
    if (item.type != MediaType.tv) return false;
    final titles = _normalizedTitleSet(item);
    if (!titles.contains('one piece')) return false;

    if (item.genreIds.contains(16)) return false;
    final lang = item.originalLanguage.trim().toLowerCase();
    final countries = item.originCountries.map((e) => e.trim().toUpperCase()).toSet();
    return lang == 'en' || countries.contains('US');
  }

  bool _isStrangerThingsTalesFrom85Candidate(MediaItem item) {
    if (item.type != MediaType.tv) return false;
    final titles = _normalizedTitleSet(item);
    return titles.any((title) {
      return title == 'stranger things tales from 85' ||
          (title.contains('stranger things') && title.contains('tales from'));
    });
  }

  bool _isProtectedVisibleItem(MediaItem item) {
    return _isNormalMovieCandidate(item) ||
        _isOnePieceLiveActionCandidate(item) ||
        _isStrangerThingsTalesFrom85Candidate(item);
  }

  bool _isBlockedSoftTvItem(MediaItem item) {
    if (item.type != MediaType.tv) return false;
    if (_isProtectedVisibleItem(item)) return false;
    if (_hasBlockedExactOrMarkerTitle(item)) return true;

    final softLang = item.originalLanguage.trim().toLowerCase();
    if (_blockedSoftTvLanguages.contains(softLang)) return true;

    final hasSoftCountry = item.originCountries.any((country) {
      final code = country.trim().toUpperCase();
      return _blockedSoftTvCountries.contains(code);
    });
    if (hasSoftCountry) return true;

    final hasKids = item.genreIds.any(_blockedSoftTvGenreIds.contains) && item.genreIds.contains(10762);
    final hasReality = item.genreIds.any(_blockedSoftTvGenreIds.contains) && item.genreIds.contains(10764);

    if (hasKids && hasReality) return true;
    if ((hasKids || hasReality) && item.voteCount < 50 && item.rating >= 9.0) {
      return true;
    }

    return false;
  }

  String _withoutSoftTvGenresParam() => _blockedSoftTvGenreQuery.join(',');

  bool _hasBlockedCountry(MediaItem item) => item.originCountries.any((c) {
        final code = c.trim().toUpperCase();
        return _blockedCountries.contains(code);
      });

  bool _hasBlockedGenre(MediaItem item) {
    final blocked = item.type == MediaType.movie
        ? _blockedMovieGenreIds
        : _blockedTvGenreIds;
    return item.genreIds.any(blocked.contains);
  }

  bool _isAllowed(MediaItem item) {
    if (item.id == 0) return false;
    if (_isNormalMovieCandidate(item)) return true;
    final isProtected = _isProtectedVisibleItem(item);
    if (!isProtected && !item.hasVisibleRating) return false;
    if (item.posterPath.isEmpty) return false;

    final releaseDate = item.releaseDate;
    if (releaseDate == null) return false;
    final today = DateTime.now();
    final releaseDay = DateTime(releaseDate.year, releaseDate.month, releaseDate.day);
    final currentDay = DateTime(today.year, today.month, today.day);
    if (releaseDay.isAfter(currentDay)) return false;

    final lang = item.originalLanguage.trim().toLowerCase();
    if (!isProtected && _blockedLanguages.contains(lang)) return false;
    if (!isProtected && _hasBlockedCountry(item)) return false;
    if (!isProtected && _hasBlockedGenre(item)) return false;
    return true;
  }


  bool _isHardAllowedForDetails(MediaItem item) {
    if (item.id == 0) return false;
    if (_isNormalMovieCandidate(item)) return true;
    if (item.posterPath.isEmpty) return false;

    final releaseDate = item.releaseDate;
    if (releaseDate == null) return false;
    final today = DateTime.now();
    final releaseDay = DateTime(releaseDate.year, releaseDate.month, releaseDate.day);
    final currentDay = DateTime(today.year, today.month, today.day);
    if (releaseDay.isAfter(currentDay)) return false;

    final lang = item.originalLanguage.trim().toLowerCase();
    if (_blockedLanguages.contains(lang)) return false;
    if (_hasBlockedCountry(item)) return false;
    if (_hasBlockedGenre(item)) return false;
    return true;
  }

  bool _canRelaxDetailsFilter(MediaItem item) {
    if (item.type != MediaType.movie) return false;
    if (!_isHardAllowedForDetails(item)) return false;

    final lang = item.originalLanguage.trim().toLowerCase();
    if (lang != 'en') return false;

    if (item.originCountries.isEmpty) return true;
    const safeMovieRegions = {'US', 'GB', 'CA', 'AU', 'NZ', 'IE'};
    return item.originCountries.any((country) {
      return safeMovieRegions.contains(country.trim().toUpperCase());
    });
  }

  List<MediaItem> _dedupeAndFilter(
    Iterable<MediaItem> items, {
    bool blockSoftTvItems = true,
    bool enforceMinimumListRating = true,
    bool blockListOnlyMovieGenres = true,
  }) {
    final map = <String, MediaItem>{};
    for (final item in items) {
      if (!_isAllowed(item)) continue;
      if (_hasBlockedAlwaysListTitle(item)) continue;
      if (blockListOnlyMovieGenres &&
          item.type == MediaType.movie &&
          item.genreIds.any(_blockedListOnlyMovieGenreIds.contains)) {
        continue;
      }
      final isProtected = _isProtectedVisibleItem(item);
      if (enforceMinimumListRating && !isProtected && item.type == MediaType.tv && item.rating < _minimumSeriesListRating) {
        continue;
      }
      if (blockSoftTvItems && _isBlockedSoftTvItem(item)) continue;
      map[item.key] = item;
    }
    return map.values.toList();
  }

  String _normalizeKeywordText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _matchesBlockedKeywordName(String raw) {
    final value = _normalizeKeywordText(raw);
    if (value.isEmpty) return false;
    for (final marker in _blockedKeywordMarkers) {
      if (value.contains(marker)) return true;
    }
    return false;
  }

  Future<int?> _searchKeywordId(String term) async {
    final normalized = _normalizeKeywordText(term);
    final cached = _keywordIdSearchCache[normalized];
    if (cached != null || _keywordIdSearchCache.containsKey(normalized)) {
      return cached;
    }

    try {
      final data = await _getJson('search/keyword', {
        'query': term,
        'page': '1',
      });
      final results = (data['results'] as List? ?? const <dynamic>[]);
      int? fallback;
      for (final raw in results) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final id = (map['id'] as num?)?.toInt();
        final name = _normalizeKeywordText((map['name'] ?? '').toString());
        if (id == null || name.isEmpty) continue;
        fallback ??= id;
        if (name == normalized) {
          _keywordIdSearchCache[normalized] = id;
          return id;
        }
      }
      _keywordIdSearchCache[normalized] = fallback;
      return fallback;
    } catch (_) {
      _keywordIdSearchCache[normalized] = null;
      return null;
    }
  }

  Future<String> _discoverBlockedKeywordIds() {
    final inFlight = _blockedDiscoverKeywordIdsFuture;
    if (inFlight != null) return inFlight;
    final future = (() async {
      final ids = <int>{};
      for (final term in _blockedDiscoverKeywordSearchTerms) {
        final id = await _searchKeywordId(term);
        if (id != null) ids.add(id);
      }
      return ids.isEmpty ? '' : ids.join('|');
    })();
    _blockedDiscoverKeywordIdsFuture = future;
    return future;
  }

  Future<String> _discoverTvHorrorKeywordIds() {
    final inFlight = _tvHorrorKeywordIdsFuture;
    if (inFlight != null) return inFlight;
    final future = (() async {
      final ids = <int>{};
      for (final term in _tvHorrorKeywordSearchTerms) {
        final id = await _searchKeywordId(term);
        if (id != null) ids.add(id);
      }
      return ids.isEmpty ? '' : ids.join('|');
    })();
    _tvHorrorKeywordIdsFuture = future;
    return future;
  }

  Future<bool> _hasBlockedKeywords(MediaItem item) async {
    final cached = _blockedKeywordMatchCache[item.key];
    if (cached != null) return cached;

    try {
      final path = item.type == MediaType.movie
          ? 'movie/${item.id}/keywords'
          : 'tv/${item.id}/keywords';
      final data = await _getJson(path);
      final rawList = (data['keywords'] as List?) ?? (data['results'] as List?) ?? const <dynamic>[];
      for (final raw in rawList) {
        if (raw is! Map) continue;
        final name = (Map<String, dynamic>.from(raw)['name'] ?? '').toString();
        if (_matchesBlockedKeywordName(name)) {
          _blockedKeywordMatchCache[item.key] = true;
          return true;
        }
      }
    } catch (_) {}

    _blockedKeywordMatchCache[item.key] = false;
    return false;
  }

  DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

  bool _regionHasSupportedWatchMonetization(Map<String, dynamic> regionData) {
    for (final key in const ['flatrate', 'free', 'ads']) {
      final bucket = regionData[key];
      if (bucket is List && bucket.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _hasWatchAvailability(MediaItem item) async {
    final cached = _watchAvailabilityCache[item.key];
    if (cached != null) return cached;

    try {
      final path = item.type == MediaType.movie
          ? 'movie/${item.id}/watch/providers'
          : 'tv/${item.id}/watch/providers';
      final data = await _getJson(path);
      final results = data['results'];
      if (results is Map) {
        final regionResults = Map<String, dynamic>.from(results);
        final primaryRegion = regionResults[_homeReleaseRegion];
        if (primaryRegion is Map &&
            _regionHasSupportedWatchMonetization(
              Map<String, dynamic>.from(primaryRegion),
            )) {
          _watchAvailabilityCache[item.key] = true;
          return true;
        }
        for (final value in regionResults.values) {
          if (value is Map &&
              _regionHasSupportedWatchMonetization(
                Map<String, dynamic>.from(value),
              )) {
            _watchAvailabilityCache[item.key] = true;
            return true;
          }
        }
      }
    } catch (_) {}

    _watchAvailabilityCache[item.key] = false;
    return false;
  }

  Future<bool> _hasMovieHomeRelease(MediaItem item) async {
    if (item.type != MediaType.movie) return false;
    final cached = _movieHomeReleaseCache[item.key];
    if (cached != null) return cached;

    try {
      final data = await _getJson('movie/${item.id}/release_dates');
      final results = (data['results'] as List? ?? const <dynamic>[]);
      final today = _dateOnly(DateTime.now());

      bool hasValidHomeReleaseInEntry(Map<String, dynamic> entry) {
        final releaseDates = (entry['release_dates'] as List? ?? const <dynamic>[]);
        for (final raw in releaseDates) {
          if (raw is! Map) continue;
          final release = Map<String, dynamic>.from(raw);
          final type = (release['type'] as num?)?.toInt() ?? -1;
          if (type != 4 && type != 5 && type != 6) continue;
          final date = DateTime.tryParse((release['release_date'] ?? '').toString());
          if (date == null) continue;
          if (!_dateOnly(date).isAfter(today)) {
            return true;
          }
        }
        return false;
      }

      for (final raw in results) {
        if (raw is! Map) continue;
        final entry = Map<String, dynamic>.from(raw);
        final region = (entry['iso_3166_1'] ?? '').toString().toUpperCase();
        if (region == _homeReleaseRegion && hasValidHomeReleaseInEntry(entry)) {
          _movieHomeReleaseCache[item.key] = true;
          return true;
        }
      }

      for (final raw in results) {
        if (raw is! Map) continue;
        final entry = Map<String, dynamic>.from(raw);
        if (hasValidHomeReleaseInEntry(entry)) {
          _movieHomeReleaseCache[item.key] = true;
          return true;
        }
      }
    } catch (_) {}

    _movieHomeReleaseCache[item.key] = false;
    return false;
  }

  Future<bool> _isActuallyAvailable(MediaItem item) async {
    final cached = _actualAvailabilityCache[item.key];
    if (cached != null) return cached;
    if (_isNormalMovieCandidate(item)) {
      _actualAvailabilityCache[item.key] = true;
      return true;
    }
    if (!_isAllowed(item)) {
      _actualAvailabilityCache[item.key] = false;
      return false;
    }
    if (!_isProtectedVisibleItem(item) && await _hasBlockedKeywords(item)) {
      _actualAvailabilityCache[item.key] = false;
      return false;
    }

    final available = item.type == MediaType.movie
        ? ((await _hasMovieHomeRelease(item)) || (await _hasWatchAvailability(item)))
        : await _hasWatchAvailability(item);

    _actualAvailabilityCache[item.key] = available;
    return available;
  }

  Future<List<MediaItem>> _filterActuallyAvailable(
    Iterable<MediaItem> items, {
    int? maxToCheck,
    bool blockSoftTvItems = true,
    bool enforceMinimumListRating = true,
    bool blockListOnlyMovieGenres = true,
  }) async {
    final candidates = _dedupeAndFilter(
      items,
      blockSoftTvItems: blockSoftTvItems,
      enforceMinimumListRating: enforceMinimumListRating,
      blockListOnlyMovieGenres: blockListOnlyMovieGenres,
    ).toList(growable: false);
    final pool = maxToCheck != null && maxToCheck > 0 && candidates.length > maxToCheck
        ? candidates.take(maxToCheck).toList(growable: false)
        : candidates;
    if (pool.isEmpty) return const <MediaItem>[];

    final checks = await Future.wait(pool.map(_isActuallyAvailable));
    final out = <MediaItem>[];
    for (int i = 0; i < pool.length; i++) {
      if (checks[i]) out.add(pool[i]);
    }
    return out;
  }

  List<MediaItem> _prependUniqueItems(
    Iterable<MediaItem> pinned,
    Iterable<MediaItem> items,
  ) {
    final seen = <String>{};
    final out = <MediaItem>[];
    for (final item in [...pinned, ...items]) {
      if (seen.add(item.key)) out.add(item);
    }
    return out;
  }

  MediaItem _mergeMediaItemVisuals(MediaItem base, MediaItem fallback) {
    return MediaItem(
      id: base.id,
      type: base.type,
      title: base.title.trim().isNotEmpty ? base.title : fallback.title,
      originalTitle: base.originalTitle.trim().isNotEmpty
          ? base.originalTitle
          : fallback.originalTitle,
      overview: base.overview.trim().isNotEmpty ? base.overview : fallback.overview,
      posterPath: base.posterPath.trim().isNotEmpty
          ? base.posterPath
          : fallback.posterPath,
      backdropPath: base.backdropPath.trim().isNotEmpty
          ? base.backdropPath
          : fallback.backdropPath,
      genreIds: base.genreIds.isNotEmpty ? base.genreIds : fallback.genreIds,
      rating: base.rating > 0 ? base.rating : fallback.rating,
      voteCount: base.voteCount > 0 ? base.voteCount : fallback.voteCount,
      popularity: base.popularity > 0 ? base.popularity : fallback.popularity,
      releaseDate: base.releaseDate ?? fallback.releaseDate,
      originalLanguage: base.originalLanguage.trim().isNotEmpty
          ? base.originalLanguage
          : fallback.originalLanguage,
      originCountries: base.originCountries.isNotEmpty
          ? base.originCountries
          : fallback.originCountries,
    );
  }

  Future<MediaItem> _enrichMovieItemVisuals(MediaItem item) async {
    if (item.type != MediaType.movie) return item;
    if (item.posterPath.trim().isNotEmpty && item.backdropPath.trim().isNotEmpty) {
      return item;
    }

    var current = item;
    for (final language in <String>[TmdbConfig.contentLanguage, 'en-US', '']) {
      try {
        final query = <String, String>{};
        if (language.trim().isNotEmpty) query['language'] = language;
        final data = await _getJson('movie/${item.id}', query);
        if (data is! Map) continue;
        final details = MediaItem.fromMovieJson(Map<String, dynamic>.from(data));
        current = _mergeMediaItemVisuals(current, details);
        if (current.posterPath.trim().isNotEmpty &&
            current.backdropPath.trim().isNotEmpty) {
          break;
        }
      } catch (_) {}
    }
    return current;
  }

  Future<List<MediaItem>> _fetchProtectedMovieItems() async {
    final collected = <MediaItem>[];
    for (final query in _protectedMovieSearchQueries) {
      for (final language in <String>[TmdbConfig.contentLanguage, 'en-US']) {
        try {
          final data = await _getJson('search/movie', {
            'language': language,
            'include_adult': 'false',
            'query': query,
            'page': '1',
          });
          final results = (data['results'] as List? ?? const <dynamic>[]);
          for (final raw in results.take(12)) {
            if (raw is! Map) continue;
            final item = MediaItem.fromMovieJson(Map<String, dynamic>.from(raw));
            if (!_isNormalMovieCandidate(item)) continue;
            collected.add(await _enrichMovieItemVisuals(item));
          }
        } catch (_) {}
      }
    }
    return _dedupeAndFilter(
      collected,
      blockSoftTvItems: false,
      enforceMinimumListRating: false,
      blockListOnlyMovieGenres: false,
    );
  }


  List<MediaItem> _latestProtectedMovieItemsForHome(List<MediaItem> items) {
    final normalItems = items.where(_isNormalMovieCandidate).toList();
    final otherItems = items.where((item) => !_isNormalMovieCandidate(item)).toList();
    if (normalItems.isEmpty) return items;

    normalItems.sort((a, b) {
      final dateCompare = (b.releaseDate ?? DateTime(1900))
          .compareTo(a.releaseDate ?? DateTime(1900));
      if (dateCompare != 0) return dateCompare;
      final popularityCompare = b.popularity.compareTo(a.popularity);
      if (popularityCompare != 0) return popularityCompare;
      return b.id.compareTo(a.id);
    });

    final latestYear = normalItems.first.releaseDate?.year;
    final latestNormalItems = latestYear == null
        ? <MediaItem>[normalItems.first]
        : normalItems
            .where((item) => item.releaseDate?.year == latestYear)
            .toList(growable: false);

    return _prependUniqueItems([...latestNormalItems, ...otherItems], const <MediaItem>[]);
  }

  Iterable<MediaItem> _keepOnlyLatestNormalMoviesForHome(
    Iterable<MediaItem> items,
    Set<String> allowedNormalKeys,
  ) {
    if (allowedNormalKeys.isEmpty) return items;
    return items.where((item) {
      if (!_isNormalMovieCandidate(item)) return true;
      return allowedNormalKeys.contains(item.key);
    });
  }

  Future<List<MediaItem>> _fetchProtectedSeriesItems() async {
    final collected = <MediaItem>[];
    for (final query in _protectedSeriesSearchQueries) {
      try {
        final data = await _getJson('search/tv', {
          'language': TmdbConfig.contentLanguage,
          'include_adult': 'false',
          'query': query,
          'page': '1',
        });
        final results = (data['results'] as List? ?? const <dynamic>[]);
        for (final raw in results) {
          if (raw is! Map) continue;
          final item = MediaItem.fromTvJson(Map<String, dynamic>.from(raw));
          if (_isProtectedVisibleItem(item)) collected.add(item);
        }
      } catch (_) {}
    }
    return _dedupeAndFilter(
      collected,
      blockSoftTvItems: false,
      enforceMinimumListRating: false,
    );
  }

  Future<List<dynamic>> _fetchPagedResults(
    String path,
    Map<String, String> query, {
    int pages = 2,
  }) async {
    final futures = <Future<dynamic>>[];
    for (int page = 1; page <= pages; page++) {
      futures.add(_getJson(path, {...query, 'page': '$page'}));
    }
    final responses = await Future.wait(futures);
    return responses
        .expand((data) => ((data['results'] as List?) ?? const <dynamic>[]))
        .toList(growable: false);
  }

  List<MediaItem> _movieItemsFromResults(Iterable<dynamic> results) {
    return _dedupeAndFilter(
      results.map(
        (e) => MediaItem.fromMovieJson(Map<String, dynamic>.from(e as Map)),
      ),
    );
  }

  List<MediaItem> _tvItemsFromResults(Iterable<dynamic> results) {
    return _dedupeAndFilter(
      results.map(
        (e) => MediaItem.fromTvJson(Map<String, dynamic>.from(e as Map)),
      ),
    );
  }

  double _featuredSeriesScore(
    MediaItem item, {
    required DateTime now,
    required bool isAiring,
    required bool isAiringToday,
    required bool isRecentLaunch,
    required bool hasFreshEpisodeWindow,
  }) {
    final releaseDate = item.releaseDate;
    final daysSinceLaunch =
        releaseDate == null ? 9999 : now.difference(releaseDate).inDays;

    final freshnessBoost = daysSinceLaunch <= 30
        ? 82.0
        : daysSinceLaunch <= 90
            ? 60.0
            : daysSinceLaunch <= 180
                ? 38.0
                : daysSinceLaunch <= 365
                    ? 18.0
                    : 0.0;

    final activityBoost = isAiringToday
        ? 120.0
        : isAiring
            ? 92.0
            : hasFreshEpisodeWindow
                ? 72.0
                : 0.0;

    final launchBoost = isRecentLaunch ? 44.0 : 0.0;
    final popularityScore = math.min(item.popularity, 220).toDouble();
    final ratingScore = item.rating * 12.5;

    return activityBoost +
        launchBoost +
        freshnessBoost +
        popularityScore +
        ratingScore;
  }

  Future<List<MediaItem>> _collectPagedItemsUntil(
    String path,
    Map<String, String> query, {
    required MediaType mediaType,
    required int targetCount,
    int maxPages = 30,
    int chunkSize = 3,
  }) async {
    final collected = <MediaItem>[];
    final seen = <String>{};

    for (
      int startPage = 1;
      startPage <= maxPages && collected.length < targetCount;
      startPage += chunkSize
    ) {
      final endPage = math.min(maxPages, startPage + chunkSize - 1);
      final futures = <Future<dynamic>>[];
      for (int page = startPage; page <= endPage; page++) {
        futures.add(_getJson(path, {...query, 'page': '$page'}));
      }

      final responses = await Future.wait(futures);
      final rawBatch = <dynamic>[];
      var reachedRealEnd = false;

      for (int i = 0; i < responses.length; i++) {
        final data = responses[i] as Map<String, dynamic>;
        final results = (data['results'] as List?) ?? const <dynamic>[];
        rawBatch.addAll(results);
        final totalPages = (data['total_pages'] as num?)?.toInt() ?? maxPages;
        final currentPage = startPage + i;
        if (currentPage >= totalPages) {
          reachedRealEnd = true;
        }
      }

      if (rawBatch.isEmpty) {
        break;
      }

      final pageItems = mediaType == MediaType.movie
          ? _movieItemsFromResults(rawBatch)
          : _tvItemsFromResults(rawBatch);

      for (final item in pageItems) {
        if (seen.add(item.key)) {
          collected.add(item);
        }
      }

      if (reachedRealEnd) {
        break;
      }
    }

    return collected;
  }

  Future<List<MediaItem>> _collectMovieBackfillByReleaseWindows(
    Map<String, String> baseQuery, {
    required int targetCount,
    int oldestYear = 1950,
    int yearsPerWindow = 2,
    int maxPagesPerWindow = 14,
  }) async {
    final collected = <MediaItem>[];
    final seen = <String>{};
    final now = DateTime.now();

    for (
      int windowEndYear = now.year;
      windowEndYear >= oldestYear && collected.length < targetCount;
      windowEndYear -= yearsPerWindow
    ) {
      final windowStartYear = math.max(oldestYear, windowEndYear - yearsPerWindow + 1);
      final windowStart = DateTime(windowStartYear, 1, 1);
      final windowEnd = windowEndYear == now.year
          ? now
          : DateTime(windowEndYear, 12, 31);

      final items = await _collectPagedItemsUntil(
        'discover/movie',
        {
          ...baseQuery,
          'primary_release_date.gte': _date(windowStart),
          'primary_release_date.lte': _date(windowEnd),
        },
        mediaType: MediaType.movie,
        targetCount: targetCount - collected.length,
        maxPages: maxPagesPerWindow,
        chunkSize: 3,
      );

      if (items.isEmpty) {
        continue;
      }

      for (final item in items) {
        if (seen.add(item.key)) {
          collected.add(item);
          if (collected.length >= targetCount) {
            break;
          }
        }
      }
    }

    return collected;
  }

  List<MediaItem> _sortByNewestThenPopularity(Iterable<MediaItem> items) {
    final out = items.toList(growable: false);
    out.sort((a, b) {
      final aDate = a.releaseDate ?? DateTime(1900);
      final bDate = b.releaseDate ?? DateTime(1900);
      final dateCompare = bDate.compareTo(aDate);
      if (dateCompare != 0) return dateCompare;
      final ratingCompare = b.rating.compareTo(a.rating);
      if (ratingCompare != 0) return ratingCompare;
      return b.popularity.compareTo(a.popularity);
    });
    return out;
  }

  Future<GenreMaps> fetchGenres() async {
    final results = await Future.wait([
      _getJson('genre/movie/list', {'language': 'ar'}),
      _getJson('genre/tv/list', {'language': 'ar'}),
    ]);
    final movieMap = <int, String>{};
    final tvMap = <int, String>{};
    for (final g in (results[0]['genres'] as List)) {
      movieMap[(g['id'] as num).toInt()] = (g['name'] ?? '').toString();
    }
    for (final blockedId in _blockedListOnlyMovieGenreIds) {
      movieMap.remove(blockedId);
    }
    for (final g in (results[1]['genres'] as List)) {
      tvMap[(g['id'] as num).toInt()] = (g['name'] ?? '').toString();
    }
    tvMap.putIfAbsent(_tvHorrorPseudoGenreId, () => 'رعب');
    return GenreMaps(movie: movieMap, tv: tvMap);
  }

  Future<HomeData> fetchHome({
    bool forceRefresh = false,
    HomeFetchProfile profile = HomeFetchProfile.full,
  }) async {
    final now = DateTime.now();
    final cached = _homeCacheByProfile[profile];
    final cachedAt = _homeCacheAtByProfile[profile];
    if (!forceRefresh && cached != null && cachedAt != null) {
      final age = now.difference(cachedAt);
      if (age <= _homeCacheTtl) {
        return cached;
      }
    }

    final blockedKeywordIds = await _discoverBlockedKeywordIds();
    final isPreview = profile == HomeFetchProfile.preview;
    final featuredShelfSize = isPreview ? 8 : 20;
    final movieShelfSize = isPreview ? 40 : 500;
    final seriesShelfSize = isPreview ? 40 : 500;
    final moviePoolSize = isPreview ? 120 : movieShelfSize + 180;
    final seriesPoolSize = isPreview ? 120 : seriesShelfSize + 180;
    final recentLaunchCutoff = now.subtract(const Duration(days: 548)); // ~18 months
    final activeWindowStart = now.subtract(const Duration(days: 28));
    final activeWindowEnd = now.add(const Duration(days: 42));

    final genresFuture = fetchGenres();
    final trendingFuture = _getJson(
      'trending/all/week',
      {'language': TmdbConfig.contentLanguage, 'page': '1'},
    );
    final latestMoviesFuture = _collectPagedItemsUntil(
      'discover/movie',
      {
        'language': TmdbConfig.contentLanguage,
        'sort_by': 'primary_release_date.desc',
        'include_adult': 'false',
        'include_video': 'false',
        'region': _homeReleaseRegion,
        'with_release_type': _movieHomeReleaseTypes,
        'watch_region': _homeReleaseRegion,
        'with_watch_monetization_types': _watchMonetizationTypes,
        'without_genres': _withoutListOnlyMovieGenresParam(),
        'release_date.lte': _date(now),
        'primary_release_date.lte': _date(now),
        'vote_count.gte': '10',
        if (blockedKeywordIds.isNotEmpty) 'without_keywords': blockedKeywordIds,
      },
      mediaType: MediaType.movie,
      targetCount: moviePoolSize,
      maxPages: isPreview ? 8 : 35,
      chunkSize: isPreview ? 3 : 5,
    );
    final featuredMoviesFuture = _collectMovieBackfillByReleaseWindows(
      {
        'language': TmdbConfig.contentLanguage,
        'sort_by': 'primary_release_date.desc',
        'include_adult': 'false',
        'include_video': 'false',
        'region': _homeReleaseRegion,
        'with_release_type': _movieHomeReleaseTypes,
        'watch_region': _homeReleaseRegion,
        'with_watch_monetization_types': _watchMonetizationTypes,
        'without_genres': _withoutListOnlyMovieGenresParam(),
        'release_date.lte': _date(now),
        'primary_release_date.lte': _date(now),
        'vote_count.gte': '20',
        if (blockedKeywordIds.isNotEmpty) 'without_keywords': blockedKeywordIds,
      },
      targetCount: moviePoolSize,
      oldestYear: 1950,
      yearsPerWindow: 2,
      maxPagesPerWindow: isPreview ? 4 : 14,
    );
    final topRatedMoviesFuture = _collectPagedItemsUntil(
      'discover/movie',
      {
        'language': TmdbConfig.contentLanguage,
        'sort_by': 'vote_average.desc',
        'include_adult': 'false',
        'include_video': 'false',
        'region': _homeReleaseRegion,
        'with_release_type': _movieHomeReleaseTypes,
        'watch_region': _homeReleaseRegion,
        'with_watch_monetization_types': _watchMonetizationTypes,
        'without_genres': _withoutListOnlyMovieGenresParam(),
        'release_date.lte': _date(now),
        'primary_release_date.lte': _date(now),
        'vote_count.gte': '100',
      },
      mediaType: MediaType.movie,
      targetCount: moviePoolSize,
      maxPages: isPreview ? 6 : 30,
      chunkSize: isPreview ? 3 : 5,
    );
    final latestSeriesFuture = _collectPagedItemsUntil(
      'discover/tv',
      {
        'language': TmdbConfig.contentLanguage,
        'sort_by': 'first_air_date.desc',
        'include_adult': 'false',
        'include_null_first_air_dates': 'false',
        'first_air_date.lte': _date(now),
        'with_status': _tvAllowedStatuses,
        'without_genres': _withoutSoftTvGenresParam(),
        'watch_region': _homeReleaseRegion,
        'with_watch_monetization_types': _watchMonetizationTypes,
        'vote_average.gte': _minimumSeriesListRatingText(),
        'vote_count.gte': '10',
      },
      mediaType: MediaType.tv,
      targetCount: seriesPoolSize,
      maxPages: isPreview ? 8 : 35,
      chunkSize: isPreview ? 3 : 5,
    );
    final topRatedSeriesFuture = _collectPagedItemsUntil(
      'discover/tv',
      {
        'language': TmdbConfig.contentLanguage,
        'sort_by': 'vote_average.desc',
        'include_adult': 'false',
        'include_null_first_air_dates': 'false',
        'first_air_date.lte': _date(now),
        'with_status': _tvAllowedStatuses,
        'without_genres': _withoutSoftTvGenresParam(),
        'watch_region': _homeReleaseRegion,
        'with_watch_monetization_types': _watchMonetizationTypes,
        'vote_average.gte': _minimumSeriesListRatingText(),
        'vote_count.gte': '50',
      },
      mediaType: MediaType.tv,
      targetCount: seriesPoolSize,
      maxPages: isPreview ? 6 : 30,
      chunkSize: isPreview ? 3 : 5,
    );
    final onTheAirFuture = _collectPagedItemsUntil(
      'tv/on_the_air',
      {
        'language': TmdbConfig.contentLanguage,
        if (blockedKeywordIds.isNotEmpty) 'without_keywords': blockedKeywordIds,
      },
      mediaType: MediaType.tv,
      targetCount: seriesPoolSize,
      maxPages: isPreview ? 6 : 30,
      chunkSize: isPreview ? 3 : 5,
    );
    final airingTodayFuture = _collectPagedItemsUntil(
      'tv/airing_today',
      {
        'language': TmdbConfig.contentLanguage,
        if (blockedKeywordIds.isNotEmpty) 'without_keywords': blockedKeywordIds,
      },
      mediaType: MediaType.tv,
      targetCount: seriesPoolSize,
      maxPages: isPreview ? 6 : 30,
      chunkSize: isPreview ? 3 : 5,
    );
    final recentLaunchFuture = _collectPagedItemsUntil(
      'discover/tv',
      {
        'language': TmdbConfig.contentLanguage,
        'sort_by': 'first_air_date.desc',
        'include_adult': 'false',
        'include_null_first_air_dates': 'false',
        'first_air_date.gte': _date(recentLaunchCutoff),
        'first_air_date.lte': _date(now),
        'with_status': _tvAllowedStatuses,
        'without_genres': _withoutSoftTvGenresParam(),
        'watch_region': _homeReleaseRegion,
        'with_watch_monetization_types': _watchMonetizationTypes,
        'vote_average.gte': _minimumSeriesListRatingText(),
        'vote_count.gte': '5',
        if (blockedKeywordIds.isNotEmpty) 'without_keywords': blockedKeywordIds,
      },
      mediaType: MediaType.tv,
      targetCount: seriesPoolSize,
      maxPages: isPreview ? 6 : 30,
      chunkSize: isPreview ? 3 : 5,
    );
    final freshEpisodeWindowFuture = _collectPagedItemsUntil(
      'discover/tv',
      {
        'language': TmdbConfig.contentLanguage,
        'sort_by': 'popularity.desc',
        'include_adult': 'false',
        'include_null_first_air_dates': 'false',
        'air_date.gte': _date(activeWindowStart),
        'air_date.lte': _date(activeWindowEnd),
        'with_status': _tvAllowedStatuses,
        'without_genres': _withoutSoftTvGenresParam(),
        'watch_region': _homeReleaseRegion,
        'with_watch_monetization_types': _watchMonetizationTypes,
        'vote_average.gte': _minimumSeriesListRatingText(),
        'vote_count.gte': '5',
        if (blockedKeywordIds.isNotEmpty) 'without_keywords': blockedKeywordIds,
      },
      mediaType: MediaType.tv,
      targetCount: seriesPoolSize,
      maxPages: isPreview ? 6 : 30,
      chunkSize: isPreview ? 3 : 5,
    );
    final protectedMovieFuture = _fetchProtectedMovieItems();
    final protectedSeriesFuture = _fetchProtectedSeriesItems();

    final genres = await genresFuture;
    final trendingData = await trendingFuture;
    final latestMovieItems = await latestMoviesFuture;
    final featuredMovieItems = await featuredMoviesFuture;
    final topRatedMovieItems = await topRatedMoviesFuture;
    final latestSeriesItems = await latestSeriesFuture;
    final topRatedSeriesItems = await topRatedSeriesFuture;
    final onTheAirItems = await onTheAirFuture;
    final airingTodayItems = await airingTodayFuture;
    final recentLaunchItems = await recentLaunchFuture;
    final freshEpisodeWindowItems = await freshEpisodeWindowFuture;
    final protectedMovieItems = _dedupeAndFilter(
      await protectedMovieFuture,
      blockSoftTvItems: false,
      enforceMinimumListRating: false,
      blockListOnlyMovieGenres: false,
    );
    final protectedSeriesItems = _dedupeAndFilter(
      await protectedSeriesFuture,
      blockSoftTvItems: false,
      enforceMinimumListRating: false,
    );
    final homeProtectedMovieItems = _latestProtectedMovieItemsForHome(protectedMovieItems);
    final homeNormalMovieKeys = homeProtectedMovieItems
        .where(_isNormalMovieCandidate)
        .map((item) => item.key)
        .toSet();

    final featuredBase = _dedupeAndFilter(
      ((trendingData['results'] as List)
              .where((e) => (e['media_type'] ?? '') != 'person')
              .map((e) =>
                  MediaItem.fromTrendingJson(e as Map<String, dynamic>)))
          .toList(),
      blockSoftTvItems: false,
    )
      ..sort((a, b) => b.popularity.compareTo(a.popularity));

    final featured = _prependUniqueItems(
      homeProtectedMovieItems,
      _keepOnlyLatestNormalMoviesForHome(featuredBase, homeNormalMovieKeys),
    );

    final latestBase = _sortByNewestThenPopularity(
      _dedupeAndFilter(
        _keepOnlyLatestNormalMoviesForHome([
          ...homeProtectedMovieItems,
          ...latestMovieItems,
          ...featuredMovieItems,
        ], homeNormalMovieKeys),
      ).where((item) => item.type == MediaType.movie),
    );
    final latest = _prependUniqueItems(homeProtectedMovieItems, latestBase);

    final featuredMoviesBase = _sortByNewestThenPopularity(
      _dedupeAndFilter(
        _keepOnlyLatestNormalMoviesForHome([
          ...homeProtectedMovieItems,
          ...featuredMovieItems,
          ...latestMovieItems,
        ], homeNormalMovieKeys),
      ).where((item) => item.type == MediaType.movie),
    );
    final featuredMovies = _prependUniqueItems(homeProtectedMovieItems, featuredMoviesBase);

    final topRatedMoviesBase = _dedupeAndFilter(
      _keepOnlyLatestNormalMoviesForHome([
        ...homeProtectedMovieItems,
        ...topRatedMovieItems,
      ], homeNormalMovieKeys),
      blockListOnlyMovieGenres: false,
    )
      ..sort((a, b) {
        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) return ratingCompare;
        final popularityCompare = b.popularity.compareTo(a.popularity);
        if (popularityCompare != 0) return popularityCompare;
        return (b.releaseDate ?? DateTime(1900))
            .compareTo(a.releaseDate ?? DateTime(1900));
      });
    final topRatedMovies = _prependUniqueItems(homeProtectedMovieItems, topRatedMoviesBase);

    final topRatedSeries = _dedupeAndFilter(topRatedSeriesItems)
      ..sort((a, b) {
        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) return ratingCompare;
        return b.popularity.compareTo(a.popularity);
      });

    final onTheAirKeys = onTheAirItems.map((e) => e.key).toSet();
    final airingTodayKeys = airingTodayItems.map((e) => e.key).toSet();
    final recentLaunchKeys = recentLaunchItems.map((e) => e.key).toSet();
    final freshEpisodeWindowKeys =
        freshEpisodeWindowItems.map((e) => e.key).toSet();

    final filteredFeaturedSeries = _dedupeAndFilter([
        ...protectedSeriesItems,
        ...airingTodayItems,
        ...onTheAirItems,
        ...freshEpisodeWindowItems,
        ...recentLaunchItems,
        ...latestSeriesItems,
      ], blockSoftTvItems: true)
        .where((item) {
          final isAiringToday   = airingTodayKeys.contains(item.key);
          final isOnTheAir      = onTheAirKeys.contains(item.key);
          final hasFreshEpisode = freshEpisodeWindowKeys.contains(item.key);
          final isRecentLaunch  = recentLaunchKeys.contains(item.key);

          final isActiveNow = isAiringToday || isOnTheAir || hasFreshEpisode;
          final releaseDate = item.releaseDate;
          final isVeryRecentLaunch = releaseDate != null &&
              now.difference(releaseDate).inDays <= 180;

          return isActiveNow || (isRecentLaunch && isVeryRecentLaunch);
        })
        .toList()
      ..sort((a, b) {
        final scoreA = _featuredSeriesScore(
          a,
          now: now,
          isAiring: onTheAirKeys.contains(a.key),
          isAiringToday: airingTodayKeys.contains(a.key),
          isRecentLaunch: recentLaunchKeys.contains(a.key),
          hasFreshEpisodeWindow: freshEpisodeWindowKeys.contains(a.key),
        );
        final scoreB = _featuredSeriesScore(
          b,
          now: now,
          isAiring: onTheAirKeys.contains(b.key),
          isAiringToday: airingTodayKeys.contains(b.key),
          isRecentLaunch: recentLaunchKeys.contains(b.key),
          hasFreshEpisodeWindow: freshEpisodeWindowKeys.contains(b.key),
        );
        return scoreB.compareTo(scoreA);
      });

    final featuredSeries = _prependUniqueItems(
      protectedSeriesItems,
      filteredFeaturedSeries,
    );

    final latestSeries = _sortByNewestThenPopularity(
      _prependUniqueItems(
        protectedSeriesItems,
        _dedupeAndFilter([
          ...protectedSeriesItems,
          ...latestSeriesItems,
          ...recentLaunchItems,
          ...onTheAirItems,
          ...freshEpisodeWindowItems,
        ], blockSoftTvItems: true),
      ),
    );

    final homeData = HomeData(
      genres: genres,
      featured: featured.take(featuredShelfSize).toList(),
      latest: latest.take(movieShelfSize).toList(),
      featuredSeries: featuredSeries.take(seriesShelfSize).toList(),
      latestSeries: latestSeries.take(seriesShelfSize).toList(),
      featuredMovies: featuredMovies.take(movieShelfSize).toList(),
      topRatedMovies: topRatedMovies.take(movieShelfSize).toList(),
      topRatedSeries: topRatedSeries.take(seriesShelfSize).toList(),
    );

    _homeCacheByProfile[profile] = homeData;
    _homeCacheAtByProfile[profile] = now;
    return homeData;
  }

  Future<List<MediaItem>> fetchSimilar(MediaItem item) async {
    final path = item.type == MediaType.movie
        ? 'movie/${item.id}/similar'
        : 'tv/${item.id}/similar';
    final data = await _getJson(path, {
      'language': TmdbConfig.contentLanguage,
      'page': '1',
    });
    final results = (data['results'] as List? ?? const []);
    final items = results.map((e) => item.type == MediaType.movie
        ? MediaItem.fromMovieJson(e as Map<String, dynamic>)
        : MediaItem.fromTvJson(e as Map<String, dynamic>));
    final filtered = await _filterActuallyAvailable(
      items.where((e) => e.id != item.id),
      maxToCheck: 24,
    );
    return filtered.take(15).toList(growable: false);
  }

  List<MediaItem> _sortCatalogItems(
    Iterable<MediaItem> items,
    SortMode sortMode,
  ) {
    final out = items.toList(growable: false);
    out.sort((a, b) {
      switch (sortMode) {
        case SortMode.newest:
          final dateCompare = (b.releaseDate ?? DateTime(1900))
              .compareTo(a.releaseDate ?? DateTime(1900));
          if (dateCompare != 0) return dateCompare;
          return b.popularity.compareTo(a.popularity);
        case SortMode.oldest:
          final dateCompare = (a.releaseDate ?? DateTime(1900))
              .compareTo(b.releaseDate ?? DateTime(1900));
          if (dateCompare != 0) return dateCompare;
          return b.popularity.compareTo(a.popularity);
        case SortMode.ratingHigh:
          final ratingCompare = b.rating.compareTo(a.rating);
          if (ratingCompare != 0) return ratingCompare;
          return b.popularity.compareTo(a.popularity);
        case SortMode.ratingLow:
          final ratingCompare = a.rating.compareTo(b.rating);
          if (ratingCompare != 0) return ratingCompare;
          return b.popularity.compareTo(a.popularity);
        case SortMode.titleAZ:
          final titleCompare =
              a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
          if (titleCompare != 0) return titleCompare;
          return (b.releaseDate ?? DateTime(1900))
              .compareTo(a.releaseDate ?? DateTime(1900));
        case SortMode.smart:
          final popularityCompare = b.popularity.compareTo(a.popularity);
          if (popularityCompare != 0) return popularityCompare;
          final ratingCompare = b.rating.compareTo(a.rating);
          if (ratingCompare != 0) return ratingCompare;
          return (b.releaseDate ?? DateTime(1900))
              .compareTo(a.releaseDate ?? DateTime(1900));
      }
    });
    return out;
  }

  Future<List<MediaItem>> fetchCatalogPage(
    MediaType type,
    int page, {
    SortMode sortMode = SortMode.newest,
    double minRating = 0,
    List<int>? genreIds,
    int? yearStart,
    int? yearEnd,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final now = DateTime.now();
    final blockedKeywordIds = await _discoverBlockedKeywordIds();
    final selectedIds = genreIds ?? const <int>[];
    final hasTvHorrorFilter =
        type == MediaType.tv && selectedIds.contains(_tvHorrorPseudoGenreId);
    final tvHorrorKeywordIds =
        hasTvHorrorFilter ? await _discoverTvHorrorKeywordIds() : '';

    String movieSortBy() {
      switch (sortMode) {
        case SortMode.newest:
          return 'primary_release_date.desc';
        case SortMode.oldest:
          return 'primary_release_date.asc';
        case SortMode.ratingHigh:
          return 'vote_average.desc';
        case SortMode.ratingLow:
          return 'vote_average.asc';
        case SortMode.titleAZ:
          return 'primary_release_date.desc';
        case SortMode.smart:
          return 'popularity.desc';
      }
    }

    String tvSortBy() {
      switch (sortMode) {
        case SortMode.newest:
          return 'first_air_date.desc';
        case SortMode.oldest:
          return 'first_air_date.asc';
        case SortMode.ratingHigh:
          return 'vote_average.desc';
        case SortMode.ratingLow:
          return 'vote_average.asc';
        case SortMode.titleAZ:
          return 'first_air_date.desc';
        case SortMode.smart:
          return 'popularity.desc';
      }
    }

    final hasGenreFilter = selectedIds.isNotEmpty;
    final hasRatingFilter = minRating > 0;
    final hasYearFilter = yearStart != null || yearEnd != null;
    final hasCustomSort = sortMode != SortMode.newest;
    final normalizedYearStart =
        yearStart == null ? null : math.min(yearStart, yearEnd ?? yearStart);
    final normalizedYearEnd =
        yearEnd == null ? null : math.max(yearEnd, yearStart ?? yearEnd);

    final pagesPerBatch =
        hasGenreFilter || hasRatingFilter || hasYearFilter || hasCustomSort
            ? 8
            : 6;
    final startPage = ((safePage - 1) * pagesPerBatch) + 1;
    final endPage = startPage + pagesPerBatch - 1;

    Future<List<MediaItem>> fetchBatch(
      String path,
      Map<String, String> baseQuery, {
      required MediaType mediaType,
    }) async {
      final raw = <dynamic>[];
      int? totalPages;

      for (int currentPage = startPage; currentPage <= endPage; currentPage++) {
        if (totalPages != null && currentPage > totalPages) break;

        final data = await _getJson(path, {
          ...baseQuery,
          'page': '$currentPage',
        });

        totalPages ??= (data['total_pages'] as num?)?.toInt();
        raw.addAll((data['results'] as List?) ?? const <dynamic>[]);
      }

      if (raw.isEmpty) return const <MediaItem>[];

      final items = mediaType == MediaType.movie
          ? _dedupeAndFilter(
              raw.map(
                (e) => MediaItem.fromMovieJson(e as Map<String, dynamic>),
              ),
            )
          : _dedupeAndFilter(
              raw.map(
                (e) => MediaItem.fromTvJson(e as Map<String, dynamic>),
              ),
            );

      final filtered = await _filterActuallyAvailable(
        items,
        maxToCheck: items.length,
      );
      final sorted = _sortCatalogItems(filtered, sortMode);
      if (mediaType == MediaType.movie &&
          safePage == 1 &&
          !hasGenreFilter &&
          !hasRatingFilter &&
          !hasYearFilter) {
        final latestProtectedMovies = _latestProtectedMovieItemsForHome(
          await _fetchProtectedMovieItems(),
        );
        final allowedNormalKeys = latestProtectedMovies
            .where(_isNormalMovieCandidate)
            .map((item) => item.key)
            .toSet();
        return _prependUniqueItems(
          latestProtectedMovies,
          _keepOnlyLatestNormalMoviesForHome(sorted, allowedNormalKeys),
        );
      }
      return sorted;
    }

    if (type == MediaType.movie) {
      final query = <String, String>{
        'language': TmdbConfig.contentLanguage,
        'include_adult': 'false',
        'include_video': 'false',
        'sort_by': movieSortBy(),
        'region': _homeReleaseRegion,
        'with_release_type': _movieHomeReleaseTypes,
        'watch_region': _homeReleaseRegion,
        'with_watch_monetization_types': _watchMonetizationTypes,
        'without_genres': _withoutListOnlyMovieGenresParam(),
        if (hasRatingFilter) 'vote_average.gte': _effectiveListMinRatingText(minRating),
        'vote_count.gte': '1',
        'release_date.lte': _date(now),
        'primary_release_date.lte': _date(now),
        if (blockedKeywordIds.isNotEmpty) 'without_keywords': blockedKeywordIds,
      };

      if (hasGenreFilter) {
        query['with_genres'] = selectedIds.join('|');
      }
      if (normalizedYearStart != null) {
        query['primary_release_date.gte'] =
            '${normalizedYearStart.toString().padLeft(4, '0')}-01-01';
      }
      if (normalizedYearEnd != null) {
        final endDate = DateTime(normalizedYearEnd, 12, 31).isAfter(now)
            ? now
            : DateTime(normalizedYearEnd, 12, 31);
        query['primary_release_date.lte'] = _date(endDate);
      }

      return fetchBatch(
        'discover/movie',
        query,
        mediaType: MediaType.movie,
      );
    }

    final query = <String, String>{
      'language': TmdbConfig.contentLanguage,
      'include_adult': 'false',
      'include_null_first_air_dates': 'false',
      'sort_by': tvSortBy(),
      'with_status': _tvAllowedStatuses,
      'without_genres': _withoutSoftTvGenresParam(),
      'watch_region': _homeReleaseRegion,
      'with_watch_monetization_types': _watchMonetizationTypes,
      'vote_average.gte': _effectiveSeriesListMinRatingText(
        hasRatingFilter ? minRating : 0,
      ),
      'vote_count.gte': '1',
      'first_air_date.lte': _date(now),
      if (blockedKeywordIds.isNotEmpty) 'without_keywords': blockedKeywordIds,
      if (hasTvHorrorFilter && tvHorrorKeywordIds.isNotEmpty)
        'with_keywords': tvHorrorKeywordIds,
    };

    final realTvGenreIds = selectedIds
        .where((id) => id != _tvHorrorPseudoGenreId)
        .toList(growable: false);
    if (realTvGenreIds.isNotEmpty) {
      query['with_genres'] = realTvGenreIds.join('|');
    } else if (hasTvHorrorFilter && tvHorrorKeywordIds.isEmpty) {
      query['with_genres'] = '$_tvHorrorPseudoGenreId';
    }
    if (normalizedYearStart != null) {
      query['first_air_date.gte'] =
          '${normalizedYearStart.toString().padLeft(4, '0')}-01-01';
    }
    if (normalizedYearEnd != null) {
      final endDate = DateTime(normalizedYearEnd, 12, 31).isAfter(now)
          ? now
          : DateTime(normalizedYearEnd, 12, 31);
      query['first_air_date.lte'] = _date(endDate);
    }

    return fetchBatch(
      'discover/tv',
      query,
      mediaType: MediaType.tv,
    );
  }

  Future<List<MediaItem>> searchAll(String query, {int pages = 4}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final futures = <Future<dynamic>>[];
    for (int page = 1; page <= pages; page++) {
      futures.add(_getJson('search/movie', {
        'language': TmdbConfig.contentLanguage,
        'include_adult': 'false',
        'query': q,
        'page': '$page',
      }));
      futures.add(_getJson('search/tv', {
        'language': TmdbConfig.contentLanguage,
        'include_adult': 'false',
        'query': q,
        'page': '$page',
      }));
    }
    final results = await Future.wait(futures);
    final merged = <MediaItem>[];
    for (int i = 0; i < results.length; i++) {
      final isMovie = i.isEven;
      for (final raw in (results[i]['results'] as List)) {
        if (isMovie) {
          final item = MediaItem.fromMovieJson(raw as Map<String, dynamic>);
          merged.add(_isNormalMovieCandidate(item)
              ? await _enrichMovieItemVisuals(item)
              : item);
        } else {
          merged.add(MediaItem.fromTvJson(raw as Map<String, dynamic>));
        }
      }
    }
    final filtered = await _filterActuallyAvailable(
      merged,
      maxToCheck: pages * 20,
      enforceMinimumListRating: false,
      blockListOnlyMovieGenres: false,
    );
    filtered.sort((a, b) => b.popularity.compareTo(a.popularity));
    return filtered;
  }

  String? _pickTrailerKeyFromVideoResults(Iterable<dynamic> rawResults) {
    String? fallback;
    for (final raw in rawResults) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final site = (map['site'] ?? '').toString().toLowerCase();
      final type = (map['type'] ?? '').toString().toLowerCase();
      final key = (map['key'] ?? '').toString().trim();
      final official = map['official'] == true;
      if (site != 'youtube' || key.isEmpty) continue;
      if (type == 'trailer' && official) return key;
      if (type == 'trailer') fallback ??= key;
      if (fallback == null && type == 'teaser') fallback = key;
    }
    return fallback;
  }

  Future<String?> _fetchBestTrailerKey(String path, Map<String, dynamic> data) async {
    final localResults = (data['videos']?['results'] as List?) ?? const <dynamic>[];
    final localKey = _pickTrailerKeyFromVideoResults(localResults);
    if (localKey != null && localKey.isNotEmpty) return localKey;

    for (final language in const ['en-US', '']) {
      try {
        final query = <String, String>{};
        if (language.isNotEmpty) query['language'] = language;
        final videos = await _getJson('$path/videos', query);
        final results = (videos['results'] as List?) ?? const <dynamic>[];
        final key = _pickTrailerKeyFromVideoResults(results);
        if (key != null && key.isNotEmpty) return key;
      } catch (_) {}
    }

    return null;
  }

  Future<MediaDetails> fetchDetails(MediaItem item) async {
    final path =
        item.type == MediaType.movie ? 'movie/${item.id}' : 'tv/${item.id}';
    final data = await _getJson(path, {
      'language': TmdbConfig.contentLanguage,
      'append_to_response': 'credits,videos',
    });

    final genres = ((data['genres'] ?? const []) as List)
        .map((e) => (e['name'] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .toList();

    final cast = ((data['credits']?['cast'] ?? const []) as List)
        .take(12)
        .map((e) => CastMember(
              name: (e['name'] ?? '').toString(),
              character: (e['character'] ?? '').toString(),
              profilePath: (e['profile_path'] ?? '').toString(),
            ))
        .where((e) => e.name.isNotEmpty)
        .toList();

    final trailerKey = await _fetchBestTrailerKey(path, data);

    int? runtimeMinutes;
    int? seasons;
    int? episodes;
    var seasonList = const <SeasonSummary>[];

    if (item.type == MediaType.movie) {
      runtimeMinutes = (data['runtime'] as num?)?.toInt();
    } else {
      seasons = (data['number_of_seasons'] as num?)?.toInt();
      episodes = (data['number_of_episodes'] as num?)?.toInt();
      seasonList = ((data['seasons'] ?? const []) as List)
          .map((e) => SeasonSummary.fromJson(e as Map<String, dynamic>))
          .where((e) => e.episodeCount > 0)
          .toList()
        ..sort((a, b) {
          if (a.isSpecial && !b.isSpecial) return 1;
          if (!a.isSpecial && b.isSpecial) return -1;
          return a.seasonNumber.compareTo(b.seasonNumber);
        });
    }

    final rawDetailItem = item.type == MediaType.movie
        ? MediaItem.fromMovieJson(data as Map<String, dynamic>)
        : MediaItem.fromTvJson(data as Map<String, dynamic>);
    final detailItem = item.type == MediaType.movie &&
            _isNormalMovieCandidate(rawDetailItem)
        ? await _enrichMovieItemVisuals(rawDetailItem)
        : rawDetailItem;

    final allowDetails = _isAllowed(detailItem) || _canRelaxDetailsFilter(detailItem);
    final blockByKeywords = !_isProtectedVisibleItem(detailItem) &&
        !_canRelaxDetailsFilter(detailItem) &&
        await _hasBlockedKeywords(detailItem);

    if (!allowDetails || blockByKeywords) {
      throw Exception('هذا العمل غير مدعوم في الفلترة الحالية.');
    }

    return MediaDetails(
      item: detailItem,
      genres: genres,
      cast: cast,
      runtimeMinutes: runtimeMinutes,
      seasons: seasons,
      episodes: episodes,
      trailerKey: trailerKey,
      seasonList: seasonList,
    );
  }

  Future<SeasonDetails> fetchSeasonDetails(
      int seriesId, int seasonNumber) async {
    final data = await _getJson('tv/$seriesId/season/$seasonNumber',
        {'language': TmdbConfig.contentLanguage});
    final season = SeasonSummary.fromJson(data as Map<String, dynamic>);
    final eps = ((data['episodes'] ?? const []) as List)
        .map((e) => EpisodeItem.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    return SeasonDetails(season: season, episodes: eps);
  }

  String _date(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  APP SHELL
// ══════════════════════════════════════════════════════════════════════════════

class SubSourceApiKeyStore {
  SubSourceApiKeyStore._();

  static const String docsUrl = 'https://subsource.net/api-docs';
  static const String _settingsFileName = 'subsource_api_settings.json';
  static const String _buildApiKey = String.fromEnvironment(
    'SUBSOURCE_API_KEY',
    defaultValue: '',
  );

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_settingsFileName');
  }

  static String _clean(String value) => value.trim();

  static Future<String> savedKey() async {
    try {
      final file = await _file();
      if (!await file.exists()) return '';
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return '';
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _clean((decoded['apiKey'] ?? '').toString());
      }
    } catch (_) {}
    return '';
  }

  static Future<String> currentKey() async {
    final saved = await savedKey();
    if (saved.isNotEmpty) return saved;
    return _clean(_buildApiKey);
  }

  static Future<bool> hasKey() async => (await currentKey()).isNotEmpty;

  static Future<bool> validateKey(String value) async {
    final key = _clean(value);
    if (key.isEmpty) return false;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 18);
    try {
      final uri = Uri.parse('https://api.subsource.net/api/v1/movies/search?searchType=text&q=Normal&year=2025');
      final request = await client.getUrl(uri);
      request.headers.set('X-API-Key', key);
      request.headers.set('Accept', 'application/json');
      request.headers.set('User-Agent', 'LightOn/1.0 Mozilla/5.0');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        if (decoded['success'] == true) return true;
        if (decoded['data'] is List) return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> saveKey(String value) async {
    final key = _clean(value);
    final file = await _file();
    if (key.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'apiKey': key,
        'updatedAt': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );
  }

  static Future<void> clearKey() => saveKey('');
}


class WyziePrefetchService {
  WyziePrefetchService._();

  static const String _subsourceApiKey = String.fromEnvironment(
    'SUBSOURCE_API_KEY',
    defaultValue: '',
  );
  static const String _subsourceApiBase = 'https://subsource.net';
  static const String _subsourceWebBase = 'https://subsource.net';
  static const String _subsourceFreeApiBase = 'https://api.subsource.net/api';
  static const String _subsourceOfficialApiBase = 'https://api.subsource.net/api/v1';
  static final String _subdlApiKey = AppSecureText.s('aMN_Qi79BCQ9FrxHJ6THHxV5shI_lFU-MhUyVHyD6zk');
  static final String _subdlApiBase = AppSecureText.s('Td9rX7tFV5heg55un8Lew0L-n2AHnoSqTgyw0CziPwngHQQpuYk');
  static final String _subdlDownloadBase = AppSecureText.s('oU2LtacL3x0ykhdgNIZQ166VAm4');
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36';

  static const int _primarySubsourceTargetTracks = 6;
  static const int _enoughStoredThreshold = 6;
  static const int _maxStoredTracksPerItem = 12;
  static const int _maxRemoteSubtitleDownloadsPerItem = 6;
  static const int _maxSubdlArabic2TracksPerItem = 4;
  static const int _minSubdlArabic2TracksPerItem = 2;

  static final Map<String, Future<List<Map<String, String>>>> _prepareInFlight =
      <String, Future<List<Map<String, String>>>>{};
  static final Map<String, List<Map<String, String>>> _preparedTrackCache =
      <String, List<Map<String, String>>>{};

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(minutes: 2),
      followRedirects: true,
      maxRedirects: 10,
      validateStatus: (s) => s != null && s < 500,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': _ua,
      },
    ),
  );

  static String _subtitleMimeFromName(String raw) {
    final value = raw.toLowerCase();
    if (value.endsWith('.vtt')) return 'text/vtt';
    if (value.endsWith('.srt')) return 'application/x-subrip';
    if (value.endsWith('.ass') || value.endsWith('.ssa')) return 'text/x-ssa';
    if (value.endsWith('.ttml') || value.endsWith('.xml')) return 'application/ttml+xml';
    if (value.endsWith('.zip')) return 'application/zip';
    return '';
  }

  static bool _isSupportedSubtitleMime(String mime) {
    final lower = mime.toLowerCase();
    if (lower.isEmpty) return true;
    return !lower.contains('zip') && !lower.contains('rar') && !lower.contains('7z');
  }

  static String _subtitleDisplayLanguage(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return 'Unknown';
    final lower = v.toLowerCase();
    switch (lower) {
      case 'ar':
      case 'ara':
      case 'arabic':
        return 'Arabic';
      case 'en':
      case 'eng':
      case 'english':
        return 'English';
      default:
        return v.length <= 3 ? v.toUpperCase() : '${v[0].toUpperCase()}${v.substring(1)}';
    }
  }

  static int _subtitleLanguageRankValue(String value) {
    final v = value.trim().toLowerCase();
    if (v == 'ar' || v.startsWith('ar') || v.contains('arab')) return 0;
    if (v == 'en' || v.startsWith('en') || v.contains('engl')) return 1;
    return 2;
  }

  static String _subdlDownloadUrlFromItem(Map<String, dynamic> item) {
    for (final key in const [
      'download_link',
      'downloadLink',
      'download_url',
      'downloadUrl',
      'download',
      'zipped_url',
      'zip_url',
      'full_link',
      'url',
      'link',
      'file',
      'subtitle_url',
      'subtitleUrl',
      'subdl_link',
      'subdlLink',
    ]) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isEmpty) continue;
      if (value.startsWith('http://') || value.startsWith('https://')) {
        return value;
      }
      final normalized = value.startsWith('/') ? value : '/$value';
      return '$_subdlDownloadBase${normalized.replaceFirst(RegExp(r'//+'), '/')}';
    }

    final files = item['files'];
    if (files is List) {
      for (final raw in files) {
        if (raw is! Map) continue;
        final nested = Map<String, dynamic>.from(raw);
        final nestedUrl = _subdlDownloadUrlFromItem(nested);
        if (nestedUrl.isNotEmpty) return nestedUrl;
      }
    }

    return '';
  }

  static bool _isSubtitleArchiveUrl(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return false;
    final normalized = value.split('?').first.split('#').first;
    return normalized.endsWith('.zip') || normalized.endsWith('.rar') || normalized.endsWith('.7z');
  }

  static bool _isArchiveSubtitleTrackMap(Map<String, String> track) {
    final url = (track['url'] ?? '').trim().toLowerCase();
    final mime = (track['mimeType'] ?? '').trim().toLowerCase();
    final label = (track['label'] ?? '').trim().toLowerCase();
    final fileName = (track['fileName'] ?? '').trim().toLowerCase();
    return _isSubtitleArchiveUrl(url) ||
        _isSubtitleArchiveUrl(label) ||
        _isSubtitleArchiveUrl(fileName) ||
        mime.contains('zip') ||
        mime.contains('rar') ||
        mime.contains('7z') ||
        mime.contains('compressed');
  }

  static bool _isSupportedSubtitlePath(String raw) {
    final mime = _subtitleMimeFromName(raw);
    return mime.isNotEmpty && _isSupportedSubtitleMime(mime);
  }

  static int _archiveSubtitleEntryScore(ArchiveFile entry, {
    required Map<String, String> track,
    int? season,
    int? episode,
  }) {
    final name = entry.name.toLowerCase();
    var score = 0;
    if (name.contains('/sample') || name.contains('sample/')) score += 5000;

    if (season != null && episode != null) {
      final s = season.toString().padLeft(2, '0');
      final e = episode.toString().padLeft(2, '0');
      if (name.contains('s${s}e$e')) score -= 1400;
      if (name.contains('${s}x$e')) score -= 1000;
      if (name.contains('episode ${episode.toString()}')) score -= 360;
      if (name.contains('ep ${episode.toString()}')) score -= 220;
    }

    final release = (track['release'] ?? '').toLowerCase();
    for (final token in release.split(RegExp(r'[^a-z0-9]+'))) {
      final t = token.trim();
      if (t.length < 4) continue;
      if (name.contains(t)) score -= 30;
    }

    if (name.endsWith('.srt')) {
      score -= 25;
    } else if (name.endsWith('.vtt')) score -= 20;
    else if (name.endsWith('.ass') || name.endsWith('.ssa')) score -= 18;
    else if (name.endsWith('.ttml') || name.endsWith('.xml')) score -= 10;

    score += name.length ~/ 8;
    return score;
  }

  static int? _positiveIntOrNull(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      final value = raw.toInt();
      return value > 0 ? value : null;
    }
    final parsed = int.tryParse(raw.toString().trim());
    return parsed != null && parsed > 0 ? parsed : null;
  }


  static String _normalizeSubtitleMovieTitle(String raw) {
    var value = raw.toLowerCase().trim();
    if (value.isEmpty) return '';
    value = value
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[’‘`´]'), "'")
        .replaceAll(RegExp(r'\bpart\s+one\b'), 'part 1')
        .replaceAll(RegExp(r'\bpart\s+two\b'), 'part 2')
        .replaceAll(RegExp(r'\bpart\s+three\b'), 'part 3')
        .replaceAll(RegExp(r'\bpart\s+four\b'), 'part 4')
        .replaceAll(RegExp(r'\bpart\s+five\b'), 'part 5')
        .replaceAll(RegExp(r'\bchapter\s+one\b'), 'chapter 1')
        .replaceAll(RegExp(r'\bchapter\s+two\b'), 'chapter 2')
        .replaceAll(RegExp(r'\bchapter\s+three\b'), 'chapter 3')
        .replaceAll(RegExp(r'\bchapter\s+four\b'), 'chapter 4')
        .replaceAll(RegExp(r'\bchapter\s+five\b'), 'chapter 5')
        .replaceAll(RegExp(r'\bvol(?:ume)?\s+one\b'), 'vol 1')
        .replaceAll(RegExp(r'\bvol(?:ume)?\s+two\b'), 'vol 2')
        .replaceAll(RegExp(r'\bvol(?:ume)?\s+three\b'), 'vol 3');
    value = value.replaceAll(RegExp(r'\((?:19|20)\d{2}\)'), ' ');
    value = value.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value;
  }

  static String _normalizeRomanSubtitleToken(String token) {
    switch (token.toLowerCase()) {
      case 'i':
        return '1';
      case 'ii':
        return '2';
      case 'iii':
        return '3';
      case 'iv':
        return '4';
      case 'v':
        return '5';
      case 'vi':
        return '6';
      case 'vii':
        return '7';
      case 'viii':
        return '8';
      case 'ix':
        return '9';
      case 'x':
        return '10';
    }
    return token.toLowerCase();
  }

  static Set<String> _subtitleMovieTitleTokens(String raw) {
    final normalized = _normalizeSubtitleMovieTitle(raw);
    if (normalized.isEmpty) return <String>{};
    const stopWords = <String>{
      'the', 'a', 'an', 'and', 'or', 'of', 'to', 'in', 'on', 'for', 'with',
      'movie', 'film', 'subtitle', 'subtitles', 'arabic', 'english', 'proper',
      'webrip', 'webdl', 'web', 'dl', 'bluray', 'brrip', 'hdrip', 'dvdrip',
      'x264', 'x265', 'h264', 'h265', 'hevc', 'aac', 'yts', 'rarbg', 'evo',
    };
    final out = <String>{};
    for (final rawToken in normalized.split(' ')) {
      if (rawToken.trim().isEmpty) continue;
      final token = _normalizeRomanSubtitleToken(rawToken.trim());
      if (stopWords.contains(token)) continue;
      if (token.length < 2 && int.tryParse(token) == null) continue;
      out.add(token);
    }
    return out;
  }

  static Set<String> _subtitleMovieTitleNumberMarkers(String raw) {
    final tokens = _subtitleMovieTitleTokens(raw);
    return tokens.where((token) => RegExp(r'^\d{1,4}$').hasMatch(token)).toSet();
  }

  static bool _movieTitleTokensMatchStrictly({
    required Set<String> wantedTokens,
    required Set<String> candidateTokens,
  }) {
    if (wantedTokens.isEmpty || candidateTokens.isEmpty) return false;
    final common = wantedTokens.intersection(candidateTokens).length;
    if (wantedTokens.length == 1) return common == 1;
    if (candidateTokens.length == 1) return false;

    final requiredCommon = wantedTokens.length <= 2
        ? wantedTokens.length
        : math.max(2, (wantedTokens.length * 0.78).ceil());
    final minCandidateTokens = wantedTokens.length <= 3
        ? 2
        : math.max(2, (wantedTokens.length * 0.55).ceil());

    if (candidateTokens.length < minCandidateTokens) return false;
    return common >= requiredCommon;
  }

  static Set<int> _subtitleYearsFromText(String raw) {
    final out = <int>{};
    for (final match in RegExp(r'\b(19\d{2}|20\d{2})\b').allMatches(raw)) {
      final parsed = int.tryParse(match.group(1) ?? '');
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  static String _subsourceCandidateTitleBlob(Map<String, dynamic> item) {
    return [
      item['title'] ?? '',
      item['alternateTitle'] ?? '',
      item['originalTitle'] ?? '',
      item['original_title'] ?? '',
      item['name'] ?? '',
    ].map((e) => e.toString().trim()).where((e) => e.isNotEmpty).join(' / ');
  }

  static bool _subsourceCandidateTypeMatches({
    required Map<String, dynamic> item,
    required MediaType mediaType,
  }) {
    final type = (item['type'] ?? item['mediaType'] ?? item['kind'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (type.isEmpty) return true;
    final isTv = type.contains('tv') || type.contains('show') || type.contains('series');
    final isMovie = type.contains('movie') || type.contains('film');
    if (mediaType == MediaType.movie && isTv) return false;
    if (mediaType == MediaType.tv && isMovie) return false;
    return true;
  }

  static bool _subsourceMovieCandidateMatchesRequest({
    required Map<String, dynamic> item,
    required int tmdbId,
    required MediaType mediaType,
    String? title,
    int? year,
    int? season,
  }) {
    if (!_subsourceCandidateTypeMatches(item: item, mediaType: mediaType)) return false;

    final rawTmdb = _positiveIntOrNull(item['tmdbId']) ?? _positiveIntOrNull(item['tmdb_id']);
    if (rawTmdb != null) {
      if (rawTmdb != tmdbId) return false;
      if (mediaType == MediaType.tv && season != null) {
        final candidateSeason = _positiveIntOrNull(item['season']);
        if (candidateSeason != null && candidateSeason != season) return false;
      }
      return true;
    }

    final releaseYear = _positiveIntOrNull(item['releaseYear']) ?? _positiveIntOrNull(item['year']);
    if (year != null && year > 1900 && releaseYear != null && (releaseYear - year).abs() > 1) {
      return false;
    }

    if (mediaType == MediaType.tv && season != null) {
      final candidateSeason = _positiveIntOrNull(item['season']);
      if (candidateSeason != null && candidateSeason != season) return false;
    }

    final wanted = _normalizeSubtitleMovieTitle(title ?? '');
    if (wanted.isEmpty) return true;
    final candidateBlob = _subsourceCandidateTitleBlob(item);
    final candidateNormalized = _normalizeSubtitleMovieTitle(candidateBlob);
    if (candidateNormalized.isEmpty) return false;

    final wantedTokens = _subtitleMovieTitleTokens(wanted);
    final candidateTokens = _subtitleMovieTitleTokens(candidateNormalized);
    if (wantedTokens.isEmpty || candidateTokens.isEmpty) return false;

    final requiredMarkers = _subtitleMovieTitleNumberMarkers(wanted);
    if (requiredMarkers.isNotEmpty && !candidateTokens.containsAll(requiredMarkers)) {
      return false;
    }

    if (candidateNormalized == wanted) return true;
    if (wanted.length > 4 && candidateNormalized.length > 4 &&
        candidateNormalized.contains(wanted)) {
      return true;
    }

    return _movieTitleTokensMatchStrictly(
      wantedTokens: wantedTokens,
      candidateTokens: candidateTokens,
    );
  }

  static int _subsourceMovieTitlePenalty({
    required Map<String, dynamic> item,
    required String? title,
  }) {
    final wantedTokens = _subtitleMovieTitleTokens(title ?? '');
    if (wantedTokens.isEmpty) return 0;
    final candidateTokens = _subtitleMovieTitleTokens(_subsourceCandidateTitleBlob(item));
    if (candidateTokens.isEmpty) return 900;
    final common = wantedTokens.intersection(candidateTokens).length;
    return ((wantedTokens.length - common).clamp(0, wantedTokens.length) * 90).toInt();
  }

  static bool _movieSubtitleTextLooksCompatible({
    required String raw,
    required String? title,
    int? year,
    bool allowUnknown = true,
  }) {
    final wantedTitle = (title ?? '').trim();
    if (wantedTitle.isEmpty) return true;
    final blob = raw.toLowerCase();

    if (year != null && year > 1900) {
      final years = _subtitleYearsFromText(blob);
      if (years.isNotEmpty && !years.any((candidateYear) => (candidateYear - year).abs() <= 1)) {
        return false;
      }
    }

    final wantedTokens = _subtitleMovieTitleTokens(wantedTitle);
    if (wantedTokens.isEmpty) return true;
    final blobTokens = _subtitleMovieTitleTokens(blob);
    if (blobTokens.isEmpty) return allowUnknown;

    final common = wantedTokens.intersection(blobTokens).length;
    final wantedMarkers = _subtitleMovieTitleNumberMarkers(wantedTitle);
    final blobMarkers = _subtitleMovieTitleNumberMarkers(blob);
    if (common > 0 && wantedMarkers.isNotEmpty && blobMarkers.isNotEmpty &&
        !blobMarkers.any(wantedMarkers.contains)) {
      return false;
    }

    if (common == 0) return allowUnknown;
    return _movieTitleTokensMatchStrictly(
      wantedTokens: wantedTokens,
      candidateTokens: blobTokens,
    );
  }

  static bool _trackMatchesRequestedMovie(
    Map<String, String> track, {
    required MediaType mediaType,
    String? title,
    int? year,
  }) {
    if (mediaType != MediaType.movie) return true;
    return _movieSubtitleTextLooksCompatible(
      raw: _subtitleTrackSearchBlob(track),
      title: title,
      year: year,
      allowUnknown: true,
    );
  }

  static int? _extractSeasonNumberFromText(String raw) {
    final value = raw.toLowerCase();
    final patterns = <RegExp>[
      RegExp(r'\bs\s*(\d{1,2})\s*e\s*\d{1,3}\b'),
      RegExp(r'\b(\d{1,2})\s*x\s*\d{1,3}\b'),
      RegExp(r'\bseason[ ._-]?(\d{1,2})\b'),
      RegExp(r'\bseries[ ._-]?(\d{1,2})\b'),
      RegExp(r'\bs\s*(\d{1,2})\b'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(value);
      final parsed = match != null ? int.tryParse(match.group(1) ?? '') : null;
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  static List<int> _extractEpisodeNumbersFromText(String raw) {
    final value = raw.toLowerCase();
    final out = <int>{};

    void addRange(String? a, String? b) {
      final start = int.tryParse((a ?? '').replaceFirst(RegExp(r'^0+'), '').ifEmpty('0'));
      final end = int.tryParse((b ?? '').replaceFirst(RegExp(r'^0+'), '').ifEmpty('0'));
      if (start == null || start <= 0) return;
      if (end == null || end <= 0) {
        out.add(start);
        return;
      }
      final lo = math.min(start, end);
      final hi = math.max(start, end);
      if (hi - lo <= 80) {
        for (var i = lo; i <= hi; i++) {
          out.add(i);
        }
      }
    }

    final rangePatterns = <RegExp>[
      RegExp(r'\be\s*(\d{1,3})\s*[-–]\s*(\d{1,3})\b'),
      RegExp(r'\bepisodes?\s*(\d{1,3})\s*[-–]\s*(\d{1,3})\b'),
      RegExp(r'\bep\s*(\d{1,3})\s*[-–]\s*(\d{1,3})\b'),
    ];
    for (final pattern in rangePatterns) {
      for (final match in pattern.allMatches(value)) {
        addRange(match.group(1), match.group(2));
      }
    }

    final singlePatterns = <RegExp>[
      RegExp(r'\bs\s*\d{1,2}\s*e\s*(\d{1,3})\b'),
      RegExp(r'\b\d{1,2}\s*x\s*(\d{1,3})\b'),
      RegExp(r'\bepisode[ ._-]?(\d{1,3})\b'),
      RegExp(r'\bep[ ._-]?(\d{1,3})\b'),
      RegExp(r'\be\s*(\d{1,3})\b'),
    ];
    for (final pattern in singlePatterns) {
      for (final match in pattern.allMatches(value)) {
        addRange(match.group(1), null);
      }
    }

    return out.toList(growable: false)..sort();
  }

  static int? _extractEpisodeNumberFromText(String raw) {
    final episodes = _extractEpisodeNumbersFromText(raw);
    return episodes.isEmpty ? null : episodes.first;
  }

  static bool _looksLikeFullSeasonPack(String raw) {
    final value = raw.toLowerCase();
    return value.contains('full season') ||
        value.contains('season pack') ||
        value.contains('complete season') ||
        value.contains('complete all') ||
        value.contains('all episodes') ||
        value.contains('complete series') ||
        RegExp(r'\bs\s*\d{1,2}[ ._-]*(complete|pack)\b').hasMatch(value) ||
        RegExp(r'\bseason[ ._-]?\d{1,2}[ ._-]*(complete|pack)\b').hasMatch(value);
  }

  static bool _textMatchesRequestedEpisode(
    String raw, {
    required MediaType mediaType,
    int? season,
    int? episode,
    bool allowUnknownEpisode = true,
  }) {
    if (mediaType != MediaType.tv || season == null || episode == null) return true;
    final seasonFromText = _extractSeasonNumberFromText(raw);
    if (seasonFromText != null && seasonFromText != season) return false;
    final episodeNumbers = _extractEpisodeNumbersFromText(raw);
    if (episodeNumbers.isNotEmpty) return episodeNumbers.contains(episode);
    return allowUnknownEpisode;
  }

  static int _subdlEpisodeSpecificScore({
    required Map<String, dynamic> item,
    required MediaType mediaType,
    int? season,
    int? episode,
  }) {
    if (mediaType != MediaType.tv || season == null || episode == null) return 0;

    final explicitSeason = _positiveIntOrNull(item['season']) ??
        _positiveIntOrNull(item['season_number']) ??
        _positiveIntOrNull(item['seasonNumber']);
    final explicitEpisode = _positiveIntOrNull(item['episode']) ??
        _positiveIntOrNull(item['episode_number']) ??
        _positiveIntOrNull(item['episodeNumber']);
    final blob = [
      item['release_name'] ?? item['release'] ?? '',
      item['name'] ?? '',
      item['file_name'] ?? '',
      item['filename'] ?? '',
      item['author'] ?? '',
      item['comment'] ?? '',
    ].join(' ').toLowerCase();

    final seasonFromText = _extractSeasonNumberFromText(blob);
    final episodeFromText = _extractEpisodeNumberFromText(blob);
    final fullSeason = _looksLikeFullSeasonPack(blob) ||
        item['full_season'] == true ||
        item['fullSeason'] == true ||
        (item['full_season']?.toString().trim() == '1');

    if (explicitSeason != null && explicitSeason != season) return 5000;
    if (seasonFromText != null && seasonFromText != season) return 4600;

    if (!fullSeason) {
      if (explicitEpisode != null && explicitEpisode != episode) return 5000;
      if (episodeFromText != null && episodeFromText != episode) return 4200;
    }

    var score = 0;
    if (explicitSeason == season) score -= 140;
    if (seasonFromText == season) score -= 240;
    if (explicitEpisode == episode) score -= 520;
    if (episodeFromText == episode) score -= 760;
    if (fullSeason) score -= 320;
    return score;
  }



  static String _subtitleTrackSearchBlob(Map<String, String> track) {
    return [
      track['label'] ?? '',
      track['release'] ?? '',
      track['fileName'] ?? '',
      track['remoteUrl'] ?? '',
      track['url'] ?? '',
      track['source'] ?? '',
      track['commentary'] ?? '',
    ].join(' ').toLowerCase();
  }

  static bool _trackMatchesRequestedEpisode(
    Map<String, String> track, {
    required MediaType mediaType,
    int? season,
    int? episode,
  }) {
    if (mediaType != MediaType.tv || season == null || episode == null) return true;
    return _textMatchesRequestedEpisode(
      _subtitleTrackSearchBlob(track),
      mediaType: mediaType,
      season: season,
      episode: episode,
      allowUnknownEpisode: true,
    );
  }

  static int _trackRank(Map<String, String> track) {
    return int.tryParse((track['matchRank'] ?? '').trim()) ?? 0;
  }

  static int _providerPriority(Map<String, String> track) {
    if (_isPrimarySubsourceTrackMap(track)) return 0;
    if (_isSubdlTrackMap(track)) return 2;
    return 9;
  }

  static bool _isSubdlTrackMap(Map<String, String> track) {
    final group = (track['providerGroup'] ?? '').trim().toLowerCase();
    final source = (track['source'] ?? '').trim().toLowerCase();
    final label = (track['label'] ?? '').trim().toLowerCase();
    final fileName = (track['fileName'] ?? '').trim().toLowerCase();
    final remoteUrl = (track['remoteUrl'] ?? '').trim().toLowerCase();
    final url = (track['url'] ?? '').trim().toLowerCase();
    final release = (track['release'] ?? '').trim().toLowerCase();
    final blob = [group, source, label, release, fileName, remoteUrl, url].join(' ');
    if (group.startsWith('subsource') ||
        source.contains('subsource') ||
        source.contains('عربي 1') ||
        label.contains('subsource') ||
        label.contains('عربي 1') ||
        fileName.contains('subsource') ||
        fileName.contains('عربي 1')) {
      return false;
    }

    return group == 'subdl' ||
        group == 'arabic2' ||
        source.contains('subdl') ||
        source.contains('عربي 2') ||
        label.contains('subdl') ||
        label.contains('عربي 2') ||
        fileName.contains('subdl') ||
        fileName.contains('عربي 2') ||
        blob.contains('arabic2');
  }

  static int _subdlTrackCount(Iterable<Map<String, String>> tracks) {
    return tracks.where(_isSubdlTrackMap).length;
  }

  static bool _hasEnoughSubdlArabic2Tracks(Iterable<Map<String, String>> tracks) {
    return _subdlTrackCount(tracks) >= _minSubdlArabic2TracksPerItem;
  }

  static bool _isPrimarySubsourceTrackMap(Map<String, String> track) {
    final group = (track['providerGroup'] ?? '').trim().toLowerCase();
    final source = (track['source'] ?? '').trim().toLowerCase();
    final label = (track['label'] ?? '').trim().toLowerCase();
    final fileName = (track['fileName'] ?? '').trim().toLowerCase();
    final remoteUrl = (track['remoteUrl'] ?? '').trim().toLowerCase();
    final url = (track['url'] ?? '').trim().toLowerCase();
    final release = (track['release'] ?? '').trim().toLowerCase();
    final blob = [group, source, label, release, fileName, remoteUrl, url].join(' ');
    if (group.startsWith('subsource') ||
        source.contains('subsource') ||
        source.contains('عربي 1') ||
        label.contains('subsource') ||
        label.contains('عربي 1') ||
        fileName.contains('subsource') ||
        fileName.contains('عربي 1') ||
        blob.contains('arabic 1')) {
      return true;
    }

    if (_isSubdlTrackMap(track)) return false;
    return false;
  }

  static bool _hasPrimarySubsourceTrack(Iterable<Map<String, String>> tracks) {
    return tracks.any(_isPrimarySubsourceTrackMap);
  }

  static bool _hasCompleteStoredSubtitleSet(Iterable<Map<String, String>> tracks) {
    final list = tracks
        .where((track) => !_isArchiveSubtitleTrackMap(track))
        .toList(growable: false);
    return list.length >= _enoughStoredThreshold;
  }

  static int _storedSubtitleOrderScore(Map<String, String> track) {
    final rank = _trackRank(track).clamp(-999999, 999999).toInt();
    if (_isPrimarySubsourceTrackMap(track)) return -1000000 + rank;
    if (_isSubdlTrackMap(track)) return 100000 + rank;
    return rank;
  }

  static List<Map<String, String>> _prioritizeStoredTrackMaps(
    Iterable<Map<String, String>> tracks,
  ) {
    final out = _mergeStoredTrackMaps(tracks).toList(growable: false);
    out.sort((a, b) {
      final byProvider = _storedSubtitleOrderScore(a).compareTo(_storedSubtitleOrderScore(b));
      if (byProvider != 0) return byProvider;
      return _subtitleTrackIdentity(a).compareTo(_subtitleTrackIdentity(b));
    });
    return out;
  }

  static Map<String, String> _asArabic2SubdlTrack(Map<String, String> track) {
    final copy = Map<String, String>.from(track);
    final originalLabel = (copy['label'] ?? '').trim();
    copy['providerGroup'] = 'arabic2';
    copy['autoSelect'] = 'false';
    copy['default'] = 'false';

    final compact = originalLabel
        .replaceFirst(RegExp(r'^عربي\s*2\s*[•\-:]\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^SubDL\s*•\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^SubDL\s*-\s*', caseSensitive: false), '')
        .trim();
    copy['label'] = compact.isEmpty ? ((copy['release'] ?? '').trim().isEmpty ? 'Subtitle' : (copy['release'] ?? '').trim()) : compact;
    return copy;
  }

  static List<Map<String, String>> _asArabic2SubdlTracks(
    Iterable<Map<String, String>> tracks,
  ) {
    final out = <Map<String, String>>[];
    for (final track in tracks) {
      out.add(_asArabic2SubdlTrack(track));
      if (out.length >= _maxSubdlArabic2TracksPerItem) break;
    }
    return out;
  }

  static List<Map<String, String>> _pickStrictSubtitleCandidates(
    Iterable<Map<String, String>> tracks, {
    required MediaType mediaType,
    String? title,
    int? year,
    int? season,
    int? episode,
  }) {
    final filtered = _mergeStoredTrackMaps(tracks)
        .where((track) => _trackMatchesRequestedEpisode(
              track,
              mediaType: mediaType,
              season: season,
              episode: episode,
            ))
        .where((track) => _trackMatchesRequestedMovie(
              track,
              mediaType: mediaType,
              title: title,
              year: year,
            ))
        .toList(growable: false);
    if (filtered.isEmpty) return const <Map<String, String>>[];

    final sorted = List<Map<String, String>>.from(filtered)
      ..sort((a, b) {
        final byProvider = _providerPriority(a).compareTo(_providerPriority(b));
        if (byProvider != 0) return byProvider;
        final byRank = _trackRank(a).compareTo(_trackRank(b));
        if (byRank != 0) return byRank;
        return (a['label'] ?? '').toLowerCase().compareTo((b['label'] ?? '').toLowerCase());
      });

    final picked = <Map<String, String>>[];
    final seen = <String>{};

    bool addTrack(Map<String, String> track) {
      final id = _subtitleTrackIdentity(track);
      if (id.isEmpty || !seen.add(id)) return false;
      picked.add(track);
      return true;
    }

    var primaryCount = 0;
    for (final track in sorted) {
      if (!_isPrimarySubsourceTrackMap(track)) continue;
      if (addTrack(track)) primaryCount++;
      if (primaryCount >= _primarySubsourceTargetTracks) break;
    }

    var subdlCount = 0;
    for (final track in sorted) {
      if (!_isSubdlTrackMap(track)) continue;
      if (addTrack(_asArabic2SubdlTrack(track))) subdlCount++;
      if (subdlCount >= _maxSubdlArabic2TracksPerItem) break;
    }

    if (picked.isEmpty) {
      for (final track in sorted) {
        if (addTrack(_isSubdlTrackMap(track) ? _asArabic2SubdlTrack(track) : track)) break;
      }
    }

    return picked.take(_maxRemoteSubtitleDownloadsPerItem).toList(growable: false);
  }

  static bool _isArabicTrack({
    required String language,
    required String label,
    required String source,
  }) {
    final lang = language.trim().toLowerCase();
    final combined = '$label $source $language'.toLowerCase();
    return lang == 'ar' ||
        lang == 'ara' ||
        lang.startsWith('ar-') ||
        lang.startsWith('ara-') ||
        combined.contains('arabic') ||
        combined.contains('arab') ||
        combined.contains('العربي') ||
        combined.contains('عربي') ||
        combined.contains('عربية') ||
        combined.contains('عرب');
  }

  static bool _isEnglishTrack({
    required String language,
    required String label,
    required String source,
  }) {
    final lang = language.toLowerCase();
    final combined = '$label $source $language'.toLowerCase();
    return lang == 'en' || lang.startsWith('en') || combined.contains('english');
  }

  static String _buildLookupKey({
    required MediaType mediaType,
    required int tmdbId,
    int? season,
    int? episode,
  }) {
    return '${mediaType.name}|$tmdbId|${season ?? ''}|${episode ?? ''}'.toLowerCase();
  }

  static List<Map<String, String>> peekPreparedTracks({
    required MediaType mediaType,
    required int tmdbId,
    int? season,
    int? episode,
  }) {
    final key = _buildLookupKey(
      mediaType: mediaType,
      tmdbId: tmdbId,
      season: season,
      episode: episode,
    );
    return List<Map<String, String>>.from(
      _preparedTrackCache[key] ?? const <Map<String, String>>[],
      growable: false,
    );
  }

  static Future<List<Map<String, String>>> startPrepareArabicTracksForPlayback({
    required int tmdbId,
    required MediaType mediaType,
    required String title,
    int? year,
    int? season,
    int? episode,
    void Function(String message)? onProgress,
  }) {
    final baseKey = _buildLookupKey(
      mediaType: mediaType,
      tmdbId: tmdbId,
      season: season,
      episode: episode,
    );
    final key = mediaType == MediaType.movie
        ? '$baseKey|${_normalizeSubtitleMovieTitle(title)}|${year ?? ''}'
        : baseKey;
    final cached = _preparedTrackCache[key];
    if (cached != null && cached.isNotEmpty) {
      return Future<List<Map<String, String>>>.value(
        List<Map<String, String>>.from(cached, growable: false),
      );
    }
    final inFlight = _prepareInFlight[key];
    if (inFlight != null) return inFlight;
    final future = prepareArabicTracksForPlayback(
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      year: year,
      season: season,
      episode: episode,
      onProgress: onProgress,
    ).then((tracks) {
      _preparedTrackCache[key] = List<Map<String, String>>.from(tracks, growable: false);
      _prepareInFlight.remove(key);
      return tracks;
    }).catchError((error) {
      _prepareInFlight.remove(key);
      throw error;
    });
    _prepareInFlight[key] = future;
    return future;
  }

  static void primeArabicTracksForPlayback({
    required int tmdbId,
    required MediaType mediaType,
    required String title,
    int? year,
    int? season,
    int? episode,
  }) {
    unawaited(startPrepareArabicTracksForPlayback(
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      year: year,
      season: season,
      episode: episode,
    ));
  }

  static String _sanitizeFileName(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'subtitle';
    return trimmed
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _truncate(String value, [int max = 72]) {
    final v = value.trim();
    if (v.length <= max) return v;
    return '${v.substring(0, max)}…';
  }

  static Future<Directory> _rootDir() async {
    Directory? base;
    if (Platform.isAndroid) {
      try {
        base = await getExternalStorageDirectory();
      } catch (_) {}
    }
    base ??= await getApplicationDocumentsDirectory();
    final root = Directory('${base.path}/lighton_subtitles');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  static Future<File> _indexFile() async {
    final root = await _rootDir();
    return File('${root.path}/subtitle_index.json');
  }

  static Future<Map<String, dynamic>> _readIndex() async {
    try {
      final file = await _indexFile();
      if (!await file.exists()) return <String, dynamic>{};
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  static Future<void> _writeIndex(Map<String, dynamic> data) async {
    final file = await _indexFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
  }

  static Future<List<Map<String, String>>> loadStoredTracks({
    required MediaType mediaType,
    required int tmdbId,
    int? season,
    int? episode,
  }) async {
    final key = _buildLookupKey(
      mediaType: mediaType,
      tmdbId: tmdbId,
      season: season,
      episode: episode,
    );
    final index = await _readIndex();
    final raw = index[key];
    if (raw is! List) return const <Map<String, String>>[];

    final out = <Map<String, String>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final rawUrl = (map['url'] ?? '').toString().trim();
      if (rawUrl.isEmpty) continue;
      final path = rawUrl.startsWith('file://') ? Uri.parse(rawUrl).toFilePath() : rawUrl;
      final subtitleFile = File(path);
      if (!subtitleFile.existsSync()) continue;
      try {
        if (subtitleFile.lengthSync() < 32) continue;
      } catch (_) {
        continue;
      }

      final outItem = <String, String>{
        'label': (map['label'] ?? 'Subtitle').toString(),
        'url': rawUrl,
        'language': (map['language'] ?? '').toString(),
        'source': (map['source'] ?? 'Downloaded Subtitle').toString(),
      };
      for (final extraKey in const ['providerGroup', 'release', 'commentary', 'matchRank', 'subtitleId', 'subsourceMovieId', 'cachedArchivePath', 'fileName', 'movieTitle', 'movieYear']) {
        final extraValue = (map[extraKey] ?? '').toString().trim();
        if (extraValue.isNotEmpty) outItem[extraKey] = extraValue;
      }
      final mime = (map['mimeType'] ?? '').toString().trim();
      if (mime.isNotEmpty) outItem['mimeType'] = mime;
      final remote = (map['remoteUrl'] ?? '').toString().trim();
      if (remote.isNotEmpty) outItem['remoteUrl'] = remote;
      out.add(outItem);
    }
    return _mergeStoredTrackMaps(out).take(_maxStoredTracksPerItem).toList(growable: false);
  }

  static Future<void> _saveStoredTracks({
    required MediaType mediaType,
    required int tmdbId,
    int? season,
    int? episode,
    required List<Map<String, String>> tracks,
  }) async {
    final key = _buildLookupKey(
      mediaType: mediaType,
      tmdbId: tmdbId,
      season: season,
      episode: episode,
    );
    final index = await _readIndex();
    index[key] = _prioritizeStoredTrackMaps(tracks)
        .take(_maxStoredTracksPerItem)
        .toList(growable: false);
    await _writeIndex(index);
  }

  static String _subtitleTrackIdentity(Map<String, String> map) {
    final url = (map['url'] ?? '').trim().toLowerCase();
    final remote = (map['remoteUrl'] ?? '').trim().toLowerCase();
    final label = (map['label'] ?? '').trim().toLowerCase();
    final language = (map['language'] ?? '').trim().toLowerCase();
    final source = (map['source'] ?? '').trim().toLowerCase();
    final release = (map['release'] ?? '').trim().toLowerCase();
    final fileName = (map['fileName'] ?? '').trim().toLowerCase();
    final mimeType = (map['mimeType'] ?? '').trim().toLowerCase();
    if (remote.isNotEmpty) {
      return 'remote|$remote|$language|$source|$release|$label|$mimeType';
    }
    return 'local|$url|$language|$source|$release|$label|$fileName|$mimeType';
  }

  static bool _isAllowedSubtitleLanguage({
    required String language,
    String label = '',
    String source = '',
    String release = '',
  }) {
    return _isArabicTrack(language: language, label: '$label $release', source: source) ||
        _isEnglishTrack(language: language, label: '$label $release', source: source);
  }

  static List<Map<String, String>> _mergeStoredTrackMaps(
    Iterable<Map<String, String>> tracks,
  ) {
    final seen = <String>{};
    final out = <Map<String, String>>[];
    for (final raw in tracks) {
      final map = <String, String>{};
      raw.forEach((key, value) {
        final k = key.trim();
        final v = value.trim();
        if (k.isNotEmpty && v.isNotEmpty) map[k] = v;
      });
      final url = (map['url'] ?? '').trim();
      if (url.isEmpty) continue;
      final language = (map['language'] ?? '').trim();
      final label = (map['label'] ?? '').trim();
      final source = (map['source'] ?? '').trim();
      final release = (map['release'] ?? '').trim();
      if (!_isAllowedSubtitleLanguage(
        language: language,
        label: label,
        source: source,
        release: release,
      )) {
        continue;
      }
      final sig = _subtitleTrackIdentity(map);
      if (!seen.add(sig)) continue;
      out.add(map);
    }
    return out;
  }

  static Future<List<Map<String, String>>> fetchArabicTracks({
    required int tmdbId,
    required MediaType mediaType,
    String? title,
    int? year,
    int? season,
    int? episode,
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('جارِ البحث عن الترجمات...');

    try {
      final subsourceTracks = await _fetchSubsourceProviderTracks(
        tmdbId: tmdbId,
        mediaType: mediaType,
        title: title,
        year: year,
        season: season,
        episode: episode,
      );

      final subdlTracks = await _fetchSubdlProviderTracks(
        tmdbId: tmdbId,
        mediaType: mediaType,
        title: title,
        year: year,
        season: season,
        episode: episode,
      );

      final arabic2SubdlTracks = _asArabic2SubdlTracks(subdlTracks).map((track) {
        final copy = Map<String, String>.from(track);
        final rank = int.tryParse(copy['matchRank'] ?? '0') ?? 0;
        copy['matchRank'] = '${rank + 350}';
        return copy;
      }).toList(growable: false);

      final combined = <Map<String, String>>[
        ...subsourceTracks,
        ...arabic2SubdlTracks,
      ];
      if (combined.isEmpty) {
        onProgress?.call('لم يتم العثور على ترجمات.');
        return const <Map<String, String>>[];
      }

      combined.sort((a, b) {
        final byScore = int.tryParse(a['matchRank'] ?? '')?.compareTo(int.tryParse(b['matchRank'] ?? '') ?? 0) ?? 0;
        if (byScore != 0) return byScore;
        final byLang = _subtitleLanguageRankValue(a['language'] ?? '').compareTo(
          _subtitleLanguageRankValue(b['language'] ?? ''),
        );
        if (byLang != 0) return byLang;
        return (a['label'] ?? '').toLowerCase().compareTo((b['label'] ?? '').toLowerCase());
      });

      final picked = _pickStrictSubtitleCandidates(
        combined,
        mediaType: mediaType,
        title: title,
        year: year,
        season: season,
        episode: episode,
      );
      final arabicCount = picked.where((e) => (e['language'] ?? '').toLowerCase().startsWith('ar')).length;
      onProgress?.call(
        picked.isEmpty
            ? 'لم يتم العثور على ترجمة مناسبة لهذه الحلقة.'
            : 'تم اختيار ${picked.length} ترجمة فقط لهذه الحلقة ($arabicCount عربي).',
      );
      return picked;
    } catch (_) {
      return const <Map<String, String>>[];
    }
  }

  static Map<String, dynamic>? _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  static List<Map<String, dynamic>> _extractSubsourceDataList(dynamic data) {
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false);
    }
    final map = _asJsonMap(data);
    if (map == null) return const <Map<String, dynamic>>[];
    for (final key in const ['data', 'results', 'items', 'movies', 'subtitles']) {
      final value = map[key];
      if (value is List) {
        return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false);
      }
    }
    return const <Map<String, dynamic>>[];
  }

  static Options _subsourceJsonOptions() => Options(
        responseType: ResponseType.json,
        receiveTimeout: const Duration(minutes: 2),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': _ua,
        },
        validateStatus: (s) => s != null && s < 500,
      );

  static int? _subsourceIdFromItem(Map<String, dynamic> item) {
    for (final key in const ['movieId', 'id', 'subtitleId', 'subId']) {
      final parsed = _positiveIntOrNull(item[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static int _subsourceMovieCandidateScore({
    required Map<String, dynamic> item,
    required int tmdbId,
    required MediaType mediaType,
    String? title,
    int? year,
    int? season,
  }) {
    if (!_subsourceMovieCandidateMatchesRequest(
      item: item,
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      year: year,
      season: season,
    )) {
      return 1000000;
    }

    var score = 0;
    final rawTmdb = _positiveIntOrNull(item['tmdbId']) ?? _positiveIntOrNull(item['tmdb_id']);
    if (rawTmdb == tmdbId) score -= 5000;
    final type = (item['type'] ?? item['mediaType'] ?? item['kind'] ?? '').toString().trim().toLowerCase();
    if (type.isNotEmpty) {
      if (mediaType == MediaType.movie && type.contains('movie')) score -= 600;
      if (mediaType == MediaType.tv && (type.contains('tv') || type.contains('show') || type.contains('series'))) score -= 600;
    }
    final releaseYear = _positiveIntOrNull(item['releaseYear']) ?? _positiveIntOrNull(item['year']);
    if (year != null && year > 1900 && releaseYear != null) {
      score += (releaseYear - year).abs() * 40;
    }
    final candidateSeason = _positiveIntOrNull(item['season']);
    if (mediaType == MediaType.tv && season != null && candidateSeason != null) {
      score += candidateSeason == season ? -300 : 450;
    }
    score += _subsourceMovieTitlePenalty(item: item, title: title);
    return score;
  }

  static int _subsourceSubtitleScore(Map<String, dynamic> item) {
    var score = 0;
    final language = (item['language'] ?? '').toString().trim().toLowerCase();
    final releaseBlob = _subsourceReleaseText(item).toLowerCase();
    final releaseType = (item['releaseType'] ?? '').toString().trim().toLowerCase();
    final productionType = (item['productionType'] ?? '').toString().trim().toLowerCase();
    final downloads = _positiveIntOrNull(item['downloads']) ?? 0;
    final hearing = item['hearingImpaired'] == true ||
        item['hearingImpaired']?.toString().trim().toLowerCase() == 'true';
    if (language.startsWith('ar') || language.contains('arab')) score -= 360;
    if (language.startsWith('en') || language.contains('engl')) score -= 180;
    if (releaseBlob.contains('1080')) score -= 90;
    if (releaseBlob.contains('720')) score -= 70;
    if (releaseBlob.contains('web-dl') || releaseBlob.contains('webdl')) score -= 40;
    if (releaseBlob.contains('webrip')) score -= 25;
    if (releaseType.contains('retail')) score -= 35;
    if (productionType.contains('translated')) score -= 18;
    if (downloads > 0) score -= downloads.clamp(0, 250) ~/ 10;
    if (hearing) score += 25;
    return score;
  }

  static String _subsourceReleaseText(Map<String, dynamic> item) {
    final raw = item['releaseInfo'] ?? item['release_info'] ?? item['release'] ?? item['releaseName'] ?? item['name'] ?? '';
    if (raw is List) {
      return raw.map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty).join(' / ');
    }
    return raw.toString().trim();
  }

  static Future<int?> _findSubsourceMovieId({
    required int tmdbId,
    required MediaType mediaType,
    String? title,
    int? year,
    int? season,
  }) async {
    return null;
  }

  static Options _subsourceHtmlOptions([String? referer]) => Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(minutes: 2),
        followRedirects: true,
        maxRedirects: 8,
        headers: {
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9,ar;q=0.8',
          'User-Agent': _ua,
          'Referer': referer ?? 'https://subsource.net/',
        },
        validateStatus: (s) => s != null && s < 500,
      );

  static Options _subsourceFreeApiOptions() => Options(
        responseType: ResponseType.json,
        receiveTimeout: const Duration(minutes: 2),
        headers: const {
          'Accept': 'application/json, text/plain, */*',
          'Content-Type': 'application/json',
          'Origin': 'https://subsource.net',
          'Referer': 'https://subsource.net/',
          'User-Agent': _ua,
        },
        validateStatus: (s) => s != null && s < 500,
      );

  static String _decodeBasicHtmlEntities(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
  }

  static String _stripHtmlTags(String input) {
    final withoutScripts = input
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true, caseSensitive: false), ' ');
    return _decodeBasicHtmlEntities(
      withoutScripts
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
    );
  }

  static String _slugifyForSubsource(String value) {
    final cleaned = value
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return cleaned;
  }

  static String _subsourceLanguageFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final parts = uri.pathSegments;
      final idx = parts.indexOf('subtitle');
      if (idx >= 0 && parts.length > idx + 2) return parts[idx + 2];
    } catch (_) {}
    final lower = url.toLowerCase();
    if (lower.contains('/arabic/')) return 'arabic';
    if (lower.contains('/english/')) return 'english';
    return '';
  }

  static String _subsourceSubtitleIdFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final parts = uri.pathSegments;
      if (parts.isNotEmpty && RegExp(r'^\d+$').hasMatch(parts.last)) return parts.last;
    } catch (_) {}
    return '';
  }

  static String _resolveSubsourceUrl(String raw, String baseUrl) {
    final clean = _decodeBasicHtmlEntities(raw.trim());
    if (clean.isEmpty || clean.startsWith('javascript:') || clean.startsWith('#')) return '';
    try {
      return Uri.parse(baseUrl).resolve(clean).toString();
    } catch (_) {
      return '';
    }
  }

  static String _htmlWindowTextAround(String html, int index, {int radius = 900}) {
    final start = math.max(0, index - radius);
    final end = math.min(html.length, index + radius);
    return _stripHtmlTags(html.substring(start, end));
  }

  static Future<String> _subsourceGetText(String url, {String? referer}) async {
    final response = await _dio.get<String>(
      url,
      options: _subsourceHtmlOptions(referer),
    );
    final data = response.data;
    if (response.statusCode == null || response.statusCode! >= 400 || data == null) return '';
    return data.toString();
  }

  static List<String> _extractSubsourceLinks(String html, String baseUrl) {
    final out = <String>{};
    final patterns = <RegExp>[
      RegExp(r'''href\s*=\s*["']([^"']+)["']''', caseSensitive: false),
      RegExp(r'''src\s*=\s*["']([^"']+)["']''', caseSensitive: false),
      RegExp(r'''["']((?:/|https?://subsource\.net/)[^"']+)["']''', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(html)) {
        final raw = match.group(1) ?? '';
        final resolved = _resolveSubsourceUrl(raw, baseUrl);
        if (resolved.isEmpty) continue;
        final host = Uri.tryParse(resolved)?.host.toLowerCase() ?? '';
        if (!host.endsWith('subsource.net')) continue;
        out.add(resolved.split('#').first);
      }
    }
    return out.toList(growable: false);
  }

  static String _pickSubsourceDownloadUrl(String detailHtml, String detailUrl) {
    final links = _extractSubsourceLinks(detailHtml, detailUrl);
    String scoreLink(String url) => url.toLowerCase();

    final direct = links.firstWhere(
      (url) {
        final lower = scoreLink(url);
        return lower.endsWith('.srt') ||
            lower.endsWith('.vtt') ||
            lower.endsWith('.ass') ||
            lower.endsWith('.ssa') ||
            lower.endsWith('.zip') ||
            lower.contains('.srt?') ||
            lower.contains('.vtt?') ||
            lower.contains('.zip?');
      },
      orElse: () => '',
    );
    if (direct.isNotEmpty) return direct;

    final download = links.firstWhere(
      (url) {
        final lower = scoreLink(url);
        if (!lower.contains('download')) return false;
        if (lower.contains('/login') || lower.contains('/register')) return false;
        return true;
      },
      orElse: () => '',
    );
    if (download.isNotEmpty) return download;

    final id = _subsourceSubtitleIdFromUrl(detailUrl);
    if (id.isNotEmpty) {
      return '${detailUrl.replaceAll(RegExp(r'/+$'), '')}/download';
    }
    return '';
  }

  static int _subsourceWebTrackScore({
    required String language,
    required String label,
    required String release,
    required MediaType mediaType,
    int? season,
    int? episode,
  }) {
    var score = 0;
    final blob = '$language $label $release'.toLowerCase();
    if (_isArabicTrack(language: language, label: label, source: 'SubSource')) score -= 600;
    if (_isEnglishTrack(language: language, label: label, source: 'SubSource')) score -= 260;
    if (blob.contains('1080')) score -= 80;
    if (blob.contains('720')) score -= 50;
    if (blob.contains('web-dl') || blob.contains('webdl')) score -= 35;
    if (blob.contains('webrip')) score -= 25;
    if (blob.contains('bluray') || blob.contains('blu-ray')) score -= 18;
    if (blob.contains('hearing') || blob.contains(' hi ')) score += 28;
    if (mediaType == MediaType.tv && season != null && episode != null) {
      final epA = 's${season.toString().padLeft(2, '0')}e${episode.toString().padLeft(2, '0')}';
      final epB = '${season}x${episode.toString().padLeft(2, '0')}';
      if (blob.contains(epA) || blob.contains(epB)) score -= 900;
      if (RegExp(r's\d{1,2}e\d{1,2}|\d{1,2}x\d{1,2}', caseSensitive: false).hasMatch(blob) &&
          !(blob.contains(epA) || blob.contains(epB))) {
        score += 2500;
      }
    }
    return score;
  }

  static List<MapEntry<int, String>> _subsourceSubtitlePageCandidatesFromHtml(
    String html,
    String baseUrl, {
    required MediaType mediaType,
    int? season,
    int? episode,
  }) {
    final candidates = <String, MapEntry<int, String>>{};
    final hrefPattern = RegExp(r'''href\s*=\s*["']([^"']+)["']''', caseSensitive: false);
    for (final match in hrefPattern.allMatches(html)) {
      final raw = match.group(1) ?? '';
      final resolved = _resolveSubsourceUrl(raw, baseUrl);
      if (resolved.isEmpty) continue;
      final lower = resolved.toLowerCase();
      if (!lower.contains('subsource.net/subtitle/')) continue;
      final language = _subsourceLanguageFromUrl(resolved);
      if (!_isAllowedSubtitleLanguage(language: language, label: resolved, source: 'SubSource')) continue;
      final context = _htmlWindowTextAround(html, match.start);
      final score = _subsourceWebTrackScore(
        language: language,
        label: context,
        release: context,
        mediaType: mediaType,
        season: season,
        episode: episode,
      );
      final id = _subsourceSubtitleIdFromUrl(resolved);
      final key = id.isNotEmpty ? id : resolved.toLowerCase();
      final existing = candidates[key];
      if (existing == null || score < existing.key) {
        candidates[key] = MapEntry(score, resolved);
      }
    }
    final out = candidates.values.toList(growable: false);
    out.sort((a, b) => a.key.compareTo(b.key));
    return out;
  }

  static Future<List<MapEntry<int, String>>> _subsourceFindSubtitlePages({
    required int tmdbId,
    required MediaType mediaType,
    String? title,
    int? year,
    int? season,
    int? episode,
  }) async {
    final rawTitle = (title ?? '').trim();
    if (rawTitle.isEmpty && tmdbId <= 0) return const <MapEntry<int, String>>[];
    final titleSlug = _slugifyForSubsource(rawTitle);
    final titleYearSlug = year != null && year > 1900 && titleSlug.isNotEmpty
        ? '$titleSlug-$year'
        : titleSlug;
    final searchText = [
      rawTitle,
      if (year != null && year > 1900) year.toString(),
      if (mediaType == MediaType.tv && season != null && episode != null)
        'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}',
    ].where((e) => e.trim().isNotEmpty).join(' ');
    final encodedQuery = Uri.encodeQueryComponent(searchText.isNotEmpty ? searchText : tmdbId.toString());
    final pages = <String>{
      if (titleYearSlug.isNotEmpty) '$_subsourceWebBase/subtitles/$titleYearSlug',
      if (titleSlug.isNotEmpty) '$_subsourceWebBase/subtitles/$titleSlug',
      '$_subsourceWebBase/search?query=$encodedQuery',
      '$_subsourceWebBase/search?q=$encodedQuery',
      '$_subsourceWebBase/search?keyword=$encodedQuery',
    };

    final out = <String, MapEntry<int, String>>{};
    for (final page in pages) {
      try {
        final html = await _subsourceGetText(page);
        if (html.isEmpty) continue;
        final direct = _subsourceSubtitlePageCandidatesFromHtml(
          html,
          page,
          mediaType: mediaType,
          season: season,
          episode: episode,
        );
        for (final candidate in direct) {
          final key = _subsourceSubtitleIdFromUrl(candidate.value).ifEmpty(candidate.value.toLowerCase());
          final existing = out[key];
          if (existing == null || candidate.key < existing.key) out[key] = candidate;
        }

        final listPages = _extractSubsourceLinks(html, page)
            .where((u) => u.toLowerCase().contains('subsource.net/subtitles/'))
            .take(8)
            .toList(growable: false);
        for (final listPage in listPages) {
          try {
            final listHtml = await _subsourceGetText(listPage, referer: page);
            if (listHtml.isEmpty) continue;
            final nested = _subsourceSubtitlePageCandidatesFromHtml(
              listHtml,
              listPage,
              mediaType: mediaType,
              season: season,
              episode: episode,
            );
            for (final candidate in nested) {
              final key = _subsourceSubtitleIdFromUrl(candidate.value).ifEmpty(candidate.value.toLowerCase());
              final existing = out[key];
              if (existing == null || candidate.key < existing.key) out[key] = candidate;
            }
          } catch (_) {}
        }
      } catch (_) {}
      if (out.length >= 18) break;
    }
    final result = out.values.toList(growable: false);
    result.sort((a, b) => a.key.compareTo(b.key));
    return result.take(24).toList(growable: false);
  }

  static Future<List<Map<String, String>>> _fetchSubsourceWebTracks({
    required int tmdbId,
    required MediaType mediaType,
    String? title,
    int? year,
    int? season,
    int? episode,
  }) async {
    final pages = await _subsourceFindSubtitlePages(
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      year: year,
      season: season,
      episode: episode,
    );
    if (pages.isEmpty) return const <Map<String, String>>[];

    final out = <MapEntry<int, Map<String, String>>>[];
    final seen = <String>{};
    for (final candidate in pages.take(16)) {
      final detailUrl = candidate.value;
      try {
        final detailHtml = await _subsourceGetText(detailUrl, referer: 'https://subsource.net/');
        final language = _subsourceLanguageFromUrl(detailUrl);
        final id = _subsourceSubtitleIdFromUrl(detailUrl);
        final detailText = detailHtml.isEmpty ? detailUrl : _stripHtmlTags(detailHtml);
        if (!_isAllowedSubtitleLanguage(language: language, label: detailText, source: 'SubSource')) continue;
        final downloadUrl = detailHtml.isNotEmpty
            ? _pickSubsourceDownloadUrl(detailHtml, detailUrl)
            : '${detailUrl.replaceAll(RegExp(r'/+$'), '')}/download';
        if (downloadUrl.isEmpty) continue;
        final displayLanguage = _subtitleDisplayLanguage(language);
        final release = _truncate(detailText.ifEmpty(detailUrl), 180);
        final label = <String>[
          'SubSource',
          displayLanguage,
          if (release.isNotEmpty) release,
        ].join(' • ');
        final sig = id.isNotEmpty ? id : downloadUrl.toLowerCase();
        if (!seen.add(sig)) continue;
        final score = candidate.key + _subsourceWebTrackScore(
          language: language,
          label: label,
          release: release,
          mediaType: mediaType,
          season: season,
          episode: episode,
        );
        out.add(MapEntry(score, <String, String>{
          'label': label,
          'url': downloadUrl,
          'remoteUrl': downloadUrl,
          'language': language,
          'source': 'SubSource',
          'providerGroup': 'subsource-web',
          'release': release,
          'matchRank': '$score',
          'fileName': id.isNotEmpty ? 'subsource-$id.zip' : 'subsource-web.zip',
          'mimeType': _subtitleMimeFromName(downloadUrl),
          if (id.isNotEmpty) 'subtitleId': id,
          'referer': detailUrl,
        }));
      } catch (_) {}
    }
    out.sort((a, b) => a.key.compareTo(b.key));
    return out.map((e) => e.value).take(_maxStoredTracksPerItem).toList(growable: false);
  }


  static String _subsourceFullText(Map<String, dynamic> item) {
    final parts = <String>[];
    void walk(dynamic value) {
      if (value == null) return;
      if (value is String || value is num || value is bool) {
        parts.add(value.toString());
      } else if (value is Map) {
        value.values.forEach(walk);
      } else if (value is Iterable) {
        value.forEach(walk);
      }
    }
    walk(item);
    return parts.join(' ');
  }

  static int _subsourcePreferredTranslatorScore(Map<String, dynamic> item) {
    final blob = _subsourceFullText(item).toLowerCase();
    var score = 0;
    if (blob.contains('د. علي طلال') || blob.contains('د.علي طلال')) score -= 10000;
    if (blob.contains('دكتور علي طلال') || blob.contains('علي طلال')) score -= 9000;
    if (blob.contains('غلي طلال')) score -= 8500;
    if (blob.contains('talal')) score -= 3000;
    if (blob.contains('محمد النعيمي')) score -= 600;
    if (blob.contains('فؤاد الخفاجي')) score -= 500;
    return score;
  }

  static Future<List<Map<String, String>>> _fetchSubsourceOfficialApiTracks({
    required int tmdbId,
    required MediaType mediaType,
    String? title,
    int? year,
    int? season,
    int? episode,
  }) async {
    final apiKey = (await SubSourceApiKeyStore.currentKey()).trim();
    final query = (title ?? '').trim();
    if (apiKey.isEmpty || query.isEmpty) return const <Map<String, String>>[];

    Options apiOptions({ResponseType responseType = ResponseType.json}) => Options(
          responseType: responseType,
          receiveTimeout: const Duration(minutes: 2),
          headers: {
            'X-API-Key': apiKey,
            'Accept': responseType == ResponseType.bytes
                ? 'application/zip, application/octet-stream, */*'
                : 'application/json',
            'User-Agent': 'LightOn/1.0 Mozilla/5.0',
          },
          validateStatus: (s) => s != null && s < 500,
        );

    try {
      final searchQuery = <String, dynamic>{
        'searchType': 'text',
        'q': query,
        if (year != null && year > 1900) 'year': year.toString(),
        if (mediaType == MediaType.tv && season != null) 'season': season.toString(),
      };

      final searchResponse = await _dio.get(
        '$_subsourceOfficialApiBase/movies/search',
        queryParameters: searchQuery,
        options: apiOptions(),
      );
      if ((searchResponse.statusCode ?? 0) < 200 || (searchResponse.statusCode ?? 0) >= 300) {
        return const <Map<String, String>>[];
      }

      final movies = _extractSubsourceDataList(searchResponse.data);
      if (movies.isEmpty) return const <Map<String, String>>[];
      final usableMovies = movies.where((movie) => _subsourceMovieCandidateMatchesRequest(
            item: movie,
            tmdbId: tmdbId,
            mediaType: mediaType,
            title: title,
            year: year,
            season: season,
          )).toList(growable: false);
      if (usableMovies.isEmpty) return const <Map<String, String>>[];
      usableMovies.sort((a, b) => _subsourceMovieCandidateScore(
            item: a,
            tmdbId: tmdbId,
            mediaType: mediaType,
            title: title,
            year: year,
            season: season,
          ).compareTo(_subsourceMovieCandidateScore(
            item: b,
            tmdbId: tmdbId,
            mediaType: mediaType,
            title: title,
            year: year,
            season: season,
          )));

      final movieIds = <int>[];
      for (final movie in usableMovies.take(5)) {
        final id = _positiveIntOrNull(movie['movieId']) ??
            _positiveIntOrNull(movie['id']) ??
            _positiveIntOrNull(movie['contentId']);
        if (id != null && !movieIds.contains(id)) movieIds.add(id);
      }
      if (movieIds.isEmpty) return const <Map<String, String>>[];

      Future<List<Map<String, dynamic>>> loadSubs(int movieId, String language) async {
        final response = await _dio.get(
          '$_subsourceOfficialApiBase/subtitles',
          queryParameters: <String, dynamic>{
            'movieId': movieId.toString(),
            'language': language,
            if (mediaType == MediaType.tv && season != null) 'season': season.toString(),
            if (mediaType == MediaType.tv && episode != null) 'episode': episode.toString(),
            if (mediaType == MediaType.tv && season != null) 'seasonNumber': season.toString(),
            if (mediaType == MediaType.tv && episode != null) 'episodeNumber': episode.toString(),
          },
          options: apiOptions(),
        );
        if ((response.statusCode ?? 0) < 200 || (response.statusCode ?? 0) >= 300) {
          return const <Map<String, dynamic>>[];
        }
        return _extractSubsourceDataList(response.data);
      }

      const languageVariants = <String>['arabic', 'ar', 'ara'];
      final out = <MapEntry<int, Map<String, String>>>[];
      final seen = <String>{};
      for (final movieId in movieIds) {
        for (final langQuery in languageVariants) {
          final subs = await loadSubs(movieId, langQuery);
          for (final item in subs) {
            final subtitleId = _positiveIntOrNull(item['subtitleId']) ?? _positiveIntOrNull(item['id']);
            if (subtitleId == null) continue;

            final language = (item['language'] ?? langQuery).toString().trim();
            final release = _subsourceReleaseText(item);
            final commentary = (item['commentary'] ?? item['comment'] ?? item['description'] ?? '').toString().trim();
            if (!_isAllowedSubtitleLanguage(
              language: language,
              label: '$release $commentary',
              source: 'SubSource',
              release: release,
            )) {
              continue;
            }
            if (!_textMatchesRequestedEpisode(
              '$release $commentary',
              mediaType: mediaType,
              season: season,
              episode: episode,
              allowUnknownEpisode: true,
            )) {
              continue;
            }
            if (mediaType == MediaType.movie && !_movieSubtitleTextLooksCompatible(
              raw: '$release $commentary ${item['name'] ?? ''} ${item['fileName'] ?? ''}',
              title: title,
              year: year,
              allowUnknown: true,
            )) {
              continue;
            }

            final displayLanguage = _subtitleDisplayLanguage(language);
            final compactComment = _truncate(commentary.replaceAll('\n', ' '), 120);
            final label = <String>[
              'عربي 1',
              displayLanguage,
              if (compactComment.isNotEmpty) compactComment,
              if (release.isNotEmpty) _truncate(release, 120),
            ].join(' • ');
            final sig = '$subtitleId|$language|$movieId';
            if (!seen.add(sig)) continue;

            final score = _subsourcePreferredTranslatorScore(item) +
                _subsourceSubtitleScore(item) +
                _subdlEpisodeSpecificScore(
                  item: item,
                  mediaType: mediaType,
                  season: season,
                  episode: episode,
                );

            out.add(MapEntry(score, <String, String>{
              'label': label,
              'url': '$_subsourceOfficialApiBase/subtitles/$subtitleId/download',
              'remoteUrl': '$_subsourceOfficialApiBase/subtitles/$subtitleId/download',
              'language': language,
              'source': 'SubSource API',
              'providerGroup': 'subsource-api',
              'release': release,
              'commentary': commentary,
              'matchRank': '$score',
              'fileName': 'subsource-$subtitleId.zip',
              'mimeType': 'application/zip',
              'subtitleId': subtitleId.toString(),
              'subsourceMovieId': movieId.toString(),
            }));
          }
        }
      }

      out.sort((a, b) => a.key.compareTo(b.key));
      return out.map((e) => e.value).take(24).toList(growable: false);
    } catch (_) {
      return const <Map<String, String>>[];
    }
  }

  static Future<List<Map<String, String>>> _fetchSubsourceFreeApiTracks({
    required int tmdbId,
    required MediaType mediaType,
    String? title,
    int? year,
    int? season,
    int? episode,
  }) async {
    final query = (title ?? '').trim();
    if (query.isEmpty) return const <Map<String, String>>[];
    try {
      final searchResponse = await _dio.post(
        '$_subsourceFreeApiBase/searchMovie',
        data: jsonEncode(<String, dynamic>{'query': query}),
        options: _subsourceFreeApiOptions(),
      );
      final searchMap = _asJsonMap(searchResponse.data);
      final found = (searchMap?['found'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false) ?? const <Map<String, dynamic>>[];
      if (found.isEmpty) return const <Map<String, String>>[];
      final usableFound = found.where((candidate) => _subsourceMovieCandidateMatchesRequest(
            item: candidate,
            tmdbId: tmdbId,
            mediaType: mediaType,
            title: title,
            year: year,
            season: season,
          )).toList(growable: false);
      if (usableFound.isEmpty) return const <Map<String, String>>[];
      usableFound.sort((a, b) => _subsourceMovieCandidateScore(
            item: a,
            tmdbId: tmdbId,
            mediaType: mediaType,
            title: title,
            year: year,
            season: season,
          ).compareTo(_subsourceMovieCandidateScore(
            item: b,
            tmdbId: tmdbId,
            mediaType: mediaType,
            title: title,
            year: year,
            season: season,
          )));
      final linkName = (usableFound.first['linkName'] ?? usableFound.first['link'] ?? usableFound.first['name'] ?? '').toString().trim();
      if (linkName.isEmpty) return const <Map<String, String>>[];
      final getPayload = <String, dynamic>{'movieName': linkName};
      if (mediaType == MediaType.tv && season != null) {
        getPayload['season'] = 'season-$season';
      }
      final movieResponse = await _dio.post(
        '$_subsourceFreeApiBase/getMovie',
        data: jsonEncode(getPayload),
        options: _subsourceFreeApiOptions(),
      );
      final movieMap = _asJsonMap(movieResponse.data);
      final subs = (movieMap?['subs'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false) ?? const <Map<String, dynamic>>[];
      if (subs.isEmpty) return const <Map<String, String>>[];
      final out = <MapEntry<int, Map<String, String>>>[];
      final seen = <String>{};
      for (final item in subs) {
        final subId = _positiveIntOrNull(item['subId']) ?? _positiveIntOrNull(item['id']);
        if (subId == null) continue;
        final language = (item['lang'] ?? item['language'] ?? '').toString().trim();
        final release = (item['releaseName'] ?? item['release'] ?? item['name'] ?? '').toString().trim();
        if (!_isAllowedSubtitleLanguage(language: language, label: release, source: 'SubSource')) continue;
        if (mediaType == MediaType.movie && !_movieSubtitleTextLooksCompatible(
          raw: '$release ${item['name'] ?? ''} ${item['fileName'] ?? ''}',
          title: title,
          year: year,
          allowUnknown: true,
        )) {
          continue;
        }
        final episodeScore = _subdlEpisodeSpecificScore(
          item: item,
          mediaType: mediaType,
          season: season,
          episode: episode,
        );
        if (episodeScore >= 4000) continue;
        final displayLanguage = _subtitleDisplayLanguage(language);
        final label = <String>['SubSource', displayLanguage, if (release.isNotEmpty) release].join(' • ');
        final sig = '$subId|$language|$release';
        if (!seen.add(sig)) continue;
        final score = _subsourceWebTrackScore(
          language: language,
          label: label,
          release: release,
          mediaType: mediaType,
          season: season,
          episode: episode,
        ) + episodeScore;
        out.add(MapEntry(score, <String, String>{
          'label': label,
          'url': '$_subsourceFreeApiBase/downloadSub',
          'remoteUrl': '$_subsourceFreeApiBase/downloadSub#$subId',
          'language': language,
          'source': 'SubSource',
          'providerGroup': 'subsource-free-api',
          'release': release,
          'matchRank': '$score',
          'fileName': 'subsource-$subId.zip',
          'mimeType': 'application/zip',
          'subtitleId': subId.toString(),
        }));
      }
      out.sort((a, b) => a.key.compareTo(b.key));
      return out.map((e) => e.value).take(_maxStoredTracksPerItem).toList(growable: false);
    } catch (_) {
      return const <Map<String, String>>[];
    }
  }

  static Future<List<Map<String, String>>> _fetchSubsourceProviderTracks({
    required int tmdbId,
    required MediaType mediaType,
    String? title,
    int? year,
    int? season,
    int? episode,
  }) async {
    final officialApiTracks = await _fetchSubsourceOfficialApiTracks(
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      year: year,
      season: season,
      episode: episode,
    );
    if (officialApiTracks.isNotEmpty) return officialApiTracks;

    final webTracks = await _fetchSubsourceWebTracks(
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      year: year,
      season: season,
      episode: episode,
    );
    if (webTracks.isNotEmpty) return webTracks;

    return _fetchSubsourceFreeApiTracks(
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      year: year,
      season: season,
      episode: episode,
    );
  }

  static Future<List<Map<String, String>>> _fetchSubdlProviderTracks({
    required int tmdbId,
    required MediaType mediaType,
    String? title,
    int? year,
    int? season,
    int? episode,
  }) async {
    final apiKey = _subdlApiKey.trim();
    if (apiKey.isEmpty) return const <Map<String, String>>[];

    int scoreItem(Map<String, dynamic> item) {
      var score = 0;
      final language = (item['lang'] ??
              item['language'] ??
              item['language_name'] ??
              item['lang_name'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();
      final release = (item['release_name'] ?? item['release'] ?? item['name'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final hi = item['hi'] == true ||
          item['hearing_impaired'] == true ||
          item['isHearingImpaired'] == true;
      if (language.startsWith('ar') || language.contains('arab')) score -= 300;
      if (mediaType == MediaType.tv) {
        final rawSeason = _positiveIntOrNull(item['season']) ??
            _positiveIntOrNull(item['season_number']) ??
            _positiveIntOrNull(item['seasonNumber']);
        final rawEpisode = _positiveIntOrNull(item['episode']) ??
            _positiveIntOrNull(item['episode_number']) ??
            _positiveIntOrNull(item['episodeNumber']);
        if (season != null && rawSeason == season) score -= 80;
        if (episode != null && rawEpisode == episode) score -= 120;
      }
      if (release.contains('1080')) score -= 60;
      if (release.contains('720')) score -= 45;
      if (release.contains('web-dl') || release.contains('webdl')) score -= 20;
      if (release.contains('webrip')) score -= 15;
      if (hi) score += 25;
      return score;
    }

    Map<String, dynamic>? decodeResponseData(dynamic data) {
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is String) {
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {}
      }
      return null;
    }

    List<Map<String, dynamic>> extractSubtitleList(Map<String, dynamic> data) {
      final status = data['status'];
      if (status == false || status == 'false') return const <Map<String, dynamic>>[];
      final subtitles = data['subtitles'];
      if (subtitles is List) {
        return subtitles.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false);
      }
      return const <Map<String, dynamic>>[];
    }

    final subdlType = mediaType == MediaType.movie ? 'movie' : 'tv';

    Map<String, String>? buildTrackEntry(Map<String, dynamic> item) {
      final downloadUrl = _subdlDownloadUrlFromItem(item);
      if (downloadUrl.isEmpty) return null;

      final rawLang = (item['lang'] ??
              item['language'] ??
              item['language_name'] ??
              item['lang_name'] ??
              item['locale'] ??
              item['iso'] ??
              '')
          .toString()
          .trim();
      final language = rawLang.isEmpty ? 'und' : rawLang;
      final release = (item['release_name'] ?? item['release'] ?? '').toString().trim();
      final archiveName = (item['name'] ?? item['filename'] ?? item['file_name'] ?? '')
          .toString()
          .trim();
      final hi = item['hi'] == true ||
          item['hearing_impaired'] == true ||
          item['isHearingImpaired'] == true;

      final isArabic = _isArabicTrack(
        language: language,
        label: '$release $archiveName',
        source: 'SubDL',
      );
      if (!isArabic) return null;

      final episodeScore = _subdlEpisodeSpecificScore(
        item: item,
        mediaType: mediaType,
        season: season,
        episode: episode,
      );
      if (episodeScore >= 4000) return null;

      final displayLanguage = _subtitleDisplayLanguage(rawLang.isEmpty ? 'Unknown' : rawLang);
      final label = release.isNotEmpty
          ? 'SubDL • $displayLanguage • $release'
          : 'SubDL • $displayLanguage';

      return <String, String>{
        'label': label,
        'url': downloadUrl,
        'remoteUrl': downloadUrl,
        'language': language,
        'source': 'SubDL',
        'providerGroup': 'subdl',
        'release': release,
        'matchRank': '${scoreItem(item) + episodeScore}',
        if (archiveName.isNotEmpty) 'fileName': archiveName,
        if (hi) 'hearingImpaired': 'true',
      };
    }

    const langVariants = <String>['ar', 'AR', 'arabic'];
    final seen = <String>{};
    final out = <MapEntry<int, Map<String, String>>>[];

    Future<void> collectFromSubtitleResponse(Map<String, dynamic>? data) async {
      if (data == null) return;
      final items = extractSubtitleList(data);
      for (final item in items) {
        final entry = buildTrackEntry(item);
        if (entry == null) continue;
        final sig = '${entry['url']?.toLowerCase() ?? ''}|${entry['language']?.toLowerCase() ?? ''}|${entry['release']?.toLowerCase() ?? ''}|${entry['fileName']?.toLowerCase() ?? ''}';
        if (!seen.add(sig)) continue;
        out.add(MapEntry(int.tryParse(entry['matchRank'] ?? '0') ?? 0, entry));
      }
    }

    try {
      for (final lang in langVariants) {
        final params = <String, dynamic>{
          'api_key': apiKey,
          'tmdb_id': tmdbId,
          'type': subdlType,
          'languages': lang,
          'subs_per_page': _maxSubdlArabic2TracksPerItem,
          if (year != null && year > 1900) 'year': year,
          if (subdlType == 'tv' && season != null) 'season_number': season,
          if (subdlType == 'tv' && episode != null) 'episode_number': episode,
        };

        final response = await _dio.get(
          _subdlApiBase,
          queryParameters: params,
          options: Options(
            responseType: ResponseType.json,
            receiveTimeout: const Duration(minutes: 2),
            headers: const {
              'Accept': 'application/json',
              'User-Agent': _ua,
            },
            validateStatus: (s) => s != null && s < 500,
          ),
        );

        await collectFromSubtitleResponse(decodeResponseData(response.data));
        if (out.isNotEmpty) break;
      }

      if (out.isEmpty) {
        final fallback = await _fetchSubdlProviderTracksViaSdId(
          apiKey: apiKey,
          tmdbId: tmdbId,
          mediaType: mediaType,
          type: subdlType,
          year: year,
          season: season,
          episode: episode,
          scoreItem: scoreItem,
          seen: seen,
        );
        out.addAll(fallback);
      }

      out.sort((a, b) {
        final byScore = a.key.compareTo(b.key);
        if (byScore != 0) return byScore;
        final byLang = _subtitleLanguageRankValue(a.value['language'] ?? '')
            .compareTo(_subtitleLanguageRankValue(b.value['language'] ?? ''));
        if (byLang != 0) return byLang;
        return (a.value['label'] ?? '')
            .toLowerCase()
            .compareTo((b.value['label'] ?? '').toLowerCase());
      });

      return out
          .map((e) => _asArabic2SubdlTrack(Map<String, String>.from(e.value)))
          .take(_maxSubdlArabic2TracksPerItem)
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, String>>[];
    }
  }

  static Future<List<MapEntry<int, Map<String, String>>>> _fetchSubdlProviderTracksViaSdId({
    required String apiKey,
    required int tmdbId,
    required MediaType mediaType,
    required String type,
    required int Function(Map<String, dynamic> item) scoreItem,
    required Set<String> seen,
    int? year,
    int? season,
    int? episode,
  }) async {
    Map<String, dynamic>? decodeResponseData(dynamic data) {
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is String) {
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {}
      }
      return null;
    }

    List<Map<String, dynamic>> extractSubtitleList(Map<String, dynamic> data) {
      final status = data['status'];
      if (status == false || status == 'false') return const <Map<String, dynamic>>[];
      final subtitles = data['subtitles'];
      if (subtitles is List) {
        return subtitles.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false);
      }
      return const <Map<String, dynamic>>[];
    }

    Map<String, String>? buildTrackEntry(Map<String, dynamic> item) {
      final downloadUrl = _subdlDownloadUrlFromItem(item);
      if (downloadUrl.isEmpty) return null;

      final rawLang = (item['lang'] ??
              item['language'] ??
              item['language_name'] ??
              item['lang_name'] ??
              item['locale'] ??
              item['iso'] ??
              '')
          .toString()
          .trim();
      final language = rawLang.isEmpty ? 'und' : rawLang;
      final release = (item['release_name'] ?? item['release'] ?? '').toString().trim();
      final archiveName = (item['name'] ?? item['filename'] ?? item['file_name'] ?? '')
          .toString()
          .trim();
      final hi = item['hi'] == true ||
          item['hearing_impaired'] == true ||
          item['isHearingImpaired'] == true;

      final isArabic = _isArabicTrack(
        language: language,
        label: '$release $archiveName',
        source: 'SubDL',
      );
      if (!isArabic) return null;

      final episodeScore = _subdlEpisodeSpecificScore(
        item: item,
        mediaType: mediaType,
        season: season,
        episode: episode,
      );
      if (episodeScore >= 4000) return null;

      final displayLanguage = _subtitleDisplayLanguage(rawLang.isEmpty ? 'Unknown' : rawLang);
      final label = release.isNotEmpty
          ? 'SubDL • $displayLanguage • $release'
          : 'SubDL • $displayLanguage';

      return <String, String>{
        'label': label,
        'url': downloadUrl,
        'remoteUrl': downloadUrl,
        'language': language,
        'source': 'SubDL',
        'providerGroup': 'subdl',
        'release': release,
        'matchRank': '${scoreItem(item) + episodeScore}',
        if (archiveName.isNotEmpty) 'fileName': archiveName,
        if (hi) 'hearingImpaired': 'true',
      };
    }

    final out = <MapEntry<int, Map<String, String>>>[];

    try {
      final response = await _dio.get(
        _subdlApiBase,
        queryParameters: {
          'api_key': apiKey,
          'tmdb_id': tmdbId,
          'type': type,
          'subs_per_page': _maxSubdlArabic2TracksPerItem,
          if (year != null && year > 1900) 'year': year,
          if (type == 'tv' && season != null) 'season_number': season,
          if (type == 'tv' && episode != null) 'episode_number': episode,
        },
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(minutes: 2),
          headers: const {
            'Accept': 'application/json',
            'User-Agent': _ua,
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      final data = decodeResponseData(response.data);
      if (data == null) return out;
      final movieResults = data['results'];
      if (movieResults is! List || movieResults.isEmpty) return out;
      final first = movieResults.first;
      if (first is! Map) return out;
      final movieInfo = Map<String, dynamic>.from(first);
      final sdId = movieInfo['sd_id'];
      if (sdId == null) return out;

      for (final lang in const <String>['ar', 'AR']) {
        final r2 = await _dio.get(
          _subdlApiBase,
          queryParameters: {
            'api_key': apiKey,
            'sd_id': sdId,
            'languages': lang,
            'subs_per_page': _maxSubdlArabic2TracksPerItem,
            if (type == 'tv' && season != null) 'season_number': season,
            if (type == 'tv' && episode != null) 'episode_number': episode,
          },
          options: Options(
            responseType: ResponseType.json,
            receiveTimeout: const Duration(minutes: 2),
            headers: const {
              'Accept': 'application/json',
              'User-Agent': _ua,
            },
            validateStatus: (s) => s != null && s < 500,
          ),
        );

        final data2 = decodeResponseData(r2.data);
        if (data2 == null) continue;
        final items = extractSubtitleList(data2);
        for (final item in items) {
          final entry = buildTrackEntry(item);
          if (entry == null) continue;
          final sig = '${entry['url']?.toLowerCase() ?? ''}|${entry['language']?.toLowerCase() ?? ''}|${entry['release']?.toLowerCase() ?? ''}|${entry['fileName']?.toLowerCase() ?? ''}';
          if (!seen.add(sig)) continue;
          out.add(MapEntry(int.tryParse(entry['matchRank'] ?? '0') ?? 0, entry));
        }
        if (out.isNotEmpty) break;
      }
    } catch (_) {}

    return out;
  }

  static Future<Directory> _targetDirForItem({
    required MediaType mediaType,
    required int tmdbId,
    required String title,
    int? year,
    int? season,
    int? episode,
  }) async {
    final root = await _rootDir();
    if (mediaType == MediaType.movie) {
      final folder = year != null && year > 1900
          ? '${_sanitizeFileName(title)} ($year) [tmdb-$tmdbId]'
          : '${_sanitizeFileName(title)} [tmdb-$tmdbId]';
      final dir = Directory('${root.path}/$folder');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }

    final seriesDir = Directory('${root.path}/${_sanitizeFileName(title)} [tmdb-$tmdbId]');
    if (!await seriesDir.exists()) await seriesDir.create(recursive: true);
    final seasonDir = Directory(
      '${seriesDir.path}/Season ${season?.toString().padLeft(2, '0') ?? '00'}',
    );
    if (!await seasonDir.exists()) await seasonDir.create(recursive: true);
    final episodeDir = Directory(
      '${seasonDir.path}/Episode ${episode?.toString().padLeft(2, '0') ?? '00'}',
    );
    if (!await episodeDir.exists()) await episodeDir.create(recursive: true);
    return episodeDir;
  }

  static ArchiveFile? _pickArchiveSubtitleEntry({
    required Archive archive,
    required Map<String, String> track,
    MediaType mediaType = MediaType.tv,
    String? title,
    int? year,
    int? season,
    int? episode,
  }) {
    final candidates = archive.files.where((entry) {
      if (!entry.isFile) return false;
      return _isSupportedSubtitlePath(entry.name);
    }).toList(growable: false);
    if (candidates.isEmpty) return null;

    var filtered = candidates;
    if (mediaType == MediaType.movie && (title ?? '').trim().isNotEmpty) {
      final compatibleMovieEntries = candidates.where((entry) => _movieSubtitleTextLooksCompatible(
            raw: entry.name,
            title: title,
            year: year,
            allowUnknown: false,
          )).toList(growable: false);
      if (compatibleMovieEntries.isNotEmpty) {
        filtered = compatibleMovieEntries;
      } else if (candidates.length > 1) {
        return null;
      }
    }
    if (season != null && episode != null) {
      final exact = candidates.where((entry) => _textMatchesRequestedEpisode(
            entry.name,
            mediaType: MediaType.tv,
            season: season,
            episode: episode,
            allowUnknownEpisode: false,
          )).toList(growable: false);
      if (exact.isNotEmpty) {
        filtered = exact;
      } else if (!_textMatchesRequestedEpisode(
        _subtitleTrackSearchBlob(track),
        mediaType: MediaType.tv,
        season: season,
        episode: episode,
        allowUnknownEpisode: true,
      )) {
        return null;
      } else if (candidates.length > 1) {
        return null;
      }
    }

    filtered.sort((a, b) {
      final byScore = _archiveSubtitleEntryScore(a, track: track, season: season, episode: episode)
          .compareTo(_archiveSubtitleEntryScore(b, track: track, season: season, episode: episode));
      if (byScore != 0) return byScore;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return filtered.first;
  }

  static Future<Directory> _seasonArchiveDirForItem({
    required MediaType mediaType,
    required int tmdbId,
    required String title,
    int? year,
    int? season,
  }) async {
    final root = await _rootDir();
    if (mediaType == MediaType.movie) {
      final dir = Directory('${root.path}/${_sanitizeFileName(title)} [tmdb-$tmdbId]/__subtitle_archives');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    final seriesDir = Directory('${root.path}/${_sanitizeFileName(title)} [tmdb-$tmdbId]');
    if (!await seriesDir.exists()) await seriesDir.create(recursive: true);
    final seasonDir = Directory('${seriesDir.path}/Season ${season?.toString().padLeft(2, '0') ?? '00'}');
    if (!await seasonDir.exists()) await seasonDir.create(recursive: true);
    final archiveDir = Directory('${seasonDir.path}/__subtitle_archives');
    if (!await archiveDir.exists()) await archiveDir.create(recursive: true);
    return archiveDir;
  }

  static String _archiveCacheFileName(Map<String, String> track, Uint8List bytes) {
    final seed = [
      track['remoteUrl'] ?? '',
      track['url'] ?? '',
      track['subtitleId'] ?? '',
      track['source'] ?? '',
      bytes.length.toString(),
    ].join('|');
    return 'archive-${seed.hashCode.abs().toRadixString(16).padLeft(8, '0')}.zip';
  }

  static Future<void> _storeSubtitleArchiveCache({
    required Map<String, String> track,
    required Uint8List bytes,
    required Directory targetDir,
  }) async {
    try {
      Directory archiveDir;
      final parent = targetDir.parent;
      if (parent.path.toLowerCase().contains('season ')) {
        archiveDir = Directory('${parent.path}/__subtitle_archives');
      } else {
        archiveDir = Directory('${targetDir.path}/__subtitle_archives');
      }
      if (!await archiveDir.exists()) await archiveDir.create(recursive: true);
      final archiveName = _archiveCacheFileName(track, bytes);
      final archiveFile = File('${archiveDir.path}/$archiveName');
      if (!await archiveFile.exists()) {
        await archiveFile.writeAsBytes(bytes, flush: true);
      }
      final meta = Map<String, String>.from(track);
      meta['cachedArchivePath'] = archiveFile.path;
      await File('${archiveFile.path}.json').writeAsString(jsonEncode(meta), flush: true);
    } catch (_) {}
  }

  static Future<List<Map<String, String>>> _extractTracksFromCachedSeasonArchives({
    required MediaType mediaType,
    required int tmdbId,
    required String title,
    int? year,
    int? season,
    int? episode,
  }) async {
    if (mediaType != MediaType.tv || season == null || episode == null) {
      return const <Map<String, String>>[];
    }
    try {
      final archiveDir = await _seasonArchiveDirForItem(
        mediaType: mediaType,
        tmdbId: tmdbId,
        title: title,
        year: year,
        season: season,
      );
      if (!await archiveDir.exists()) return const <Map<String, String>>[];
      final targetDir = await _targetDirForItem(
        mediaType: mediaType,
        tmdbId: tmdbId,
        title: title,
        year: year,
        season: season,
        episode: episode,
      );
      final baseName = '${title.trim()} S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
      final out = <Map<String, String>>[];
      await for (final entity in archiveDir.list(followLinks: false)) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.zip')) continue;
        Map<String, String> meta = <String, String>{};
        try {
          final rawMeta = await File('${entity.path}.json').readAsString();
          final decoded = jsonDecode(rawMeta);
          if (decoded is Map) {
            decoded.forEach((key, value) {
              if (key != null && value != null) meta[key.toString()] = value.toString();
            });
          }
        } catch (_) {}
        if (meta.isEmpty) {
          meta = <String, String>{
            'label': entity.uri.pathSegments.last,
            'source': 'عربي 1',
            'providerGroup': 'subsource-api',
            'language': 'ar',
            'url': entity.path,
            'remoteUrl': entity.path,
            'mimeType': 'application/zip',
          };
        }
        final archive = ZipDecoder().decodeBytes(await entity.readAsBytes(), verify: false);
        final picked = _pickArchiveSubtitleEntry(
          archive: archive,
          track: meta,
          mediaType: mediaType,
          title: title,
          year: year,
          season: season,
          episode: episode,
        );
        if (picked == null) continue;
        final rawContent = picked.content;
        final bytes = rawContent is Uint8List
            ? rawContent
            : (rawContent is List<int> ? Uint8List.fromList(rawContent) : null);
        if (bytes == null || bytes.isEmpty) continue;
        final mimeType = _subtitleMimeFromName(picked.name).ifEmpty('application/x-subrip');
        final ext = picked.name.toLowerCase().endsWith('.vtt')
            ? '.vtt'
            : picked.name.toLowerCase().endsWith('.ass')
                ? '.ass'
                : picked.name.toLowerCase().endsWith('.ssa')
                    ? '.ssa'
                    : '.srt';
        final uniquePart = '${entity.path}|${picked.name}|$episode'.hashCode.abs().toRadixString(16).padLeft(8, '0');
        final file = File('${targetDir.path}/${_sanitizeFileName(baseName)} - cached-$uniquePart$ext');
        if (!await file.exists()) {
          await file.writeAsBytes(bytes, flush: true);
        }
        final item = Map<String, String>.from(meta);
        item['label'] = (meta['label'] ?? meta['release'] ?? 'Subtitle').trim().ifEmpty('Subtitle');
        item['url'] = Uri.file(file.path).toString();
        item['fileName'] = file.uri.pathSegments.last;
        item['mimeType'] = mimeType;
        item['cachedArchivePath'] = entity.path;
        out.add(item);
        if (out.length >= _primarySubsourceTargetTracks) break;
      }
      if (out.isEmpty) return const <Map<String, String>>[];
      final stored = await loadStoredTracks(
        mediaType: mediaType,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
      );
      final merged = _prioritizeStoredTrackMaps([...stored, ...out]).take(_maxStoredTracksPerItem).toList(growable: false);
      await _saveStoredTracks(
        mediaType: mediaType,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
        tracks: merged,
      );
      return merged;
    } catch (_) {
      return const <Map<String, String>>[];
    }
  }

  static Future<Map<String, String>?> _downloadTrackToFile({
    required Map<String, String> track,
    required Directory targetDir,
    required String baseName,
    required int index,
    required MediaType mediaType,
    String? title,
    int? year,
    int? season,
    int? episode,
  }) async {
    final remoteUrl = (track['url'] ?? '').trim();
    if (remoteUrl.isEmpty) return null;

    try {
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final downloadHeaders = <String, String>{
        'Accept': '*/*',
        'User-Agent': _ua,
      };
      final providerGroup = (track['providerGroup'] ?? '').trim().toLowerCase();
      final referer = (track['referer'] ?? '').trim();
      if (referer.isNotEmpty) downloadHeaders['Referer'] = referer;

      final Response<List<int>> response;
      if (providerGroup == 'subsource-api') {
        final apiKey = (await SubSourceApiKeyStore.currentKey()).trim();
        if (apiKey.isEmpty) return null;
        response = await _dio.get<List<int>>(
          remoteUrl,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(minutes: 2),
            headers: {
              ...downloadHeaders,
              'X-API-Key': apiKey,
              'Accept': 'application/zip, application/octet-stream, */*',
            },
            followRedirects: true,
            maxRedirects: 8,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
      } else if (providerGroup == 'subsource-free-api') {
        final subId = (track['subtitleId'] ?? '').trim();
        if (subId.isEmpty) return null;
        response = await _dio.post<List<int>>(
          remoteUrl,
          data: jsonEncode(<String, dynamic>{'id': subId}),
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(minutes: 2),
            headers: {
              ...downloadHeaders,
              'Accept': 'application/octet-stream, application/zip, */*',
              'Content-Type': 'application/json',
              'Origin': 'https://subsource.net',
              'Referer': 'https://subsource.net/',
            },
            validateStatus: (s) => s != null && s < 500,
          ),
        );
      } else {
        response = await _dio.get<List<int>>(
          remoteUrl,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(minutes: 2),
            headers: downloadHeaders,
            followRedirects: true,
            maxRedirects: 8,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
      }

      final bytes = Uint8List.fromList(response.data ?? const <int>[]);
      if (bytes.isEmpty) return null;

      final contentType = (response.headers.map['content-type']?.join(';') ?? '').toLowerCase();
      final hintedMime = (track['mimeType'] ?? '').trim().toLowerCase();
      if (contentType.contains('text/html')) return null;
      final archiveLike = _isSubtitleArchiveUrl(remoteUrl) || contentType.contains('zip') || contentType.contains('compressed') || hintedMime.contains('zip');

      String ext = '.srt';
      String outputNameHint = '';
      Uint8List fileBytes = bytes;
      String resolvedMimeType = (track['mimeType'] ?? '').trim();

      if (archiveLike) {
        Archive archive;
        try {
          archive = ZipDecoder().decodeBytes(bytes, verify: false);
        } catch (_) {
          return null;
        }
        await _storeSubtitleArchiveCache(
          track: track,
          bytes: bytes,
          targetDir: targetDir,
        );
        final picked = _pickArchiveSubtitleEntry(
          archive: archive,
          track: track,
          mediaType: mediaType,
          title: title,
          year: year,
          season: season,
          episode: episode,
        );
        if (picked == null) return null;

        final rawContent = picked.content;
        if (rawContent is List<int>) {
          fileBytes = Uint8List.fromList(rawContent);
        } else if (rawContent is Uint8List) {
          fileBytes = rawContent;
        } else {
          return null;
        }
        outputNameHint = picked.name;
        resolvedMimeType = _subtitleMimeFromName(picked.name);
      }

      final mimeType = resolvedMimeType.ifEmpty(
        _subtitleMimeFromName(outputNameHint.isNotEmpty ? outputNameHint : remoteUrl).ifEmpty(
          _subtitleMimeFromName(contentType),
        ),
      );
      if (!_isSupportedSubtitleMime(mimeType.isNotEmpty ? mimeType : contentType)) {
        return null;
      }

      final lowerHint = (outputNameHint.isNotEmpty ? outputNameHint : remoteUrl).toLowerCase();
      if (lowerHint.endsWith('.vtt')) {
        ext = '.vtt';
      } else if (lowerHint.endsWith('.ass')) ext = '.ass';
      else if (lowerHint.endsWith('.ssa')) ext = '.ssa';
      else if (lowerHint.endsWith('.ttml') || lowerHint.endsWith('.xml')) ext = '.ttml';
      else if (mimeType.contains('text/vtt')) ext = '.vtt';
      else if (mimeType.contains('x-ssa') || mimeType.contains('ssa') || mimeType.contains('ass')) ext = '.ass';
      else if (mimeType.contains('ttml') || mimeType.contains('xml')) ext = '.ttml';

      final sourcePart = _truncate(
        _sanitizeFileName((track['source'] ?? 'Subtitle').replaceAll('•', '-')),
        18,
      );
      final labelPart = _truncate(
        _sanitizeFileName((track['label'] ?? 'Subtitle').replaceAll('•', '-')),
        52,
      );
      final uniqueSeed = '$remoteUrl|${outputNameHint.isNotEmpty ? outputNameHint : (track['fileName'] ?? '')}';
      final uniquePart = uniqueSeed.hashCode.abs().toRadixString(16).padLeft(8, '0');
      final fileName = '${_sanitizeFileName(baseName)} ${index.toString().padLeft(2, '0')} - $sourcePart - $labelPart - $uniquePart$ext';
      final file = File('${targetDir.path}/$fileName');
      await file.writeAsBytes(fileBytes, flush: true);

      final resolvedSubtitleMime = mimeType.ifEmpty(_subtitleMimeFromName(file.path));
      final webInlineFileName = outputNameHint.trim().isNotEmpty ? outputNameHint.trim() : fileName;
      final webInlineDataUrl = 'data:${resolvedSubtitleMime.ifEmpty('application/x-subrip')};base64,${base64Encode(fileBytes)}';

      return {
        'label': track['label'] ?? 'Subtitle',
        // On Web/PWA there is no readable local file system for the JS subtitle
        // overlay. The existing subtitle pipeline already downloaded the ZIP and
        // extracted the selected SRT/VTT/ASS into fileBytes above, so pass the
        // extracted subtitle directly as a data URL. Do NOT fetch SubDL again and
        // do NOT send subtitle downloads through the resolver Worker.
        'url': kIsWeb ? webInlineDataUrl : Uri.file(file.path).toString(),
        'language': track['language'] ?? '',
        'source': (track['source'] ?? 'Subtitle').trim().ifEmpty('Subtitle'),
        if ((track['providerGroup'] ?? '').trim().isNotEmpty) 'providerGroup': (track['providerGroup'] ?? '').trim(),
        'release': (track['release'] ?? '').trim(),
        if ((track['commentary'] ?? '').trim().isNotEmpty) 'commentary': (track['commentary'] ?? '').trim(),
        if ((track['matchRank'] ?? '').trim().isNotEmpty) 'matchRank': (track['matchRank'] ?? '').trim(),
        if ((track['subtitleId'] ?? '').trim().isNotEmpty) 'subtitleId': (track['subtitleId'] ?? '').trim(),
        if ((track['subsourceMovieId'] ?? '').trim().isNotEmpty) 'subsourceMovieId': (track['subsourceMovieId'] ?? '').trim(),
        if (mediaType == MediaType.movie && (title ?? '').trim().isNotEmpty) 'movieTitle': (title ?? '').trim(),
        if (mediaType == MediaType.movie && year != null && year > 1900) 'movieYear': year.toString(),
        'remoteUrl': remoteUrl,
        'fileName': kIsWeb ? webInlineFileName : fileName,
        'mimeType': resolvedSubtitleMime,
        if (kIsWeb) 'webInlineSubtitle': 'true',
        if (kIsWeb) 'originalRemoteUrl': remoteUrl,
      };
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, String>>> _downloadAndMergeMissingTracks({
    required List<Map<String, String>> existing,
    required List<Map<String, String>> fetched,
    required MediaType mediaType,
    required int tmdbId,
    required String title,
    int? year,
    int? season,
    int? episode,
    void Function(String message)? onProgress,
  }) async {
    var mergedExisting = _prioritizeStoredTrackMaps(existing)
        .where((track) => !_isArchiveSubtitleTrackMap(track))
        .where((track) => _trackMatchesRequestedMovie(
              track,
              mediaType: mediaType,
              title: title,
              year: year,
            ))
        .take(_maxStoredTracksPerItem)
        .toList(growable: false);
    final fetchedSanitized = _prioritizeStoredTrackMaps(fetched);
    final existingHasPrimary = _hasPrimarySubsourceTrack(mergedExisting);
    final fetchedHasPrimary = _hasPrimarySubsourceTrack(fetchedSanitized);
    if (mergedExisting.length >= _maxStoredTracksPerItem) {
      if (fetchedHasPrimary && !existingHasPrimary) {
        final removableIndex = mergedExisting.lastIndexWhere(_isSubdlTrackMap);
        if (removableIndex >= 0) {
          mergedExisting.removeAt(removableIndex);
        } else {
          mergedExisting = mergedExisting.take(_maxStoredTracksPerItem - 1).toList(growable: false);
        }
      } else {
        return mergedExisting.take(_maxStoredTracksPerItem).toList(growable: false);
      }
    }

    final existingIds = mergedExisting
        .map(_subtitleTrackIdentity)
        .toSet();

    final localExtras = <Map<String, String>>[];
    final remoteCandidates = <Map<String, String>>[];
    final seenIds = <String>{...existingIds};

    for (final track in fetchedSanitized) {
      final rawUrl = (track['url'] ?? '').trim();
      if (rawUrl.isEmpty) continue;
      final identity = _subtitleTrackIdentity(track);
      if (!seenIds.add(identity)) continue;
      final lowerUrl = rawUrl.toLowerCase();
      if (lowerUrl.startsWith('file://')) {
        localExtras.add(track);
        continue;
      }
      remoteCandidates.add(track);
    }

    if (localExtras.isNotEmpty) {
      mergedExisting = _mergeStoredTrackMaps([
        ...mergedExisting,
        ...localExtras,
      ]).take(_maxStoredTracksPerItem).toList(growable: false);
      await _saveStoredTracks(
        mediaType: mediaType,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
        tracks: mergedExisting,
      );
    }

    if (remoteCandidates.isEmpty || mergedExisting.length >= _maxStoredTracksPerItem) {
      return mergedExisting.take(_maxStoredTracksPerItem).toList(growable: false);
    }

    onProgress?.call('جارِ تنزيل الترجمات...');
    final dir = await _targetDirForItem(
      mediaType: mediaType,
      tmdbId: tmdbId,
      title: title,
      year: year,
      season: season,
      episode: episode,
    );

    final baseName = mediaType == MediaType.movie
        ? (year != null && year > 1900 ? '${title.trim()} ($year)' : title.trim())
        : '${title.trim()} S${(season ?? 0).toString().padLeft(2, '0')}E${(episode ?? 0).toString().padLeft(2, '0')}';

    final selectedRemoteCandidates = _pickStrictSubtitleCandidates(
      remoteCandidates,
      mediaType: mediaType,
      title: title,
      year: year,
      season: season,
      episode: episode,
    );
    if (selectedRemoteCandidates.isEmpty) {
      return mergedExisting.take(_maxStoredTracksPerItem).toList(growable: false);
    }

    final downloads = await Future.wait(
      selectedRemoteCandidates.asMap().entries.map((entry) {
        return _downloadTrackToFile(
          track: entry.value,
          targetDir: dir,
          baseName: baseName,
          index: mergedExisting.length + entry.key + 1,
          mediaType: mediaType,
          title: title,
          year: year,
          season: season,
          episode: episode,
        );
      }),
    );

    final saved = downloads.whereType<Map<String, String>>().toList(growable: false);
    if (saved.isEmpty) {
      return mergedExisting.take(_maxStoredTracksPerItem).toList(growable: false);
    }
    mergedExisting = _prioritizeStoredTrackMaps([
      ...saved,
      ...mergedExisting,
    ]).take(_maxStoredTracksPerItem).toList(growable: false);

    await _saveStoredTracks(
      mediaType: mediaType,
      tmdbId: tmdbId,
      season: season,
      episode: episode,
      tracks: mergedExisting,
    );

    return mergedExisting;
  }

  static Future<List<Map<String, String>>> persistTracksForItem({
    required int tmdbId,
    required MediaType mediaType,
    required String title,
    required Iterable<Map<String, String>> tracks,
    int? year,
    int? season,
    int? episode,
    void Function(String message)? onProgress,
  }) async {
    final existing = await loadStoredTracks(
      mediaType: mediaType,
      tmdbId: tmdbId,
      season: season,
      episode: episode,
    );
    final sanitized = _prioritizeStoredTrackMaps(tracks).take(_maxStoredTracksPerItem).toList(growable: false);
    if (sanitized.isEmpty) {
      return existing;
    }
    return _downloadAndMergeMissingTracks(
      existing: existing,
      fetched: sanitized,
      mediaType: mediaType,
      tmdbId: tmdbId,
      title: title,
      year: year,
      season: season,
      episode: episode,
      onProgress: onProgress,
    );
  }

  static Future<List<Map<String, String>>> prepareArabicTracksForPlayback({
    required int tmdbId,
    required MediaType mediaType,
    required String title,
    int? year,
    int? season,
    int? episode,
    void Function(String message)? onProgress,
  }) async {
    final stored = await loadStoredTracks(
      mediaType: mediaType,
      tmdbId: tmdbId,
      season: season,
      episode: episode,
    );

    final compatibleStored = stored
        .where((track) => _trackMatchesRequestedMovie(
              track,
              mediaType: mediaType,
              title: title,
              year: year,
            ))
        .toList(growable: false);

    var effectiveStored = compatibleStored;
    if (!_hasCompleteStoredSubtitleSet(effectiveStored)) {
      final fromSeasonArchives = await _extractTracksFromCachedSeasonArchives(
        mediaType: mediaType,
        tmdbId: tmdbId,
        title: title,
        year: year,
        season: season,
        episode: episode,
      );
      if (fromSeasonArchives.isNotEmpty) {
        effectiveStored = _prioritizeStoredTrackMaps([
          ...effectiveStored,
          ...fromSeasonArchives,
        ]).take(_maxStoredTracksPerItem).toList(growable: false);
      }
    }

    if (_hasCompleteStoredSubtitleSet(effectiveStored)) {
      onProgress?.call('تم العثور على ${effectiveStored.length} ترجمة محفوظة.');
      return effectiveStored;
    }

    if (effectiveStored.isNotEmpty) {
      onProgress?.call('تم العثور على ${effectiveStored.length} ترجمة محفوظة، جارِ البحث عن بقية الترجمات...');
    }

    final fetched = await fetchArabicTracks(
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      year: year,
      season: season,
      episode: episode,
      onProgress: onProgress,
    );

    if (fetched.isEmpty) {
      if (effectiveStored.isNotEmpty) {
        onProgress?.call('تم الإبقاء على ${effectiveStored.length} ترجمة محفوظة فقط.');
        return effectiveStored;
      }
      return const <Map<String, String>>[];
    }

    final merged = await _downloadAndMergeMissingTracks(
      existing: effectiveStored,
      fetched: fetched,
      mediaType: mediaType,
      tmdbId: tmdbId,
      title: title,
      year: year,
      season: season,
      episode: episode,
      onProgress: onProgress,
    );

    final result = merged.isNotEmpty ? merged : effectiveStored;
    onProgress?.call(
      result.isEmpty
          ? 'لم يتم حفظ أي ترجمة عربية.'
          : 'تم تجهيز ${result.length} ترجمة عربية، جارِ فتح المشغل...',
    );
    return result;
  }

  static Future<void> topUpArabicSubtitleCache({
    required int tmdbId,
    required MediaType mediaType,
    required String title,
    int? year,
    int? season,
    int? episode,
  }) async {
    final stored = await loadStoredTracks(
      mediaType: mediaType,
      tmdbId: tmdbId,
      season: season,
      episode: episode,
    );
    final compatibleStored = stored
        .where((track) => _trackMatchesRequestedMovie(
              track,
              mediaType: mediaType,
              title: title,
              year: year,
            ))
        .toList(growable: false);
    if (_hasCompleteStoredSubtitleSet(compatibleStored)) return;

    final fetched = await fetchArabicTracks(
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      year: year,
      season: season,
      episode: episode,
    );
    if (fetched.isEmpty) return;

    await _downloadAndMergeMissingTracks(
      existing: compatibleStored,
      fetched: fetched,
      mediaType: mediaType,
      tmdbId: tmdbId,
      title: title,
      year: year,
      season: season,
      episode: episode,
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
  final List<int> _tabHistory = <int>[0];
  final Map<String, MediaItem> _saved = {};
  final Set<int> _openedTabs = <int>{0};

  bool _isSaved(MediaItem item) => _saved.containsKey(item.key);

  void _toggleSaved(MediaItem item) => setState(() {
        if (_saved.containsKey(item.key)) {
          _saved.remove(item.key);
        } else {
          _saved[item.key] = item;
        }
      });

  bool handleBackWithinLightOnRoot() {
    if (_tabHistory.length > 1) {
      setState(() {
        _tabHistory.removeLast();
        _tab = _tabHistory.last;
        _openedTabs.add(_tab);
      });
      return true;
    }

    if (_tab != 0) {
      setState(() {
        _tab = 0;
        _openedTabs.add(0);
        _tabHistory
          ..clear()
          ..add(0);
      });
      return true;
    }

    return false;
  }

  void _openDetails(MediaItem item) {
    unawaited(WatchHistoryStore.push(item));
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DetailsPage(
        item: item,
        isSaved: _isSaved(item),
        onToggleSave: () => _toggleSaved(item),
      ),
    ));
  }

  void _showAbout() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2D2D30),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('حول التطبيق',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            SizedBox(height: 12),
            Text(
              'This product uses the TMDB API but is not endorsed or certified by TMDB.',
              style: TextStyle(color: Colors.white70, height: 1.7),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageBuilders = <WidgetBuilder>[
      (_) => HomePage(onOpen: _openDetails),
      (_) => CatalogPage(title: 'الأفلام', type: MediaType.movie, onOpen: _openDetails),
      (_) => CatalogPage(title: 'المسلسلات', type: MediaType.tv, onOpen: _openDetails),
      (_) => SearchPage(onOpen: _openDetails),
      (_) => SavedPage(
            items: _saved.values.where((e) => e.hasVisibleRating).toList(),
            onOpen: _openDetails,
          ),
    ];

    final hasInternalBack = _tabHistory.length > 1 || _tab != 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (hasInternalBack) {
          handleBackWithinLightOnRoot();
        }
        // At Light On root on Web/PWA, do nothing. This prevents Android
        // Chrome Back from jumping to the selector or closing the site after
        // returning from Details.
      },
      child: Scaffold(

      backgroundColor: Colors.transparent,
      extendBody: false,
      body: CinematicBackground(
        child: SafeArea(
          bottom: false,
          child: _LazyTabStack(
            index: _tab,
            openedTabs: _openedTabs,
            builders: pageBuilders,
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF2D2D30),
          border: Border(top: BorderSide(color: Color(0xFF3A3A3D))),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            height: 68,
            elevation: 0,
            backgroundColor: const Color(0xFF2D2D30),
            selectedIndex: _tab,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (i) {
              if (i == _tab) return;
              setState(() {
                _tabHistory.remove(i);
                _tabHistory.add(i);
                _tab = i;
                _openedTabs.add(i);
              });
            },
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'الرئيسية'),
              NavigationDestination(
                  icon: Icon(Icons.movie_outlined),
                  selectedIcon: Icon(Icons.movie),
                  label: 'الأفلام'),
              NavigationDestination(
                  icon: Icon(Icons.tv_outlined),
                  selectedIcon: Icon(Icons.tv),
                  label: 'المسلسلات'),
              NavigationDestination(
                  icon: Icon(Icons.search_outlined),
                  selectedIcon: Icon(Icons.search),
                  label: 'البحث'),
              NavigationDestination(
                  icon: Icon(Icons.bookmark_outline),
                  selectedIcon: Icon(Icons.bookmark),
                  label: 'مكتبتي'),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _LazyTabStack extends StatelessWidget {
  final int index;
  final Set<int> openedTabs;
  final List<WidgetBuilder> builders;

  const _LazyTabStack({
    required this.index,
    required this.openedTabs,
    required this.builders,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < builders.length; i++)
          if (openedTabs.contains(i))
            Offstage(
              offstage: index != i,
              child: TickerMode(
                enabled: index == i,
                child: RepaintBoundary(
                  child: KeyedSubtree(
                    key: ValueKey('tab-$i'),
                    child: builders[i](context),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  PAGES
// ══════════════════════════════════════════════════════════════════════════════

class HomePage extends StatefulWidget {
  final ValueChanged<MediaItem> onOpen;

  const HomePage({super.key, required this.onOpen});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ScrollController _scrollController;
  late Future<HomeData> _homeFuture;
  HomeData? _visibleHomeData;
  Object? _loadMoreError;
  bool _loadingMore = false;
  bool _fullRequested = false;
  bool _fullLoaded = false;
  Timer? _silentFullTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
    _homeFuture = Future<HomeData>.delayed(
      const Duration(milliseconds: 250),
      () => _loadInitialHome(),
    );
  }

  @override
  void dispose() {
    _silentFullTimer?.cancel();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<HomeData> _loadInitialHome({bool forceRefresh = false}) async {
    final data = await TmdbService.instance.fetchHome(
      forceRefresh: forceRefresh,
      profile: HomeFetchProfile.preview,
    );
    if (mounted) {
      setState(() {
        _visibleHomeData = data;
      });
    } else {
      _visibleHomeData = data;
    }
    return data;
  }

  bool _onHomeScrollNotification(ScrollNotification notification) {
    return false;
  }

  void _handleScroll() {
  }

  Future<void> _requestMoreHomeItems() async {
    if (_fullLoaded || _loadingMore || _fullRequested) return;
    await _loadRemainingHome();
  }

  Future<void> _loadRemainingHome({bool forceRefresh = false}) async {
    if (_loadingMore || _fullLoaded) return;
    _silentFullTimer?.cancel();
    _fullRequested = true;
    if (mounted) {
      setState(() {
        _loadingMore = true;
        _loadMoreError = null;
      });
    } else {
      _loadingMore = true;
      _loadMoreError = null;
    }

    try {
      final data = await TmdbService.instance.fetchHome(
        forceRefresh: forceRefresh,
        profile: HomeFetchProfile.full,
      );
      if (mounted) {
        setState(() {
          _visibleHomeData = data;
          _loadingMore = false;
          _fullLoaded = true;
        });
      } else {
        _visibleHomeData = data;
        _loadingMore = false;
        _fullLoaded = true;
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadingMore = false;
          _loadMoreError = error;
        });
      } else {
        _loadingMore = false;
        _loadMoreError = error;
      }
      _fullRequested = false;
    }
  }

  Future<void> _reloadHome() async {
    _silentFullTimer?.cancel();
    _fullRequested = false;
    _fullLoaded = false;
    _loadMoreError = null;
    _loadingMore = false;
    final future = _loadInitialHome(forceRefresh: true);
    if (mounted) {
      setState(() {
        _visibleHomeData = null;
        _homeFuture = future;
      });
    } else {
      _visibleHomeData = null;
      _homeFuture = future;
    }
    await future;
  }

  Widget _buildLoadMoreRetry() {
    if (_visibleHomeData == null || _loadMoreError == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Center(
        child: FilledButton(
          onPressed: () => _loadRemainingHome(forceRefresh: true),
          child: const Text('إعادة تحميل بقية العناصر'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HomeData>(
      future: _homeFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError && _visibleHomeData == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'فشل تحميل TMDB\n\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          );
        }
        if (!snapshot.hasData && _visibleHomeData == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = _visibleHomeData ?? snapshot.data!;
        return RefreshIndicator(
          onRefresh: _reloadHome,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onHomeScrollNotification,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: HeroCarousel(items: data.featured, onOpen: widget.onOpen),
                ),
                SliverToBoxAdapter(
                  child: FutureBuilder<List<MediaItem>>(
                    future: WatchHistoryStore.loadRecent(),
                    builder: (context, historySnapshot) {
                      final recent = historySnapshot.data ?? const <MediaItem>[];
                      if (recent.isEmpty) return const SizedBox.shrink();
                      return SectionBlock(
                        title: 'آخر ما شاهدته',
                        child: HorizontalMediaList(
                          items: recent,
                          genres: data.genres,
                          onOpen: widget.onOpen,
                        ),
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: SectionBlock(
                    title: 'أحدث الأفلام',
                    child: HorizontalMediaList(
                      items: data.latest,
                      genres: data.genres,
                      onOpen: widget.onOpen,
                      onNeedMore: _requestMoreHomeItems,
                      hasMoreSource: !_fullLoaded,
                      loadingMore: _loadingMore,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SectionBlock(
                    title: 'المسلسلات الجديدة والنشطة',
                    child: HorizontalMediaList(
                      items: data.featuredSeries,
                      genres: data.genres,
                      onOpen: widget.onOpen,
                      onNeedMore: _requestMoreHomeItems,
                      hasMoreSource: !_fullLoaded,
                      loadingMore: _loadingMore,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SectionBlock(
                    title: 'الأفلام الجديدة والمميزة',
                    child: HorizontalMediaList(
                      items: data.featuredMovies,
                      genres: data.genres,
                      onOpen: widget.onOpen,
                      onNeedMore: _requestMoreHomeItems,
                      hasMoreSource: !_fullLoaded,
                      loadingMore: _loadingMore,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SectionBlock(
                    title: 'أحدث المسلسلات',
                    child: HorizontalMediaList(
                      items: data.latestSeries,
                      genres: data.genres,
                      onOpen: widget.onOpen,
                      onNeedMore: _requestMoreHomeItems,
                      hasMoreSource: !_fullLoaded,
                      loadingMore: _loadingMore,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SectionBlock(
                    title: 'الأفلام الأعلى تقييمًا',
                    child: HorizontalMediaList(
                      items: data.topRatedMovies,
                      genres: data.genres,
                      onOpen: widget.onOpen,
                      onNeedMore: _requestMoreHomeItems,
                      hasMoreSource: !_fullLoaded,
                      loadingMore: _loadingMore,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SectionBlock(
                    title: 'المسلسلات الأعلى تقييمًا',
                    child: HorizontalMediaList(
                      items: data.topRatedSeries,
                      genres: data.genres,
                      onOpen: widget.onOpen,
                      onNeedMore: _requestMoreHomeItems,
                      hasMoreSource: !_fullLoaded,
                      loadingMore: _loadingMore,
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _buildLoadMoreRetry()),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Catalog ─────────────────────────────────────────────────────────────────

class CatalogPage extends StatefulWidget {
  final String title;
  final MediaType type;
  final ValueChanged<MediaItem> onOpen;

  const CatalogPage({
    super.key,
    required this.title,
    required this.type,
    required this.onOpen,
  });

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late final Future<GenreMaps> _genresFuture;
  late final ScrollController _scrollController;
  final List<MediaItem> _items = [];
  final Set<int> _selectedGenreIds = {};
  double _minRating = 0;
  SortMode _sortMode = SortMode.newest;
  RangeValues? _yearRange;
  bool _filtersApplied = false;
  int _page = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _genresFuture = TmdbService.instance.fetchGenres();
    _scrollController = ScrollController()..addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 700) _loadMore();
  }

  Future<void> _refresh() async {
    setState(() {
      _items.clear();
      _page = 1;
      _hasMore = true;
      _loadError = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final range = _yearRange;
      final newItems = await TmdbService.instance.fetchCatalogPage(
        widget.type,
        _page,
        sortMode: _sortMode,
        minRating: _filtersApplied ? _minRating : 0,
        genreIds:
            _filtersApplied ? _selectedGenreIds.toList(growable: false) : const <int>[],
        yearStart: _filtersApplied ? range?.start.round() : null,
        yearEnd: _filtersApplied ? range?.end.round() : null,
      );
      final existingKeys = _items.map((e) => e.key).toSet();
      final uniqueNew = <MediaItem>[];
      for (final item in newItems) {
        if (!existingKeys.contains(item.key)) {
          existingKeys.add(item.key);
          uniqueNew.add(item);
        }
      }
      setState(() {
        _items.addAll(uniqueNew);
        _page++;
        _hasMore = newItems.isNotEmpty;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e;
        _isLoading = false;
      });
    }
  }

  Future<void> _reloadFromFirstPage() async {
    setState(() {
      _items.clear();
      _page = 1;
      _hasMore = true;
      _loadError = null;
    });
    await _loadMore();
  }

  void _reset(int minYear, int maxYear) => setState(() {
        _selectedGenreIds.clear();
        _minRating = 0;
        _sortMode = SortMode.newest;
        _yearRange = RangeValues(minYear.toDouble(), maxYear.toDouble());
        _filtersApplied = false;
      });

  void _openFilters(
      List<MediaItem> items, Map<int, String> genreMap, int minYear, int maxYear) {
    final currentRange =
        _yearRange ?? RangeValues(minYear.toDouble(), maxYear.toDouble());
    final tempGenreIds = <int>{..._selectedGenreIds};
    double tempRating = _minRating;
    SortMode tempSort = _sortMode;
    RangeValues tempRange = currentRange;
    final allGenres = genreMap.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2D2D30),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.white,
              secondary: Colors.white,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1B1B1E),
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            sliderTheme: Theme.of(context).sliderTheme.copyWith(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
              activeTickMarkColor: const Color(0xFF1B1B1E),
              inactiveTickMarkColor: Colors.white24,
              valueIndicatorColor: Colors.white,
              valueIndicatorTextStyle: const TextStyle(color: Color(0xFF1B1B1E)),
              rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
            ),
            chipTheme: Theme.of(context).chipTheme.copyWith(
              selectedColor: Colors.white,
              secondarySelectedColor: Colors.white,
              checkmarkColor: const Color(0xFF1B1B1E),
              side: const BorderSide(color: Colors.white),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.white),
              ),
              labelStyle: const TextStyle(color: Colors.white),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              child: SingleChildScrollView(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('فلاتر ${widget.title}',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setSheet(() {
                          tempGenreIds.clear();
                          tempRating = 0;
                          tempSort = SortMode.newest;
                          tempRange = RangeValues(
                              minYear.toDouble(), maxYear.toDouble());
                        }),
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        child: const Text('إعادة ضبط'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text('الترتيب',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: SortMode.values
                        .where((mode) => mode != SortMode.smart)
                        .map((mode) => ChoiceChip(
                              label: Text(
                                mode.label,
                                style: TextStyle(
                                  color: tempSort == mode
                                      ? const Color(0xFF1B1B1E)
                                      : Colors.white,
                                ),
                              ),
                              selected: tempSort == mode,
                              showCheckmark: true,
                              onSelected: (_) =>
                                  setSheet(() => tempSort = mode),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 22),
                  const Text('النوع',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: allGenres
                        .map((entry) {
                          final selected = tempGenreIds.contains(entry.key);
                          return FilterChip(
                            label: Text(
                              entry.value,
                              style: TextStyle(
                                color: selected
                                    ? const Color(0xFF1B1B1E)
                                    : Colors.white,
                              ),
                            ),
                            selected: selected,
                            showCheckmark: true,
                            onSelected: (_) => setSheet(() => selected
                                ? tempGenreIds.remove(entry.key)
                                : tempGenreIds.add(entry.key)),
                          );
                        })
                        .toList(),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'السنة: ${tempRange.start.round()} - ${tempRange.end.round()}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white24,
                      valueIndicatorColor: Colors.white,
                      valueIndicatorTextStyle:
                          const TextStyle(color: Color(0xFF1B1B1E)),
                    ),
                    child: RangeSlider(
                      min: minYear.toDouble(),
                      max: maxYear.toDouble(),
                      divisions: (maxYear - minYear).clamp(1, 100),
                      values: tempRange,
                      labels: RangeLabels('${tempRange.start.round()}',
                          '${tempRange.end.round()}'),
                      onChanged: (v) => setSheet(() => tempRange = v),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('أقل تقييم: ${tempRating.toStringAsFixed(1)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 17)),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white24,
                      valueIndicatorColor: Colors.white,
                      valueIndicatorTextStyle:
                          const TextStyle(color: Color(0xFF1B1B1E)),
                    ),
                    child: Slider(
                      min: 0,
                      max: 10,
                      divisions: 20,
                      value: tempRating,
                      label: tempRating.toStringAsFixed(1),
                      onChanged: (v) => setSheet(() => tempRating = v),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1B1B1E),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedGenreIds
                            ..clear()
                            ..addAll(tempGenreIds);
                          _minRating = tempRating;
                          _sortMode = tempSort;
                          _yearRange = RangeValues(
                            tempRange.start.round().toDouble(),
                            tempRange.end.round().toDouble(),
                          );
                          _filtersApplied = tempGenreIds.isNotEmpty ||
                              tempRating > 0 ||
                              tempSort != SortMode.newest ||
                              _yearRange!.start.round() != minYear ||
                              _yearRange!.end.round() != maxYear;
                        });
                        Navigator.pop(context);
                        unawaited(_reloadFromFirstPage());
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('تطبيق الفلاتر'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  List<MediaItem> _applyFilters(
      List<MediaItem> items, Map<int, String> genreMap, int minYear, int maxYear) {
    if (!_filtersApplied) {
      return List<MediaItem>.from(items, growable: false);
    }

    final range =
        _yearRange ?? RangeValues(minYear.toDouble(), maxYear.toDouble());
    final filtered = items.where((item) {
      final year = item.releaseDate?.year ?? 0;
      final yearOk =
          year >= range.start.round() && year <= range.end.round();
      final ratingOk = item.rating >= _minRating;
      final selectedRealGenreIds = _selectedGenreIds
          .where((id) => !(widget.type == MediaType.tv && id == TmdbService._tvHorrorPseudoGenreId))
          .toSet();
      final hasTvHorrorFilter =
          widget.type == MediaType.tv && _selectedGenreIds.contains(TmdbService._tvHorrorPseudoGenreId);
      final genreOk = _selectedGenreIds.isEmpty ||
          (hasTvHorrorFilter && selectedRealGenreIds.isEmpty) ||
          item.genreIds.any((id) => selectedRealGenreIds.contains(id));
      return yearOk && ratingOk && genreOk;
    }).toList();

    filtered.sort((a, b) {
      switch (_sortMode) {
        case SortMode.newest:
          return (b.releaseDate ?? DateTime(1900))
              .compareTo(a.releaseDate ?? DateTime(1900));
        case SortMode.oldest:
          return (a.releaseDate ?? DateTime(1900))
              .compareTo(b.releaseDate ?? DateTime(1900));
        case SortMode.ratingHigh:
          return b.rating.compareTo(a.rating);
        case SortMode.ratingLow:
          return a.rating.compareTo(b.rating);
        case SortMode.titleAZ:
          return a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
        case SortMode.smart:
          return (b.releaseDate ?? DateTime(1900))
              .compareTo(a.releaseDate ?? DateTime(1900));
      }
    });
    return filtered;
  }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GenreMaps>(
      future: _genresFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return CustomScrollView(
            slivers: [
              SliverAppBar(pinned: true, title: Text(widget.title)),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'فشل تحميل التصنيفات\n\n' '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        if (!snapshot.hasData) {
          return CustomScrollView(
            slivers: [
              SliverAppBar(pinned: true, title: Text(widget.title)),
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          );
        }

        final maps = snapshot.data!;
        final genreMap = widget.type == MediaType.movie ? maps.movie : maps.tv;
        const minYear = 1900;
        final maxYear = DateTime.now().year;
        if (!_filtersApplied) {
          _yearRange = RangeValues(minYear.toDouble(), maxYear.toDouble());
        } else {
          _yearRange ??= RangeValues(minYear.toDouble(), maxYear.toDouble());
        }
        final filtered = _applyFilters(_items, genreMap, minYear, maxYear);

        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                pinned: true,
                title: Text(widget.title),
                actions: [
                  IconButton(
                    tooltip: 'فلاتر',
                    onPressed: _items.isEmpty
                        ? null
                        : () => _openFilters(_items, genreMap, minYear, maxYear),
                    icon: const Icon(Icons.tune),
                  ),
                ],
              ),
              if (_items.isEmpty && _isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_items.isEmpty && _loadError != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'فشل تحميل ${widget.title}\n\n' '$_loadError',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _loadMore,
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (filtered.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'لا توجد نتائج مطابقة للفلاتر الحالية.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = filtered[index];
                        final genreLabel = item.genreIds.isEmpty
                            ? ''
                            : (genreMap[item.genreIds.first] ?? '');
                        return GestureDetector(
                          onTap: () => widget.onOpen(item),
                          child: PosterCard(item: item, genreLabel: genreLabel),
                        );
                      },
                      childCount: filtered.length,
                    ),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.48,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Center(
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : _loadError != null
                            ? FilledButton(
                                onPressed: _loadMore,
                                child: const Text('إعادة المحاولة'),
                              )
                            : (!_hasMore
                                ? const Text(
                                    'تم تحميل كل النتائج المتاحة.',
                                    style: TextStyle(color: Colors.white54),
                                  )
                                : const SizedBox.shrink()),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Search ───────────────────────────────────────────────────────────────────

class SearchPage extends StatefulWidget {
  final ValueChanged<MediaItem> onOpen;

  const SearchPage({super.key, required this.onOpen});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final Future<GenreMaps> _genresFuture;
  Future<List<MediaItem>>? _resultsFuture;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _genresFuture = TmdbService.instance.fetchGenres();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final query = value.trim();
      setState(() {
        _resultsFuture =
            query.isEmpty ? null : TmdbService.instance.searchAll(query);
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GenreMaps>(
      future: _genresFuture,
      builder: (context, genreSnapshot) {
        if (genreSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (genreSnapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'فشل تحميل التصنيفات\n\n${genreSnapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          );
        }
        final genreMap = <int, String>{
          ...genreSnapshot.data!.movie,
          ...genreSnapshot.data!.tv,
        };
        return CustomScrollView(
          slivers: [
            const SliverAppBar(pinned: true, backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent, title: Text('البحث')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: TextField(
                  onChanged: _onChanged,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'ابحث عن فيلم أو مسلسل...',
                  ),
                ),
              ),
            ),
            if (_resultsFuture == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('اكتب اسم الفيلم أو المسلسل.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Colors.white70, height: 1.6)),
                  ),
                ),
              )
            else
              FutureBuilder<List<MediaItem>>(
                future: _resultsFuture,
                builder: (context, resultsSnapshot) {
                  if (resultsSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()));
                  }
                  if (resultsSnapshot.hasError) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'فشل البحث\n\n${resultsSnapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    );
                  }
                  final items = resultsSnapshot.data ?? [];
                  if (items.isEmpty) {
                    return const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                          child: Text('لا توجد نتائج.',
                              style: TextStyle(color: Colors.white70))),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = items[index];
                          final genreLabel = item.genreIds.isEmpty
                              ? ''
                              : (genreMap[item.genreIds.first] ?? '');
                          return GestureDetector(
                            onTap: () => widget.onOpen(item),
                            child: PosterCard(
                                item: item, genreLabel: genreLabel),
                          );
                        },
                        childCount: items.length,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.48,
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

// ─── Saved ────────────────────────────────────────────────────────────────────

class _DownloadLibraryMetadata {
  final String path;
  final String title;
  final String groupKey;
  final String? posterUrl;
  final String? thumbnailPath;
  final String? mediaType;
  final int? tmdbId;
  final int? season;
  final int? episode;
  final String? qualityLabel;
  final String? fileName;
  final String? status;
  final double? progress;
  final String? finalPath;
  final String? downloadId;
  final int createdAtMs;

  const _DownloadLibraryMetadata({
    required this.path,
    required this.title,
    required this.groupKey,
    this.posterUrl,
    this.thumbnailPath,
    this.mediaType,
    this.tmdbId,
    this.season,
    this.episode,
    this.qualityLabel,
    this.fileName,
    this.status,
    this.progress,
    this.finalPath,
    this.downloadId,
    required this.createdAtMs,
  });

  factory _DownloadLibraryMetadata.fromJson(Map<String, dynamic> json) {
    return _DownloadLibraryMetadata(
      path: (json['path'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      groupKey: (json['groupKey'] ?? '').toString(),
      posterUrl: (json['posterUrl'] ?? '').toString().trim().isEmpty ? null : (json['posterUrl'] ?? '').toString(),
      thumbnailPath: (json['thumbnailPath'] ?? '').toString().trim().isEmpty ? null : (json['thumbnailPath'] ?? '').toString(),
      mediaType: (json['mediaType'] ?? '').toString().trim().isEmpty ? null : (json['mediaType'] ?? '').toString(),
      tmdbId: (json['tmdbId'] as num?)?.toInt(),
      season: (json['season'] as num?)?.toInt(),
      episode: (json['episode'] as num?)?.toInt(),
      qualityLabel: (json['qualityLabel'] ?? '').toString().trim().isEmpty ? null : (json['qualityLabel'] ?? '').toString(),
      fileName: (json['fileName'] ?? '').toString().trim().isEmpty ? null : (json['fileName'] ?? '').toString(),
      status: (json['status'] ?? '').toString().trim().isEmpty ? null : (json['status'] ?? '').toString(),
      progress: (json['progress'] as num?)?.toDouble(),
      finalPath: (json['finalPath'] ?? '').toString().trim().isEmpty ? null : (json['finalPath'] ?? '').toString(),
      downloadId: (json['downloadId'] ?? '').toString().trim().isEmpty ? null : (json['downloadId'] ?? '').toString(),
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'title': title,
        'groupKey': groupKey,
        if (posterUrl != null && posterUrl!.isNotEmpty) 'posterUrl': posterUrl,
        if (thumbnailPath != null && thumbnailPath!.isNotEmpty) 'thumbnailPath': thumbnailPath,
        if (mediaType != null && mediaType!.isNotEmpty) 'mediaType': mediaType,
        if (tmdbId != null) 'tmdbId': tmdbId,
        if (season != null) 'season': season,
        if (episode != null) 'episode': episode,
        if (qualityLabel != null && qualityLabel!.isNotEmpty) 'qualityLabel': qualityLabel,
        if (fileName != null && fileName!.isNotEmpty) 'fileName': fileName,
        if (status != null && status!.isNotEmpty) 'status': status,
        if (progress != null) 'progress': progress,
        if (finalPath != null && finalPath!.isNotEmpty) 'finalPath': finalPath,
        if (downloadId != null && downloadId!.isNotEmpty) 'downloadId': downloadId,
        'createdAtMs': createdAtMs,
      };
}

class _DownloadLibraryIndexStore {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/download_library_index.json');
  }

  static Future<Map<String, _DownloadLibraryMetadata>> loadIndex() async {
    try {
      final file = await _file();
      if (!await file.exists()) return <String, _DownloadLibraryMetadata>{};
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <String, _DownloadLibraryMetadata>{};
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String, _DownloadLibraryMetadata>{};
      final out = <String, _DownloadLibraryMetadata>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final meta = _DownloadLibraryMetadata.fromJson(Map<String, dynamic>.from(item));
        if (meta.path.trim().isEmpty) continue;
        out[meta.path] = meta;
      }
      return out;
    } catch (_) {
      return <String, _DownloadLibraryMetadata>{};
    }
  }

  static Future<void> _save(Map<String, _DownloadLibraryMetadata> items) async {
    final file = await _file();
    final list = items.values.map((e) => e.toJson()).toList(growable: false);
    await file.writeAsString(jsonEncode(list));
  }

  static Future<void> upsert(_DownloadLibraryMetadata metadata) async {
    final index = await loadIndex();
    index[metadata.path] = metadata;
    await _save(index);
  }

  static Future<void> remove(String path) async {
    final index = await loadIndex();
    if (index.remove(path) != null) {
      await _save(index);
    }
  }
}

class _LibraryDownloadGroup {
  final String id;
  final String title;
  final String? posterUrl;
  final String? thumbnailPath;
  final MediaType? mediaType;
  final List<_LibraryDownloadEntry> entries;

  const _LibraryDownloadGroup({
    required this.id,
    required this.title,
    this.posterUrl,
    this.thumbnailPath,
    this.mediaType,
    required this.entries,
  });
}

class SavedPage extends StatefulWidget {
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;

  const SavedPage({super.key, required this.items, required this.onOpen});

  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage> {
  static final MethodChannel _downloadPlayerChannel = MethodChannel(AppSecureText.s('IhmDL74rYtAK6atQiPOW'));
  static const String _backgroundDownloadSource = 'LightOn';

  Timer? _downloadsRefreshTimer;
  final Set<String> _expandedDownloadGroups = <String>{};
  List<_LibraryDownloadEntry> _downloadEntries = const <_LibraryDownloadEntry>[];
  bool _downloadsInitialLoading = true;
  bool _downloadsRefreshInFlight = false;
  String _downloadsSignature = '';
  String _subSourceApiPreview = '';

  String _maskSubSourceApiKey(String key) {
    final clean = key.trim();
    if (clean.isEmpty) return '';
    if (clean.length <= 12) return clean;
    return '${clean.substring(0, 6)}…${clean.substring(clean.length - 4)}';
  }

  Future<void> _refreshSubSourceApiPreview() async {
    final saved = await SubSourceApiKeyStore.savedKey();
    if (!mounted) return;
    setState(() {
      _subSourceApiPreview = _maskSubSourceApiKey(saved);
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refreshSubSourceApiPreview());
    unawaited(_refreshDownloads(initial: true));
    _downloadsRefreshTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      unawaited(_refreshDownloads());
    });
  }

  @override
  void dispose() {
    _downloadsRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _showSubSourceActivationDialog() async {
    final savedKey = await SubSourceApiKeyStore.savedKey();
    final controller = TextEditingController(text: savedKey);
    bool testing = false;
    String? errorText;
    var activePreview = _maskSubSourceApiKey(savedKey);
    var revealApiField = savedKey.trim().isEmpty;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !testing,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> testAndSave() async {
                final key = controller.text.trim();
                if (key.isEmpty) {
                  setDialogState(() => errorText = 'ضع API أولًا');
                  return;
                }

                setDialogState(() {
                  testing = true;
                  errorText = null;
                });

                final ok = await SubSourceApiKeyStore.validateKey(key);
                if (!dialogContext.mounted) return;

                if (!ok) {
                  setDialogState(() {
                    testing = false;
                    errorText = 'API خطأ أو غير فعال';
                  });
                  return;
                }

                await SubSourceApiKeyStore.saveKey(key);
                activePreview = _maskSubSourceApiKey(key);
                await _refreshSubSourceApiPreview();
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                if (mounted) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('تم تفعيل الترجمة')),
                  );
                }
              }

              Future<void> deleteKey() async {
                await SubSourceApiKeyStore.clearKey();
                controller.clear();
                await _refreshSubSourceApiPreview();
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  activePreview = '';
                  revealApiField = true;
                  errorText = null;
                });
                if (mounted) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('تم حذف API')),
                  );
                }
              }

              final hasActiveKey = activePreview.isNotEmpty;

              return AlertDialog(
                backgroundColor: const Color(0xFF2D2D30),
                titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                title: const Text(
                  'تفعيل الترجمة',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasActiveKey) ...[
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: testing
                              ? null
                              : () => setDialogState(() {
                                    revealApiField = !revealApiField;
                                  }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F8A3B),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'مفعل: $activePreview',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Icon(
                                  revealApiField
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (revealApiField)
                      TextField(
                        controller: controller,
                        enabled: !testing,
                        minLines: 1,
                        maxLines: 1,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          hintText: 'sk_...',
                          errorText: errorText,
                          prefixIcon: const Icon(Icons.key_rounded),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: testing ? null : deleteKey,
                    child: const Text('حذف'),
                  ),
                  FilledButton.icon(
                    onPressed: testing ? null : testAndSave,
                    icon: testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(testing ? 'جاري الاختبار...' : 'اختبار وحفظ'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Widget _buildSubSourceActivationButton() {
    final active = _subSourceApiPreview.isNotEmpty;
    return TextButton.icon(
      onPressed: _showSubSourceActivationDialog,
      style: TextButton.styleFrom(
        backgroundColor: active ? const Color(0xFF0F8A3B) : Colors.white,
        foregroundColor: active ? Colors.white : Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(
        active ? Icons.check_circle_rounded : Icons.closed_caption_rounded,
        size: 18,
        color: active ? Colors.white : Colors.black,
      ),
      label: Text(
        active ? 'مفعل' : 'تفعيل ترجمة',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }

  String _sanitizeFileName(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'subtitle';
    return trimmed
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _buildDownloadsSignature(List<_LibraryDownloadEntry> items) {
    return items.map((entry) {
      return [
        entry.path,
        entry.finalPath ?? '',
        entry.downloadId ?? '',
        entry.status,
        entry.progress.toStringAsFixed(4),
        entry.sizeBytes.toString(),
        entry.modifiedAt.millisecondsSinceEpoch.toString(),
      ].join('|');
    }).join('||');
  }

  Future<void> _refreshDownloads({bool initial = false, bool force = false}) async {
    if (_downloadsRefreshInFlight) return;
    _downloadsRefreshInFlight = true;
    try {
      final items = await _loadDownloads();
      final nextSignature = _buildDownloadsSignature(items);
      if (!mounted) return;
      if (initial || force || _downloadsInitialLoading || nextSignature != _downloadsSignature) {
        setState(() {
          _downloadEntries = items;
          _downloadsSignature = nextSignature;
          _downloadsInitialLoading = false;
        });
      } else if (_downloadsInitialLoading) {
        setState(() {
          _downloadsInitialLoading = false;
        });
      }
    } finally {
      _downloadsRefreshInFlight = false;
    }
  }

  Future<List<_LibraryDownloadEntry>> _loadDownloads() async {
    final roots = <Directory>[];
    final seen = <String>{};
    final metadataIndex = await _DownloadLibraryIndexStore.loadIndex();
    final activeSnapshots = <String, BackgroundDownloadSnapshot>{};
    try {
      final snapshots = await BackgroundDownloadBridge.list(source: _backgroundDownloadSource);
      for (final snap in snapshots) {
        if (snap.tempPath.trim().isNotEmpty) activeSnapshots[snap.tempPath.trim()] = snap;
        if (snap.finalPath.trim().isNotEmpty) activeSnapshots[snap.finalPath.trim()] = snap;
      }
    } catch (_) {}

    Future<void> addRoot(Directory dir) async {
      final key = dir.path;
      if (seen.add(key)) roots.add(dir);
    }

    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        await addRoot(Directory('${ext.path}/Videos'));
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    await addRoot(Directory('${appDir.path}/Videos'));

    final out = <_LibraryDownloadEntry>[];
    final seenFiles = <String>{};

    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final filePath = entity.path;
        if (!seenFiles.add(filePath)) continue;
        _DownloadLibraryMetadata? meta = metadataIndex[filePath];
        if (meta == null) {
          for (final candidate in metadataIndex.values) {
            if ((candidate.finalPath ?? '').trim() == filePath.trim()) {
              meta = candidate;
              break;
            }
          }
        }
        final isPartial = filePath.toLowerCase().endsWith('.downloading');
        if (!_isLibraryVideoFile(filePath) && !isPartial) continue;
        try {
          final stat = await entity.stat();
          final mediaType = meta?.mediaType == 'tv'
              ? MediaType.tv
              : (meta?.mediaType == 'movie' ? MediaType.movie : null);
          final title = (meta?.title ?? '').trim().isNotEmpty
              ? meta!.title.trim()
              : _guessLibraryTitleFromPath(meta?.finalPath ?? filePath);
          final groupKey = (meta?.groupKey ?? '').trim().isNotEmpty
              ? meta!.groupKey.trim()
              : title.toLowerCase();
          final active = activeSnapshots[filePath] ?? activeSnapshots[(meta?.finalPath ?? '').trim()];
          final normalizedStatus = (active?.status ?? meta?.status ?? (isPartial ? 'downloading' : 'done')).trim();
          final activeProgress = active?.progress;
          final activeId = (active?.id ?? meta?.downloadId ?? '').trim();
          out.add(_LibraryDownloadEntry(
            path: filePath,
            finalPath: (meta?.finalPath ?? '').trim().isEmpty ? null : meta!.finalPath,
            downloadId: activeId.isEmpty ? null : activeId,
            name: (meta?.fileName ?? (meta?.finalPath ?? filePath).split(Platform.pathSeparator).last).trim(),
            modifiedAt: stat.modified,
            sizeBytes: stat.size,
            title: title,
            groupKey: groupKey,
            posterUrl: meta?.posterUrl,
            thumbnailPath: meta?.thumbnailPath,
            mediaType: mediaType,
            tmdbId: meta?.tmdbId,
            season: meta?.season,
            episode: meta?.episode,
            qualityLabel: meta?.qualityLabel,
            status: normalizedStatus,
            progress: (activeProgress ?? meta?.progress ?? (normalizedStatus == 'done' ? 1.0 : 0.0)).clamp(0.0, 1.0),
          ));
        } catch (_) {}
      }
    }

    out.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return out;
  }

  bool _isLibraryVideoFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.m2ts') ||
        lower.endsWith('.flv');
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    final digits = size >= 100 ? 0 : (size >= 10 ? 1 : 2);
    return '${size.toStringAsFixed(digits)} ${units[unitIndex]}';
  }

  String _localVideoMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.m3u8')) return 'application/x-mpegURL';
    if (lower.endsWith('.mpd')) return 'application/dash+xml';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    return 'video/mp4';
  }

  String _localSubtitleMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.vtt')) return 'text/vtt';
    if (lower.endsWith('.srt')) return 'application/x-subrip';
    if (lower.endsWith('.ass') || lower.endsWith('.ssa')) return 'text/x-ssa';
    if (lower.endsWith('.ttml') || lower.endsWith('.xml')) return 'application/ttml+xml';
    return 'text/vtt';
  }

  String _localSubtitleLanguage(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('.ar.') || lower.contains('_ar') || lower.contains('arab') || lower.contains('عرب')) return 'ar';
    if (lower.contains('.en.') || lower.contains('_en') || lower.contains('english')) return 'en';
    return '';
  }

  Future<List<Map<String, String>>> _collectDownloadedSubtitleTracks(String videoPath) async {
    try {
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) return const <Map<String, String>>[];
      final dir = videoFile.parent;
      if (!await dir.exists()) return const <Map<String, String>>[];
      final videoName = videoFile.uri.pathSegments.isNotEmpty
          ? videoFile.uri.pathSegments.last
          : videoFile.path.split(Platform.pathSeparator).last;
      final dot = videoName.lastIndexOf('.');
      final baseName = dot > 0 ? videoName.substring(0, dot) : videoName;
      final baseLower = baseName.toLowerCase();
      final safeBaseLower = _sanitizeFileName(baseName).toLowerCase();
      final out = <Map<String, String>>[];

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : entity.path.split(Platform.pathSeparator).last;
        final lower = name.toLowerCase();
        final isSubtitle = lower.endsWith('.vtt') ||
            lower.endsWith('.srt') ||
            lower.endsWith('.ass') ||
            lower.endsWith('.ssa') ||
            lower.endsWith('.ttml') ||
            lower.endsWith('.xml');
        if (!isSubtitle) continue;
        if (!(lower == '$baseLower.vtt' ||
            lower == '$baseLower.srt' ||
            lower == '$baseLower.ass' ||
            lower == '$baseLower.ssa' ||
            lower == '$baseLower.ttml' ||
            lower == '$baseLower.xml' ||
            lower.startsWith('$baseLower.') ||
            lower.startsWith('$baseLower ') ||
            lower.startsWith('$safeBaseLower.') ||
            lower.startsWith('$safeBaseLower '))) {
          continue;
        }
        try {
          if (await entity.length() < 32) continue;
        } catch (_) {
          continue;
        }
        final lang = _localSubtitleLanguage(name);
        out.add({
          'label': lang == 'ar' ? 'Arabic' : (lang == 'en' ? 'English' : 'Subtitle'),
          'url': Uri.file(entity.path).toString(),
          'language': lang,
          'source': 'Local Download',
          'mimeType': _localSubtitleMimeType(entity.path),
          'autoSelect': out.isEmpty ? 'true' : 'false',
          'default': out.isEmpty ? 'true' : 'false',
        });
      }

      out.sort((a, b) {
        int rank(Map<String, String> item) {
          final lang = (item['language'] ?? '').toLowerCase();
          final blob = [item['fileName'], item['label'], item['source'], item['url']]
              .whereType<String>()
              .join(' ')
              .toLowerCase();
          final isArabic2Backup = blob.contains('عربي 2') || blob.contains('subdl');
          final isSubSource = blob.contains('subsource');
          if (isSubSource && (lang == 'ar' || blob.contains('arabic') || blob.contains('عرب'))) return -20;
          if ((lang == 'ar' || blob.contains('arabic') || blob.contains('عرب')) && !isArabic2Backup) return 0;
          if (isArabic2Backup) return 20;
          if (lang == 'en') return 30;
          return 40;
        }
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        return (a['url'] ?? '').toLowerCase().compareTo((b['url'] ?? '').toLowerCase());
      });
      if (out.isNotEmpty) {
        for (final item in out) {
          item['autoSelect'] = 'false';
          item['default'] = 'false';
        }
        out.first['autoSelect'] = 'true';
        out.first['default'] = 'true';
      }
      return out;
    } catch (_) {
      return const <Map<String, String>>[];
    }
  }

  Future<void> _openDownload(_LibraryDownloadEntry entry) async {
    final playablePath = entry.status == 'done' ? entry.path : (entry.finalPath ?? '');
    if (entry.status != 'done' || playablePath.trim().isEmpty || !File(playablePath).existsSync()) return;

    final subtitles = await _collectDownloadedSubtitleTracks(playablePath);
    final aspectW = entry.mediaType == MediaType.tv ? 16 : 16;
    final aspectH = entry.mediaType == MediaType.tv ? 9 : 9;
    try {
      final ok = await _downloadPlayerChannel.invokeMethod<bool>('openNativePlayer', {
        'url': Uri.file(playablePath).toString(),
        'currentTime': 0.0,
        'pageUrl': Uri.file(playablePath).toString(),
        'mimeType': _localVideoMimeType(playablePath),
        'headers': const <String, String>{},
        'aspectRatioNumerator': aspectW,
        'aspectRatioDenominator': aspectH,
        'subtitleTracks': subtitles,
        'qualityOptions': const <Map<String, dynamic>>[],
        'currentQualityLabel': entry.qualityLabel ?? '',
        'serverOptions': const <Map<String, dynamic>>[],
        'currentServerLabel': '',
        'resizeMode': 'fill',
        'preferFill': true,
        'autoSelectSubtitle': true,
      });
      if (ok != true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر فتح الملف داخل المشغل الداخلي')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المشغل الداخلي غير متاح لهذا الملف')),
      );
    }
  }

  Future<void> _pauseLibraryDownload(_LibraryDownloadEntry entry) async {
    final id = (entry.downloadId ?? '').trim();
    if (id.isEmpty) return;
    await BackgroundDownloadBridge.pause(id);
    await _refreshDownloads(force: true);
  }

  Future<void> _resumeLibraryDownload(_LibraryDownloadEntry entry) async {
    final id = (entry.downloadId ?? '').trim();
    if (id.isEmpty) return;
    await BackgroundDownloadBridge.resume(id);
    await _refreshDownloads(force: true);
  }

  Future<void> _deleteSidecarSubtitlesForVideo(String videoPath) async {
    final normalized = videoPath.trim();
    if (normalized.isEmpty) return;
    try {
      final videoFile = File(normalized);
      final name = videoFile.uri.pathSegments.isEmpty
          ? videoFile.path.split(Platform.pathSeparator).last
          : videoFile.uri.pathSegments.last;
      final cleanName = name.toLowerCase().endsWith('.downloading')
          ? name.substring(0, name.length - '.downloading'.length)
          : name;
      final dot = cleanName.lastIndexOf('.');
      final baseName = dot > 0 ? cleanName.substring(0, dot) : cleanName;
      if (baseName.trim().isEmpty) return;
      final baseLower = baseName.toLowerCase();
      final safeBaseLower = _sanitizeFileName(baseName).toLowerCase();
      final dir = videoFile.parent;
      if (!await dir.exists()) return;

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final childName = entity.uri.pathSegments.isEmpty
            ? entity.path.split(Platform.pathSeparator).last
            : entity.uri.pathSegments.last;
        final lower = childName.toLowerCase();
        final isSubtitle = lower.endsWith('.vtt') ||
            lower.endsWith('.srt') ||
            lower.endsWith('.ass') ||
            lower.endsWith('.ssa') ||
            lower.endsWith('.ttml') ||
            lower.endsWith('.xml');
        if (!isSubtitle) continue;
        final matchesBase = lower == '$baseLower.vtt' ||
            lower == '$baseLower.srt' ||
            lower == '$baseLower.ass' ||
            lower == '$baseLower.ssa' ||
            lower == '$baseLower.ttml' ||
            lower == '$baseLower.xml' ||
            lower.startsWith('$baseLower.') ||
            lower.startsWith('$baseLower ') ||
            lower.startsWith('$safeBaseLower.') ||
            lower.startsWith('$safeBaseLower ');
        if (!matchesBase) continue;
        try {
          await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _deleteDownload(_LibraryDownloadEntry entry) async {
    try {
      final id = (entry.downloadId ?? '').trim();
      if (id.isNotEmpty) {
        await BackgroundDownloadBridge.delete(id);
      }
      final file = File(entry.path);
      if (await file.exists()) {
        await file.delete();
      }
      await _deleteSidecarSubtitlesForVideo(entry.path);
      final finalPath = (entry.finalPath ?? '').trim();
      if (finalPath.isNotEmpty) {
        final finalFile = File(finalPath);
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        await _deleteSidecarSubtitlesForVideo(finalPath);
        await _DownloadLibraryIndexStore.remove(finalPath);
      }
      await _DownloadLibraryIndexStore.remove(entry.path);
    } catch (_) {}
    if (!mounted) return;
    await _refreshDownloads(force: true);
  }

  String _guessLibraryTitleFromPath(String path) {
    final parts = path.split(Platform.pathSeparator).where((e) => e.trim().isNotEmpty).toList();
    if (parts.length >= 2) {
      final folder = parts[parts.length - 2].trim();
      if (folder.toLowerCase().startsWith('season ') && parts.length >= 3) {
        return parts[parts.length - 3].trim();
      }
      if (folder.toLowerCase() != 'movies' && folder.toLowerCase() != 'series' && folder.toLowerCase() != 'videos') {
        return folder;
      }
    }
    final fileName = parts.isNotEmpty ? parts.last : path;
    return fileName.replaceAll(RegExp(r'\.[^.]+$'), '').replaceAll('_', ' ').trim();
  }

  List<_LibraryDownloadGroup> _groupDownloads(List<_LibraryDownloadEntry> items) {
    final buckets = <String, List<_LibraryDownloadEntry>>{};
    for (final item in items) {
      buckets.putIfAbsent(item.groupKey, () => <_LibraryDownloadEntry>[]).add(item);
    }
    final groups = buckets.entries.map((entry) {
      final entries = List<_LibraryDownloadEntry>.from(entry.value)
        ..sort((a, b) {
          final aSeason = a.season ?? 0;
          final bSeason = b.season ?? 0;
          final seasonCompare = aSeason.compareTo(bSeason);
          if (seasonCompare != 0) return seasonCompare;
          final aEpisode = a.episode ?? 0;
          final bEpisode = b.episode ?? 0;
          final episodeCompare = aEpisode.compareTo(bEpisode);
          if (episodeCompare != 0) return episodeCompare;
          return b.modifiedAt.compareTo(a.modifiedAt);
        });
      final first = entries.first;
      final posterEntry = entries.firstWhere(
        (e) => (e.posterUrl ?? '').trim().isNotEmpty,
        orElse: () => first,
      );
      final thumbEntry = entries.firstWhere(
        (e) => (e.thumbnailPath ?? '').trim().isNotEmpty && File(e.thumbnailPath!).existsSync(),
        orElse: () => first,
      );
      return _LibraryDownloadGroup(
        id: entry.key,
        title: first.title,
        posterUrl: posterEntry.posterUrl,
        thumbnailPath: thumbEntry.thumbnailPath,
        mediaType: first.mediaType,
        entries: entries,
      );
    }).toList(growable: false)
      ..sort((a, b) => b.entries.first.modifiedAt.compareTo(a.entries.first.modifiedAt));
    return groups;
  }

  String _groupSubtitle(_LibraryDownloadGroup group) {
    final count = group.entries.length;
    final looksLikeTvGroup = group.mediaType == MediaType.tv ||
        group.id.trim().toLowerCase().startsWith('tv:') ||
        group.entries.any((entry) =>
            entry.mediaType == MediaType.tv ||
            entry.season != null ||
            entry.episode != null);
    if (looksLikeTvGroup) {
      return count == 1 ? 'حلقة محمّلة' : '$count حلقات محمّلة';
    }
    return count == 1 ? 'فيلم محمّل' : '$count ملفات';
  }

  String _entryTitle(_LibraryDownloadEntry entry) {
    final quality = (entry.qualityLabel ?? '').trim();
    if (entry.mediaType == MediaType.tv) {
      final code = entry.episodeCode;
      if (quality.isNotEmpty) return '$code • $quality';
      return code;
    }
    if (quality.isNotEmpty) return quality;
    return entry.name;
  }

  Widget _buildSavedGrid() {
    if (widget.items.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد عناصر محفوظة.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: widget.items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.48,
      ),
      itemBuilder: (context, index) => GestureDetector(
        onTap: () => widget.onOpen(widget.items[index]),
        child: PosterCard(item: widget.items[index]),
      ),
    );
  }

  Widget _buildDownloadsTab() {
    if (_downloadsInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final items = _downloadEntries;
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _refreshDownloads(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          children: const [
            SizedBox(height: 120),
            Center(
              child: Text(
                'لا توجد تحميلات.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      );
    }

    final groups = _groupDownloads(items);
    return RefreshIndicator(
      onRefresh: () => _refreshDownloads(force: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final group = groups[index];
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1B1B1E),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF34343A)),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: PageStorageKey<String>('library_download_group_${group.id}'),
                initiallyExpanded: _expandedDownloadGroups.contains(group.id),
                iconColor: Colors.white,
                collapsedIconColor: Colors.white,
                onExpansionChanged: (expanded) {
                  if (!mounted) return;
                  setState(() {
                    if (expanded) {
                      _expandedDownloadGroups.add(group.id);
                    } else {
                      _expandedDownloadGroups.remove(group.id);
                    }
                  });
                },
                tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 58,
                    height: 82,
                    child: (group.posterUrl ?? '').trim().isNotEmpty
                        ? Image.network(
                            group.posterUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: const Color(0x14FFFFFF),
                              alignment: Alignment.center,
                              child: const Icon(Icons.movie_creation_outlined, color: Colors.white70),
                            ),
                          )
                        : (group.thumbnailPath ?? '').trim().isNotEmpty && File(group.thumbnailPath!).existsSync()
                            ? pwaImageFile(group.thumbnailPath!, fit: BoxFit.cover)
                            : Container(
                                color: const Color(0x14FFFFFF),
                                alignment: Alignment.center,
                                child: const Icon(Icons.movie_creation_outlined, color: Colors.white70),
                              ),
                  ),
                ),
                title: Text(
                  group.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  _groupSubtitle(group),
                  style: const TextStyle(color: Colors.white60),
                ),
                children: group.entries.map((entry) {
                  return Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151519),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2D2D34)),
                    ),
                    child: Builder(
                      builder: (context) {
                        final control = _ActiveDownloadRegistry.get(entry.path) ?? _ActiveDownloadRegistry.get(entry.finalPath);
                        final nativeId = (entry.downloadId ?? '').trim();
                        final canPause = (control != null || nativeId.isNotEmpty) && (entry.status == 'downloading' || entry.status == 'preparing');
                        final canResume = (control != null || nativeId.isNotEmpty) && entry.status == 'paused';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          title: Text(
                            _entryTitle(entry),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: entry.status == 'downloading' || entry.status == 'preparing'
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 2),
                                    ClipRRect(
                                      borderRadius: const BorderRadius.all(Radius.circular(99)),
                                      child: LinearProgressIndicator(
                                        value: entry.progress <= 0 ? null : entry.progress,
                                        minHeight: 6,
                                        backgroundColor: _kDownloadAccentSoft,
                                        valueColor: const AlwaysStoppedAnimation<Color>(_kDownloadProgressBarColor),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      entry.status == 'preparing'
                                          ? 'جاري تجهيز التحميل...'
                                          : 'جاري التحميل... ${(entry.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                      style: const TextStyle(color: Colors.white, fontSize: 11.5),
                                    ),
                                  ],
                                )
                              : Text(
                                  entry.status == 'paused'
                                      ? 'تم إيقاف التحميل مؤقتًا • ${(entry.progress * 100).clamp(0, 100).toStringAsFixed(0)}%'
                                      : '${_formatBytes(entry.sizeBytes)} • ${entry.modifiedAt.year}-${entry.modifiedAt.month.toString().padLeft(2, '0')}-${entry.modifiedAt.day.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    color: entry.status == 'error'
                                        ? Colors.redAccent
                                        : (entry.status == 'cancelled'
                                            ? Colors.white38
                                            : (entry.status == 'paused' ? Colors.white : Colors.white60)),
                                  ),
                                ),
                          onTap: entry.status == 'done' ? () => _openDownload(entry) : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (entry.status == 'done')
                                IconButton(
                                  onPressed: () => _openDownload(entry),
                                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                                )
                              else ...[
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(end: 4),
                                  child: Text(
                                    entry.status == 'preparing' ? '...' : '${(entry.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      color: entry.status == 'error'
                                          ? Colors.redAccent
                                          : (entry.status == 'cancelled' ? Colors.white38 : Colors.white),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (canPause)
                                  IconButton(
                                    onPressed: control != null ? control.pause : () => _pauseLibraryDownload(entry),
                                    icon: const Icon(Icons.pause_circle_outline_rounded, color: Colors.white),
                                  ),
                                if (canResume)
                                  IconButton(
                                    onPressed: control != null ? () => control.resume() : () => _resumeLibraryDownload(entry),
                                    icon: const Icon(Icons.play_circle_outline_rounded, color: Colors.white),
                                  ),
                              ],
                              IconButton(
                                onPressed: () => _deleteDownload(entry),
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                }).toList(growable: false),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2E2E33))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'مكتبتي',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                    ),
                    _buildSubSourceActivationButton(),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1B1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF34343A)),
                  ),
                  child: const TabBar(
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: Color.fromARGB(255, 168, 74, 64),
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    tabs: [
                      Tab(text: 'المحفوظات'),
                      Tab(text: 'التحميلات'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSavedGrid(),
                _buildDownloadsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryDownloadEntry {
  final String path;
  final String name;
  final DateTime modifiedAt;
  final int sizeBytes;
  final String title;
  final String groupKey;
  final String? posterUrl;
  final String? thumbnailPath;
  final MediaType? mediaType;
  final int? tmdbId;
  final int? season;
  final int? episode;
  final String? qualityLabel;
  final String status;
  final double progress;
  final String? finalPath;
  final String? downloadId;

  const _LibraryDownloadEntry({
    required this.path,
    required this.name,
    required this.modifiedAt,
    required this.sizeBytes,
    required this.title,
    required this.groupKey,
    this.posterUrl,
    this.thumbnailPath,
    this.mediaType,
    this.tmdbId,
    this.season,
    this.episode,
    this.qualityLabel,
    this.status = 'done',
    this.progress = 1.0,
    this.finalPath,
    this.downloadId,
  });

  String get episodeCode {
    if (season != null && episode != null) {
      return 'S${season!.toString().padLeft(2, '0')}E${episode!.toString().padLeft(2, '0')}';
    }
    return name;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DETAILS PAGE
// ══════════════════════════════════════════════════════════════════════════════

class DetailsPage extends StatefulWidget {
  final MediaItem item;
  final bool isSaved;
  final VoidCallback onToggleSave;

  const DetailsPage({
    super.key,
    required this.item,
    required this.isSaved,
    required this.onToggleSave,
  });

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  late final Future<MediaDetails> _detailsFuture;
  final Map<int, Future<SeasonDetails>> _seasonFutureCache = {};
  int? _selectedSeasonNumber;
  Future<List<Map<String, String>>>? _movieSubtitlePrepareFuture;
  String _movieSubtitlePrepareKey = '';
  late final Future<List<MediaItem>> _similarFuture;
  late bool _isSavedLocal;
  bool _movieDownloadBusy = false;
  bool _movieDownloadDone = false;
  final Set<String> _episodeDownloadBusyKeys = <String>{};
  final Set<String> _episodeDownloadDoneKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _isSavedLocal = widget.isSaved;
    _detailsFuture = TmdbService.instance.fetchDetails(widget.item);
    _similarFuture = TmdbService.instance.fetchSimilar(widget.item);
    if (widget.item.type == MediaType.movie) {
      _movieSubtitlePrepareKey = _movieSubtitleKey(widget.item);
      _movieSubtitlePrepareFuture = WyziePrefetchService.startPrepareArabicTracksForPlayback(
        tmdbId: widget.item.id,
        mediaType: widget.item.type,
        title: widget.item.displayTitle,
        year: widget.item.releaseDate?.year,
      );
    }
  }


  @override
  void didUpdateWidget(covariant DetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSaved != widget.isSaved) {
      _isSavedLocal = widget.isSaved;
    }
  }

  void _handleToggleSave() {
    setState(() => _isSavedLocal = !_isSavedLocal);
    widget.onToggleSave();
  }

  void _handleMovieDownloadStatus(String status) {
    if (!mounted) return;
    final s = status.trim().toLowerCase();
    setState(() {
      if (s == 'done') {
        _movieDownloadBusy = false;
        _movieDownloadDone = true;
      } else if (s == 'resolving' || s == 'choices') {
        _movieDownloadBusy = true;
        _movieDownloadDone = false;
      } else if (s == 'error' || s == 'idle' || s == 'cancelled' || s == 'queued') {
        _movieDownloadBusy = false;
      } else {
        _movieDownloadBusy = true;
        _movieDownloadDone = false;
      }
    });
  }

  String _episodeDownloadKey(int season, int episode) => '$season:$episode';

  bool _isEpisodeDownloadBusy(int season, EpisodeItem episode) {
    return _episodeDownloadBusyKeys.contains(
      _episodeDownloadKey(season, episode.episodeNumber),
    );
  }

  bool _isEpisodeDownloadDone(int season, EpisodeItem episode) {
    return _episodeDownloadDoneKeys.contains(
      _episodeDownloadKey(season, episode.episodeNumber),
    );
  }

  void _handleEpisodeDownloadStatus(int season, int episodeNumber, String status) {
    if (!mounted) return;
    final key = _episodeDownloadKey(season, episodeNumber);
    final s = status.trim().toLowerCase();
    setState(() {
      if (s == 'done') {
        _episodeDownloadBusyKeys.remove(key);
        _episodeDownloadDoneKeys.add(key);
      } else if (s == 'resolving' || s == 'choices') {
        _episodeDownloadDoneKeys.remove(key);
        _episodeDownloadBusyKeys.add(key);
      } else if (s == 'error' || s == 'idle' || s == 'cancelled' || s == 'queued') {
        _episodeDownloadBusyKeys.remove(key);
      } else {
        _episodeDownloadDoneKeys.remove(key);
        _episodeDownloadBusyKeys.add(key);
      }
    });
  }

  int? _pickInitialSeason(List<SeasonSummary> seasons) {
    if (seasons.isEmpty) return null;
    final regular = seasons
        .where((s) => !s.isSpecial && s.episodeCount > 0)
        .toList()
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    if (regular.isNotEmpty) return regular.first.seasonNumber;
    final any = [...seasons]
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    return any.first.seasonNumber;
  }

  Future<SeasonDetails> _seasonFuture(MediaDetails details, int seasonNumber) =>
      _seasonFutureCache.putIfAbsent(
        seasonNumber,
        () => TmdbService.instance
            .fetchSeasonDetails(details.item.id, seasonNumber),
      );

  void _ensureSeasonSelected(MediaDetails details) {
    if (details.item.type != MediaType.tv) return;
    if (_selectedSeasonNumber != null) return;
    final initial = _pickInitialSeason(details.seasonList);
    if (initial == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selectedSeasonNumber = initial);
    });
  }

  StreamingSource _preferredStreamingSource() {
    for (final source in kStreamingSources) {
      if (source.name.toLowerCase() == 'vidfast') return source;
    }
    return kStreamingSources.first;
  }

  void _openSuggested(MediaItem item) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DetailsPage(
        item: item,
        isSaved: false,
        onToggleSave: () {},
      ),
    ));
  }

  Future<void> _openPreferredSourcePlayer({
    required MediaItem item,
    int? season,
    int? episode,
    List<Map<String, String>> initialSubtitleTracks = const <Map<String, String>>[],
    Future<List<Map<String, String>>>? deferredSubtitleTracksFuture,
  }) async {
    unawaited(WatchHistoryStore.push(item));
    final source = _preferredStreamingSource();
    final url = source.buildUrl(item.id, season: season, episode: episode);
    if (kIsWeb) {
      // PWA: افتح مصدر VidFast الداخلي مباشرة داخل iframe فقط، بدون مشغل خارجي وبدون ترجمة خارجية.
      await openUniversalMediaPlayer(
        context,
        url: url,
        title: item.displayTitle,
        pageUrl: url,
      );
      return;
    }
    await Navigator.of(context).push(
      _buildDirectHiddenPlayerRoute(
        AsdPicsPlayer(
          initialUrl: url,
          headerTitle: item.displayTitle,
          launchHidden: true,
          downloadOnlyMode: false,
          autoDownloadPrompt: false,
          loadingPosterUrl: item.posterUrl,
          preferredSourceName: source.name,
          tmdbId: item.id,
          mediaType: item.type,
          season: season,
          episode: episode,
          initialSubtitleTracks: initialSubtitleTracks,
          deferredSubtitleTracksFuture: deferredSubtitleTracksFuture,
          skipInitialSubtitleFetch: true,
        ),
      ),
    );
  }

  Future<void> _openPreferredSourceDownloader({
    required MediaItem item,
    int? season,
    int? episode,
    List<Map<String, String>> initialSubtitleTracks = const <Map<String, String>>[],
    Future<List<Map<String, String>>>? deferredSubtitleTracksFuture,
    ValueChanged<String>? onDownloadStatusChanged,
  }) async {
    unawaited(WatchHistoryStore.push(item));
    final source = _preferredStreamingSource();
    final url = source.buildUrl(item.id, season: season, episode: episode);
    if (kIsWeb) {
      onDownloadStatusChanged?.call('idle');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PWA لا يدعم تحميل الفيديو كملف. سيتم فتح مشغل VidFast الداخلي بدل التحميل.')),
        );
      }
      await openUniversalMediaPlayer(
        context,
        url: url,
        title: item.displayTitle,
        pageUrl: url,
      );
      return;
    }
    onDownloadStatusChanged?.call('resolving');

    final overlay = Overlay.of(context, rootOverlay: true);
    OverlayEntry? entry;
    bool removed = false;

    void removeHiddenDownloader(String result) {
      if (removed) return;
      removed = true;
      try {
        entry?.remove();
      } catch (_) {}
      if (!mounted) return;
      final normalized = result.trim().toLowerCase();
      if (normalized == 'error' || normalized == 'idle' || normalized == 'cancelled') {
        onDownloadStatusChanged?.call(normalized);
      }
    }

    entry = OverlayEntry(
      maintainState: true,
      builder: (_) => Positioned(
        right: 0,
        bottom: 0,
        width: 2,
        height: 2,
        child: IgnorePointer(
          ignoring: true,
          child: AsdPicsPlayer(
            initialUrl: url,
            headerTitle: item.displayTitle,
            launchHidden: true,
            downloadOnlyMode: true,
            autoDownloadPrompt: false,
            loadingPosterUrl: item.posterUrl,
            preferredSourceName: source.name,
            tmdbId: item.id,
            mediaType: item.type,
            season: season,
            episode: episode,
            initialSubtitleTracks: initialSubtitleTracks,
            deferredSubtitleTracksFuture: deferredSubtitleTracksFuture,
            skipInitialSubtitleFetch: true,
            onDownloadStatusChanged: onDownloadStatusChanged,
            onHiddenDownloadFinished: removeHiddenDownloader,
          ),
        ),
      ),
    );

    overlay.insert(entry);
    onDownloadStatusChanged?.call('background');
  }

  Future<T> _runSubtitleBusyDialog<T>({
    required String title,
    required Future<T> Function(ValueNotifier<String> progress) task,
  }) async {
    final progress = ValueNotifier<String>('جارِ التحضير...');
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF151518),
        title: Text(title),
        content: ValueListenableBuilder<String>(
          valueListenable: progress,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                value,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    try {
      return await task(progress);
    } finally {
      progress.dispose();
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  String _movieSubtitleKey(MediaItem item) {
    return '${item.id}|${item.displayTitle.trim().toLowerCase()}|${item.releaseDate?.year ?? ''}';
  }

  Future<List<Map<String, String>>> _prepareMoviePlaybackSubtitles(MediaItem item) {
    final key = _movieSubtitleKey(item);
    if (_movieSubtitlePrepareFuture == null || _movieSubtitlePrepareKey != key) {
      _movieSubtitlePrepareKey = key;
      _movieSubtitlePrepareFuture = WyziePrefetchService.startPrepareArabicTracksForPlayback(
        tmdbId: item.id,
        mediaType: item.type,
        title: item.displayTitle,
        year: item.releaseDate?.year,
      );
    }
    return _movieSubtitlePrepareFuture!;
  }

  Future<List<Map<String, String>>> _prepareEpisodePlaybackSubtitles(
    MediaItem series,
    EpisodeItem episode,
    int season,
  ) {
    return WyziePrefetchService.startPrepareArabicTracksForPlayback(
      tmdbId: series.id,
      mediaType: series.type,
      title: series.displayTitle,
      year: series.releaseDate?.year,
      season: season,
      episode: episode.episodeNumber,
    );
  }

  void _openMovieSources(MediaItem item) {
    final prepareFuture = _prepareMoviePlaybackSubtitles(item);

    final fastTracks = WyziePrefetchService.peekPreparedTracks(
      tmdbId: item.id,
      mediaType: item.type,
    );

    Future<List<Map<String, String>>> deferredTracks() async {
      try {
        final prepared = await prepareFuture;
        if (prepared.isNotEmpty) return prepared;
      } catch (_) {}
      return await WyziePrefetchService.loadStoredTracks(
        tmdbId: item.id,
        mediaType: item.type,
      );
    }

    unawaited(_openPreferredSourcePlayer(
      item: item,
      initialSubtitleTracks: fastTracks,
      deferredSubtitleTracksFuture: deferredTracks(),
    ));
  }

  Future<void> _downloadMovieSources(MediaItem item) async {
    if (_movieDownloadBusy) return;
    _handleMovieDownloadStatus('resolving');
    final prepareFuture = _prepareMoviePlaybackSubtitles(item);
    final fastTracks = WyziePrefetchService.peekPreparedTracks(
      tmdbId: item.id,
      mediaType: item.type,
    );
    Future<List<Map<String, String>>> deferredTracks() async {
      try {
        final prepared = await prepareFuture;
        if (prepared.isNotEmpty) return prepared;
      } catch (_) {}
      return await WyziePrefetchService.loadStoredTracks(
        tmdbId: item.id,
        mediaType: item.type,
      );
    }
    unawaited(_openPreferredSourceDownloader(
      item: item,
      initialSubtitleTracks: fastTracks,
      deferredSubtitleTracksFuture: deferredTracks(),
      onDownloadStatusChanged: _handleMovieDownloadStatus,
    ));
  }

  void _openEpisodeSources(MediaItem series, EpisodeItem episode, int season) {
    final prepareFuture = _prepareEpisodePlaybackSubtitles(series, episode, season);

    final fastTracks = WyziePrefetchService.peekPreparedTracks(
      tmdbId: series.id,
      mediaType: series.type,
      season: season,
      episode: episode.episodeNumber,
    );

    Future<List<Map<String, String>>> deferredTracks() async {
      try {
        final prepared = await prepareFuture;
        if (prepared.isNotEmpty) return prepared;
      } catch (_) {}
      return await WyziePrefetchService.loadStoredTracks(
        tmdbId: series.id,
        mediaType: series.type,
        season: season,
        episode: episode.episodeNumber,
      );
    }

    unawaited(_openPreferredSourcePlayer(
      item: series,
      season: season,
      episode: episode.episodeNumber,
      initialSubtitleTracks: fastTracks,
      deferredSubtitleTracksFuture: deferredTracks(),
    ));
  }

  Future<void> _downloadEpisodeSources(MediaItem series, EpisodeItem episode, int season) async {
    final episodeNumber = episode.episodeNumber;
    if (_episodeDownloadBusyKeys.contains(_episodeDownloadKey(season, episodeNumber))) return;
    _handleEpisodeDownloadStatus(season, episodeNumber, 'resolving');
    final prepareFuture = _prepareEpisodePlaybackSubtitles(series, episode, season);
    final fastTracks = WyziePrefetchService.peekPreparedTracks(
      tmdbId: series.id,
      mediaType: series.type,
      season: season,
      episode: episodeNumber,
    );
    Future<List<Map<String, String>>> deferredTracks() async {
      try {
        final prepared = await prepareFuture;
        if (prepared.isNotEmpty) return prepared;
      } catch (_) {}
      return await WyziePrefetchService.loadStoredTracks(
        tmdbId: series.id,
        mediaType: series.type,
        season: season,
        episode: episodeNumber,
      );
    }
    unawaited(_openPreferredSourceDownloader(
      item: series,
      season: season,
      episode: episodeNumber,
      initialSubtitleTracks: fastTracks,
      deferredSubtitleTracksFuture: deferredTracks(),
      onDownloadStatusChanged: (status) =>
          _handleEpisodeDownloadStatus(season, episodeNumber, status),
    ));
  }

  void _openTrailerPage(String trailerKey) {
    final key = trailerKey.trim();
    if (key.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrailerWebViewPage(
          videoKey: key,
          title: widget.item.displayTitle,
        ),
      ),
    );
  }

  Widget _buildBackdropHero({
    required MediaItem item,
    required bool hasTrailer,
    required VoidCallback onTrailerTap,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (item.backdropUrl.isNotEmpty)
          Image.network(
            item.backdropUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: const Color(0xFF17171C)),
          )
        else
          Container(color: const Color(0xFF17171C)),
        Container(color: Colors.black.withOpacity(0.38)),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 140,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xFF0B0B0D)],
              ),
            ),
          ),
        ),
        if (hasTrailer)
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: _TrailerPlayButton(onTap: onTrailerTap),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MediaDetails>(
      future: _detailsFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final currentItem = data?.item ?? widget.item;
        if (data != null) _ensureSeasonSelected(data);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: CinematicBackground(
            child: CustomScrollView(
              slivers: [
              SliverAppBar(
                expandedHeight: 330,
                pinned: true,
                title: Text(currentItem.displayTitle),
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildBackdropHero(
                    item: currentItem,
                    hasTrailer: data?.trailerKey?.isNotEmpty == true,
                    onTrailerTap: () {
                      final trailerKey = data?.trailerKey?.trim();
                      if (trailerKey == null || trailerKey.isEmpty) return;
                      _openTrailerPage(trailerKey);
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const Padding(
                          padding: EdgeInsets.all(28),
                          child: Center(child: CircularProgressIndicator()))
                      : snapshot.hasError
                          ? Text(
                              'فشل تحميل التفاصيل\n\n${snapshot.error}',
                              style: const TextStyle(color: Colors.white70))
                          : _DetailsContent(
                              data: data!,
                              isSaved: _isSavedLocal,
                              onToggleSave: _handleToggleSave,
                              selectedSeasonNumber: _selectedSeasonNumber,
                              onSelectSeason: (n) =>
                                  setState(() => _selectedSeasonNumber = n),
                              seasonFutureBuilder: (n) =>
                                  _seasonFuture(data, n),
                              onPlayMovie: () => _openMovieSources(data.item),
                              onDownloadMovie: () => _downloadMovieSources(data.item),
                              movieDownloadBusy: _movieDownloadBusy,
                              movieDownloadDone: _movieDownloadDone,
                              onPlayEpisode: (season, ep) =>
                                  _openEpisodeSources(data.item, ep, season),
                              onDownloadEpisode: (season, ep) =>
                                  _downloadEpisodeSources(data.item, ep, season),
                              isEpisodeDownloadBusy: _isEpisodeDownloadBusy,
                              isEpisodeDownloadDone: _isEpisodeDownloadDone,
                              similarFuture: _similarFuture,
                              onOpenSuggestion: _openSuggested,
                            ),
                ),
              ),
            ],
          ),
        ),
      );
      },
    );
  }
}

class _DetailsContent extends StatelessWidget {
  final MediaDetails data;
  final bool isSaved;
  final VoidCallback onToggleSave;
  final int? selectedSeasonNumber;
  final ValueChanged<int> onSelectSeason;
  final Future<SeasonDetails> Function(int) seasonFutureBuilder;
  final VoidCallback onPlayMovie;
  final VoidCallback onDownloadMovie;
  final bool movieDownloadBusy;
  final bool movieDownloadDone;
  final void Function(int season, EpisodeItem episode) onPlayEpisode;
  final void Function(int season, EpisodeItem episode) onDownloadEpisode;
  final bool Function(int season, EpisodeItem episode) isEpisodeDownloadBusy;
  final bool Function(int season, EpisodeItem episode) isEpisodeDownloadDone;
  final Future<List<MediaItem>> similarFuture;
  final ValueChanged<MediaItem> onOpenSuggestion;

  const _DetailsContent({
    required this.data,
    required this.isSaved,
    required this.onToggleSave,
    required this.selectedSeasonNumber,
    required this.onSelectSeason,
    required this.seasonFutureBuilder,
    required this.onPlayMovie,
    required this.onDownloadMovie,
    required this.movieDownloadBusy,
    required this.movieDownloadDone,
    required this.onPlayEpisode,
    required this.onDownloadEpisode,
    required this.isEpisodeDownloadBusy,
    required this.isEpisodeDownloadDone,
    required this.similarFuture,
    required this.onOpenSuggestion,
  });

  @override
  Widget build(BuildContext context) {
    final item = data.item;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                item.originalTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _BookmarkActionButton(
              isSaved: isSaved,
              onTap: onToggleSave,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            InfoChip(label: item.yearText),
            InfoChip(label: item.type == MediaType.movie ? 'فيلم' : 'مسلسل'),
            InfoChip(label: '⭐ ${item.rating.toStringAsFixed(1)}'),
            if (data.runtimeMinutes != null)
              InfoChip(label: '${data.runtimeMinutes} دقيقة'),
            if (data.seasons != null)
              InfoChip(label: '${data.seasons} مواسم'),
            if (data.episodes != null)
              InfoChip(label: '${data.episodes} حلقة'),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: data.genres.map((g) => InfoChip(label: g)).toList(),
        ),
        const SizedBox(height: 18),

        if (item.type == MediaType.movie) ...[
          Row(
            children: [
              Expanded(
                child: _SoftActionButton(
                  onTap: onPlayMovie,
                  icon: Icons.play_arrow_rounded,
                  iconColor: const Color.fromARGB(255, 250, 250, 250),
                  iconSize: 200,
                  height: 80,
                ),
              ),
              const SizedBox(width: 10),
              _SoftActionButton(
                onTap: movieDownloadBusy ? () {} : onDownloadMovie,
                icon: movieDownloadDone ? Icons.check_rounded : Icons.download_rounded,
                iconColor: movieDownloadDone
                    ? const Color(0xFF82E082)
                    : const Color.fromARGB(255, 255, 253, 253),
                iconSize: movieDownloadDone ? 54 : 60,
                height: 74,
                width: 84,
                child: movieDownloadBusy
                    ? const _SmallDownloadBusyIcon()
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 22),
        ] else
          const SizedBox(height: 22),

        if (item.type == MediaType.tv) ...[
          const SizedBox(height: 26),
          _SeasonEpisodeSection(
            details: data,
            selectedSeasonNumber: selectedSeasonNumber,
            onSelectSeason: onSelectSeason,
            seasonFutureBuilder: seasonFutureBuilder,
            onPlayEpisode: onPlayEpisode,
            onDownloadEpisode: onDownloadEpisode,
            isEpisodeDownloadBusy: isEpisodeDownloadBusy,
            isEpisodeDownloadDone: isEpisodeDownloadDone,
          ),
        ],

        const SizedBox(height: 26),
        const Text('مقترحات مشابهة',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 10),
        FutureBuilder<List<MediaItem>>(
          future: similarFuture,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <MediaItem>[];
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (items.isEmpty) {
              return const Text('لا توجد مقترحات مشابهة حالياً.',
                  style: TextStyle(color: Colors.white60));
            }
            return HorizontalMediaList(
              items: items,
              genres: const GenreMaps(movie: <int, String>{}, tv: <int, String>{}),
              onOpen: onOpenSuggestion,
            );
          },
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
//  Season / Episode Section
// ──────────────────────────────────────────────────────────────────────────────



class _SoftActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;
  final double iconSize;
  final double height;
  final double? width;
  final Widget? child;

  const _SoftActionButton({
    required this.icon,
    required this.onTap,
    required this.iconColor,
    required this.iconSize,
    required this.height,
    this.width,
    this.child,
  });

  static const Color _surfaceColor = Color.fromARGB(0, 150, 38, 38);
  static const Color _borderColor = Color.fromARGB(0, 20, 7, 7);
  static const Color _playColor = Color.fromARGB(255, 168, 74, 64);
  static const Color _playGlyphColor = Colors.white;

  bool get _isPlayButton => icon == Icons.play_arrow_rounded;
  bool get _isCircularPlayButton =>
      _isPlayButton && width != null && (width! - height).abs() < 0.1;

  @override
  Widget build(BuildContext context) {
    final radius = _isCircularPlayButton ? height / 2 : (_isPlayButton ? 18.0 : 20.0);
    final playPadding = _isCircularPlayButton
        ? EdgeInsets.zero
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 4);

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: _isCircularPlayButton
            ? const CircleBorder()
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        borderRadius: _isCircularPlayButton ? null : BorderRadius.circular(radius),
        child: Ink(
          height: height,
          width: width,
          padding: _isPlayButton ? playPadding : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _isPlayButton ? _playColor : _surfaceColor,
            shape: _isCircularPlayButton ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: _isCircularPlayButton ? null : BorderRadius.circular(radius),
            border: _isPlayButton ? null : Border.all(color: _borderColor),
            boxShadow: [
              BoxShadow(
                color: _isPlayButton
                    ? const Color.fromARGB(0, 0, 0, 0)
                    : const Color(0x12000000),
                blurRadius: _isPlayButton ? 14 : 14,
                offset: Offset(0, _isPlayButton ? 6 : 6),
              ),
            ],
          ),
          child: Center(
            child: child ?? (_isPlayButton
                ? FittedBox(
                    fit: BoxFit.contain,
                    child: _ExactSvgPlayGlyph(
                      size: iconSize,
                      color: _playGlyphColor,
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.contain,
                    child: Icon(
                      icon,
                      color: iconColor,
                      size: iconSize,
                    ),
                  )),
          ),
        ),
      ),
    );

    if (width != null) return button;
    return SizedBox(height: height, child: button);
  }
}


class _SmallDownloadBusyIcon extends StatelessWidget {
  const _SmallDownloadBusyIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 42,
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Colors.white,
              backgroundColor: Color(0x22FFFFFF),
            ),
          ),
          Icon(
            Icons.download_rounded,
            color: Colors.white,
            size: 19,
          ),
        ],
      ),
    );
  }
}

class _ExactSvgPlayGlyph extends StatelessWidget {
  final double size;
  final Color color;

  const _ExactSvgPlayGlyph({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ExactSvgPlayGlyphPainter(color),
    );
  }
}

class _ExactSvgPlayGlyphPainter extends CustomPainter {
  final Color color;

  const _ExactSvgPlayGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final path = Path()
      ..moveTo(size.width * 0.63927734375, size.height * 0.59294921875)
      ..relativeLineTo(size.width * -0.1812109375, size.height * 0.1061328125)
      ..relativeCubicTo(
        size.width * -0.021953125,
        size.height * 0.01287109375,
        size.width * -0.04384765625,
        size.height * 0.0194140625,
        size.width * -0.0650390625,
        size.height * 0.0194140625,
      )
      ..relativeCubicTo(
        size.width * -0.00001953125,
        0,
        size.width * -0.00001953125,
        0,
        size.width * -0.00001953125,
        0,
      )
      ..relativeCubicTo(
        size.width * -0.028359375,
        size.height * -0.00001953125,
        size.width * -0.05349609375,
        size.height * -0.01193359375,
        size.width * -0.07080078125,
        size.height * -0.03359375,
      )
      ..relativeCubicTo(
        size.width * -0.0157421875,
        size.height * -0.01970703125,
        size.width * -0.0240625,
        size.height * -0.04650390625,
        size.width * -0.0240625,
        size.height * -0.07748046875,
      )
      ..lineTo(size.width * 0.298828125, size.height * 0.392578125)
      ..relativeCubicTo(
        0,
        size.height * -0.0309765625,
        size.width * 0.0083203125,
        size.height * -0.05775390625,
        size.width * 0.0240625,
        size.height * -0.0774609375,
      )
      ..relativeCubicTo(
        size.width * 0.0173046875,
        size.height * -0.02166015625,
        size.width * 0.04244140625,
        size.height * -0.03359375,
        size.width * 0.07080078125,
        size.height * -0.03359375,
      )
      ..relativeCubicTo(
        size.width * 0.0212109375,
        0,
        size.width * 0.0430859375,
        size.height * 0.0065234375,
        size.width * 0.06505859375,
        size.height * 0.01939453125,
      )
      ..relativeLineTo(size.width * 0.1812109375, size.height * 0.10615234375)
      ..relativeCubicTo(
        size.width * 0.0387890625,
        size.height * 0.02271484375,
        size.width * 0.06103515625,
        size.height * 0.0566015625,
        size.width * 0.06103515625,
        size.height * 0.0929296875,
      )
      ..cubicTo(
        size.width * 0.7001171875,
        size.height * 0.53634765625,
        size.width * 0.67787109375,
        size.height * 0.570234375,
        size.width * 0.63927734375,
        size.height * 0.59294921875,
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ExactSvgPlayGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}



class TrailerWebViewPage extends StatefulWidget {
  final String videoKey;
  final String title;

  const TrailerWebViewPage({
    super.key,
    required this.videoKey,
    required this.title,
  });

  @override
  State<TrailerWebViewPage> createState() => _TrailerWebViewPageState();
}

class _TrailerWebViewPageState extends State<TrailerWebViewPage> {
  InAppWebViewController? _controller;
  int _progress = 0;

  WebUri get _youtubeUrl => WebUri(
        'https://www.youtube.com/watch?v=${widget.videoKey}',
      );

  bool _isAllowedYoutubeUrl(String raw) {
    final lower = raw.toLowerCase();
    return lower.startsWith('about:blank') ||
        lower.contains('youtube.com/') ||
        lower.contains('youtu.be/') ||
        lower.contains('google.com/') ||
        lower.contains('gstatic.com/') ||
        lower.contains('googleusercontent.com/');
  }

  @override
  void dispose() {
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.title.trim().isEmpty ? 'مشاهدة الإعلان' : 'إعلان • ${widget.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'إعادة التحميل',
            onPressed: () => _controller?.loadUrl(
              urlRequest: URLRequest(url: _youtubeUrl),
            ),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: _youtubeUrl),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                useShouldOverrideUrlLoading: true,
                transparentBackground: false,
                supportZoom: false,
                userAgent:
                    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
              ),
              onWebViewCreated: (controller) => _controller = controller,
              onProgressChanged: (_, progress) {
                if (!mounted) return;
                setState(() => _progress = progress);
              },
              shouldOverrideUrlLoading: (controller, action) async {
                final raw = action.request.url?.toString() ?? '';
                if (_isAllowedYoutubeUrl(raw)) {
                  return NavigationActionPolicy.ALLOW;
                }
                return NavigationActionPolicy.CANCEL;
              },
            ),
            if (_progress < 100)
              Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(
                  value: _progress <= 0 ? null : _progress / 100,
                  minHeight: 2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrailerPlayButton extends StatefulWidget {
  final VoidCallback onTap;

  const _TrailerPlayButton({required this.onTap});

  @override
  State<_TrailerPlayButton> createState() => _TrailerPlayButtonState();
}

class _TrailerPlayButtonState extends State<_TrailerPlayButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) async {
        await _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
              color: Colors.white.withOpacity(0.52),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF0000),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'شاهد الإعلان',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Text(
                        'YouTube',
                        style: TextStyle(
                          color: Color(0xFFFF0000),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                      Text(
                        '  •  الإعلان الرسمي',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookmarkActionButton extends StatelessWidget {
  final bool isSaved;
  final VoidCallback onTap;

  const _BookmarkActionButton({
    required this.isSaved,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: onTap,
          radius: 30,
          child: Icon(
            isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
      ),
    );
  }
}

class _SeasonEpisodeSection extends StatelessWidget {
  final MediaDetails details;
  final int? selectedSeasonNumber;
  final ValueChanged<int> onSelectSeason;
  final Future<SeasonDetails> Function(int) seasonFutureBuilder;
  final void Function(int season, EpisodeItem episode) onPlayEpisode;
  final void Function(int season, EpisodeItem episode) onDownloadEpisode;
  final bool Function(int season, EpisodeItem episode) isEpisodeDownloadBusy;
  final bool Function(int season, EpisodeItem episode) isEpisodeDownloadDone;

  const _SeasonEpisodeSection({
    required this.details,
    required this.selectedSeasonNumber,
    required this.onSelectSeason,
    required this.seasonFutureBuilder,
    required this.onPlayEpisode,
    required this.onDownloadEpisode,
    required this.isEpisodeDownloadBusy,
    required this.isEpisodeDownloadDone,
  });

  @override
  Widget build(BuildContext context) {
    if (details.seasonList.isEmpty) {
      return const Text('لا توجد مواسم أو حلقات متاحة لهذا المسلسل.',
          style: TextStyle(color: Colors.white70));
    }
    final seasonNumber =
        selectedSeasonNumber ?? details.seasonList.first.seasonNumber;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('المواسم والحلقات',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1B1B1E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: seasonNumber,
                  dropdownColor: const Color(0xFF252526),
                  borderRadius: BorderRadius.circular(14),
                  iconEnabledColor: Colors.white70,
                  items: details.seasonList.map((season) {
                    return DropdownMenuItem<int>(
                      value: season.seasonNumber,
                      child: Text(
                        season.isSpecial
                            ? 'الحلقات الخاصة'
                            : 'الموسم ${season.seasonNumber}',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) onSelectSeason(value);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FutureBuilder<SeasonDetails>(
          key: ValueKey<int>(seasonNumber),
          future: seasonFutureBuilder(seasonNumber),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                'فشل تحميل حلقات الموسم\n\n${snapshot.error}',
                style: const TextStyle(color: Colors.white70),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()));
            }
            final seasonData = snapshot.data!;
            final episodes = seasonData.episodes;
            if (episodes.isEmpty) {
              return const Text('لا توجد حلقات في هذا الموسم.',
                  style: TextStyle(color: Colors.white70));
            }
            return SizedBox(
              height: 235,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: episodes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final episode = episodes[index];
                  return SizedBox(
                    width: 190,
                    child: _EpisodePosterCard(
                      episode: episode,
                      downloadBusy: isEpisodeDownloadBusy(seasonNumber, episode),
                      downloadDone: isEpisodeDownloadDone(seasonNumber, episode),
                      onPlay: () => onPlayEpisode(seasonNumber, episode),
                      onDownload: () =>
                          onDownloadEpisode(seasonNumber, episode),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}


class _EpisodePosterCard extends StatelessWidget {
  final EpisodeItem episode;
  final bool downloadBusy;
  final bool downloadDone;
  final VoidCallback onPlay;
  final VoidCallback onDownload;

  const _EpisodePosterCard({
    required this.episode,
    required this.downloadBusy,
    required this.downloadDone,
    required this.onPlay,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF34343A)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: episode.stillUrl.isEmpty
                    ? Container(
                        color: const Color(0xFF2D2D30),
                        child: const Icon(
                          Icons.live_tv_outlined,
                          color: Colors.white54,
                          size: 30,
                        ),
                      )
                    : Image.network(
                        episode.stillUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFF2D2D30),
                          child: const Icon(
                            Icons.live_tv_outlined,
                            color: Colors.white54,
                            size: 30,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'الحلقة ${episode.episodeNumber}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _SoftActionButton(
                  onTap: onPlay,
                  icon: Icons.play_arrow_rounded,
                  iconColor: Colors.white,
                  iconSize: 52,
                  height: 68,
                  width: 68,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SoftActionButton(
                    onTap: downloadBusy ? () {} : onDownload,
                    icon: downloadDone ? Icons.check_rounded : Icons.download_rounded,
                    iconColor: downloadDone
                        ? const Color(0xFF82E082)
                        : const Color.fromARGB(255, 255, 255, 255),
                    iconSize: downloadDone ? 46 : 50,
                    height: 58,
                    child: downloadBusy ? const _SmallDownloadBusyIcon() : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _WaveDropletLoader extends StatefulWidget {
  final double size;

  const _WaveDropletLoader({required this.size});

  @override
  State<_WaveDropletLoader> createState() => _WaveDropletLoaderState();
}

class _WaveDropletLoaderState extends State<_WaveDropletLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _WaveDropletLoaderPainter(progress: _controller.value),
        );
      },
    );
  }
}

class _WaveDropletLoaderPainter extends CustomPainter {
  final double progress;

  _WaveDropletLoaderPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final clipPath = Path()..addOval(rect);

    final ringPaint = Paint()
      ..color = Colors.white.withOpacity(0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.07
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius - ringPaint.strokeWidth, ringPaint);

    canvas.save();
    canvas.clipPath(clipPath);

    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawOval(rect.deflate(size.width * 0.1), bgPaint);

    _drawWave(
      canvas,
      size,
      level: 0.56,
      amplitude: size.height * 0.055,
      phase: progress * math.pi * 2,
      color: Colors.white.withOpacity(0.85),
    );
    _drawWave(
      canvas,
      size,
      level: 0.60,
      amplitude: size.height * 0.045,
      phase: progress * math.pi * 2 + math.pi / 1.6,
      color: Colors.white.withOpacity(0.42),
    );

    canvas.restore();
  }

  void _drawWave(
    Canvas canvas,
    Size size, {
    required double level,
    required double amplitude,
    required double phase,
    required Color color,
  }) {
    final baseY = size.height * level;
    final path = Path()..moveTo(0, size.height);
    for (double x = 0; x <= size.width; x += 1) {
      final y = baseY + math.sin((x / size.width * math.pi * 2) + phase) * amplitude;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveDropletLoaderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class HeroCarousel extends StatefulWidget {
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;

  const HeroCarousel({super.key, required this.items, required this.onOpen});

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  late final PageController _controller;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: 250,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: GestureDetector(
                  onTap: () => widget.onOpen(item),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.34),
                          blurRadius: 28,
                          offset: const Offset(0, 18),
                        ),
                      ],
                      image: item.backdropUrl.isNotEmpty
                          ? DecorationImage(
                              image: ResizeImage(NetworkImage(item.backdropUrl), width: 900),
                              fit: BoxFit.cover)
                          : null,
                      gradient: item.backdropUrl.isEmpty
                          ? const LinearGradient(
                              colors: [
                                Color(0xFF2D2D30),
                                Color(0xFF252526)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.15),
                            Colors.black.withOpacity(0.65),
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Spacer(),
                            Text(item.displayTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 8),
                            Text(item.overview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white70, height: 1.4)),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed: () => widget.onOpen(item),
                                  icon: const Icon(Icons.info_outline),
                                  label: const Text('عرض التفاصيل'),
                                ),
                                const SizedBox(width: 10),
                                _MiniBadge(
                                    label:
                                        '⭐ ${item.rating.toStringAsFixed(1)}'),
                                const SizedBox(width: 8),
                                _MiniBadge(label: item.yearText),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.items.length,
            (index) => Container(
              width: _current == index ? 22 : 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: _current == index
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SectionBlock extends StatelessWidget {
  final String title;
  final Widget child;

  const SectionBlock({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class HorizontalMediaList extends StatefulWidget {
  final List<MediaItem> items;
  final GenreMaps genres;
  final ValueChanged<MediaItem> onOpen;
  final Future<void> Function()? onNeedMore;
  final bool hasMoreSource;
  final bool loadingMore;
  final int initialVisibleCount;
  final int pageSize;

  const HorizontalMediaList({
    super.key,
    required this.items,
    required this.genres,
    required this.onOpen,
    this.onNeedMore,
    this.hasMoreSource = false,
    this.loadingMore = false,
    this.initialVisibleCount = 10,
    this.pageSize = 10,
  });

  @override
  State<HorizontalMediaList> createState() => _HorizontalMediaListState();
}

class _HorizontalMediaListState extends State<HorizontalMediaList> {
  late final ScrollController _controller;
  late int _visibleCount;
  bool _requestingMoreSource = false;

  @override
  void initState() {
    super.initState();
    _visibleCount = math.min(widget.initialVisibleCount, widget.items.length);
    _controller = ScrollController()..addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant HorizontalMediaList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length < _visibleCount) {
      _visibleCount = math.min(widget.initialVisibleCount, widget.items.length);
    } else if (_visibleCount == 0 && widget.items.isNotEmpty) {
      _visibleCount = math.min(widget.initialVisibleCount, widget.items.length);
    }
    if (oldWidget.loadingMore && !widget.loadingMore) {
      _requestingMoreSource = false;
      if (widget.items.length > oldWidget.items.length &&
          _visibleCount >= oldWidget.items.length) {
        _visibleCount = math.min(widget.items.length, _visibleCount + widget.pageSize);
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleScroll);
    _controller.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_controller.hasClients) return;
    if (_controller.position.extentAfter < 360) {
      _revealOrRequestMore();
    }
  }

  Future<void> _revealOrRequestMore() async {
    if (!mounted) return;
    if (_visibleCount < widget.items.length) {
      setState(() {
        _visibleCount = math.min(
          widget.items.length,
          _visibleCount + widget.pageSize,
        );
      });
      return;
    }

    final callback = widget.onNeedMore;
    if (callback == null || !widget.hasMoreSource || widget.loadingMore || _requestingMoreSource) {
      return;
    }
    if (mounted) {
      setState(() => _requestingMoreSource = true);
    } else {
      _requestingMoreSource = true;
    }
    try {
      await callback();
    } finally {
      if (mounted) {
        setState(() => _requestingMoreSource = false);
      } else {
        _requestingMoreSource = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 16.0;
        const gap = 10.0;
        final cardWidth =
            (constraints.maxWidth - (horizontalPadding * 2) - (gap * 2)) / 3;
        final listHeight = (cardWidth / 0.67) + 56;
        final safeVisibleCount = math.min(_visibleCount, widget.items.length);
        final showMoreSpinner = widget.hasMoreSource &&
            (widget.loadingMore || _requestingMoreSource);
        final totalCount = safeVisibleCount + (showMoreSpinner ? 1 : 0);
        return SizedBox(
          height: listHeight,
          child: ListView.separated(
            controller: _controller,
            padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
            scrollDirection: Axis.horizontal,
            itemCount: totalCount,
            separatorBuilder: (_, __) => const SizedBox(width: gap),
            itemBuilder: (context, index) {
              if (index >= safeVisibleCount) {
                return SizedBox(
                  width: cardWidth,
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.20),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.22)),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              }
              final item = widget.items[index];
              final map = item.type == MediaType.movie ? widget.genres.movie : widget.genres.tv;
              final genreLabel =
                  item.genreIds.isEmpty ? '' : (map[item.genreIds.first] ?? '');
              return SizedBox(
                width: cardWidth,
                child: GestureDetector(
                  onTap: () => widget.onOpen(item),
                  child: PosterCard(
                    item: item,
                    genreLabel: genreLabel,
                    compact: true,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class PosterCard extends StatelessWidget {
  final MediaItem item;
  final String genreLabel;
  final bool compact;

  const PosterCard({
    super.key,
    required this.item,
    this.genreLabel = '',
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = compact ? 8.0 : 10.0;
    final titleStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: compact ? 12 : 14,
    );
    final subStyle = TextStyle(
      color: Colors.white60,
      fontSize: compact ? 10.5 : 12,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D30),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: const Color(0xFF3A3A3D)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius - 1),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.posterUrl.isNotEmpty)
                    Image.network(
                      item.posterUrl,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                      cacheWidth: compact ? 240 : 360,
                      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded || frame != null) return child;
                        return Container(color: const Color(0xFF252526));
                      },
                      errorBuilder: (_, __, ___) => Container(color: const Color(0xFF252526)),
                    )
                  else
                    Container(color: const Color(0xFF252526)),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _MiniBadge(
                      label: '⭐ ${item.rating.toStringAsFixed(1)}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          item.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        const SizedBox(height: 2),
        Text(
          genreLabel.isEmpty ? item.yearText : '$genreLabel • ${item.yearText}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: subStyle,
        ),
      ],
    );
  }
}

class InfoChip extends StatelessWidget {
  final String label;

  const InfoChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12.5)),
    );
  }
}

class RemovableChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const RemovableChip(
      {super.key, required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color:
                Theme.of(context).colorScheme.primary.withOpacity(0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 6),
          GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close, size: 16)),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String label;

  const _MiniBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xCC252526),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  INTERNAL EMBED PLAYER (merged from second file)
// ══════════════════════════════════════════════════════════════════════════════

class DownloadItem {
  final String id;
  final String url;
  String fileName;
  double progress;
  String status;
  String? savedPath;
  String? thumbnailPath;
  CancelToken? cancelToken;
  String? errorMessage;
  String? tempPath;
  String? finalPath;
  String? qualityLabel;
  String? pageUrl;
  String kind;
  bool pauseRequested;
  Completer<void>? resumeCompleter;

  DownloadItem({
    required this.id,
    required this.url,
    required this.fileName,
    this.progress = 0,
    this.status = 'downloading',
    this.savedPath,
    this.thumbnailPath,
    this.cancelToken,
    this.errorMessage,
    this.tempPath,
    this.finalPath,
    this.qualityLabel,
    this.pageUrl,
    this.kind = 'direct',
    this.pauseRequested = false,
    this.resumeCompleter,
  });
}

const Color _kDownloadAccent = Color(0xFFA84A40);
const Color _kDownloadAccentSoft = Color(0x33A84A40);
const Color _kDownloadProgressBarColor = Colors.indigo;

class _ActiveDownloadControl {
  final VoidCallback pause;
  final Future<void> Function() resume;
  final bool Function() isPaused;
  final bool Function() isRunning;

  const _ActiveDownloadControl({
    required this.pause,
    required this.resume,
    required this.isPaused,
    required this.isRunning,
  });
}

class _ActiveDownloadRegistry {
  static final Map<String, _ActiveDownloadControl> _controls = <String, _ActiveDownloadControl>{};

  static void register(String? key, _ActiveDownloadControl control) {
    final normalized = (key ?? '').trim();
    if (normalized.isEmpty) return;
    _controls[normalized] = control;
  }

  static void unregister(String? key) {
    final normalized = (key ?? '').trim();
    if (normalized.isEmpty) return;
    _controls.remove(normalized);
  }

  static _ActiveDownloadControl? get(String? key) {
    final normalized = (key ?? '').trim();
    if (normalized.isEmpty) return null;
    return _controls[normalized];
  }
}

class CapturedMediaItem {
  final String id;
  final String url;
  final String pageUrl;
  final String? mimeType;
  final String fileName;
  final DateTime foundAt;
  final bool isDirectFile;
  final bool isStream;
  final String? qualityLabel;
  final Map<String, String>? headers;

  const CapturedMediaItem({
    required this.id,
    required this.url,
    required this.pageUrl,
    required this.fileName,
    required this.foundAt,
    required this.isDirectFile,
    required this.isStream,
    this.mimeType,
    this.qualityLabel,
    this.headers,
  });
}

class PageQualityOption {
  final String label;
  final String key;
  final String? url;
  final bool selected;

  const PageQualityOption({
    required this.label,
    required this.key,
    this.url,
    this.selected = false,
  });

  factory PageQualityOption.fromMap(Map<String, dynamic> map) {
    return PageQualityOption(
      label: (map['label']?.toString().trim().isNotEmpty ?? false)
          ? map['label'].toString().trim()
          : 'Quality',
      key: map['key']?.toString() ?? '',
      url: map['url']?.toString(),
      selected: map['selected'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'label': label,
        'key': key,
        if (url != null && url!.isNotEmpty) 'url': url!,
        'selected': selected,
      };
}

class PageServerOption {
  final String label;
  final String key;
  final int index;
  final String? embedUrl;
  final bool selected;

  const PageServerOption({
    required this.label,
    required this.key,
    this.index = 0,
    this.embedUrl,
    this.selected = false,
  });

  factory PageServerOption.fromMap(Map<String, dynamic> map) {
    return PageServerOption(
      label: (map['label']?.toString().trim().isNotEmpty ?? false)
          ? map['label'].toString().trim()
          : 'Server',
      key: map['key']?.toString() ?? '',
      index: map['index'] is num ? (map['index'] as num).toInt() : int.tryParse((map['index'] ?? '0').toString()) ?? 0,
      embedUrl: (map['embedUrl'] ?? map['url'])?.toString(),
      selected: map['selected'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'label': label,
        'key': key,
        'index': index,
        if (embedUrl != null && embedUrl!.isNotEmpty) 'embedUrl': embedUrl!,
        'selected': selected,
      };
}

class VidfastSourceBundle {
  final List<PageQualityOption> qualityOptions;
  final String currentQualityLabel;
  final List<PageServerOption> serverOptions;
  final String currentServerLabel;
  final List<Map<String, dynamic>> subtitleTracks;

  const VidfastSourceBundle({
    required this.qualityOptions,
    required this.currentQualityLabel,
    required this.serverOptions,
    required this.currentServerLabel,
    this.subtitleTracks = const <Map<String, dynamic>>[],
  });

  factory VidfastSourceBundle.fromMap(Map<String, dynamic> map) {
    final rawQ = (map['qualityOptions'] as List? ?? const []);
    final rawS = (map['serverOptions'] as List? ?? const []);
    final rawT = (map['subtitleTracks'] as List? ?? const []);

    return VidfastSourceBundle(
      qualityOptions: rawQ
          .whereType<Map>()
          .map((e) => PageQualityOption.fromMap(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      currentQualityLabel: (map['currentQualityLabel'] ?? '').toString(),
      serverOptions: rawS
          .whereType<Map>()
          .map((e) => PageServerOption.fromMap(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      currentServerLabel: (map['currentServerLabel'] ?? '').toString(),
      subtitleTracks: rawT
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false),
    );
  }
}

class VidfastCaptureExtract {
  static const String js = r"""
(function(){
  'use strict';
  if (window.__asdVidfastQualityInstalled) return;
  window.__asdVidfastQualityInstalled = true;

  // ── Flutter bridge ──────────────────────────────────────────────────────────
  function fl(name, value) {
    try { window.flutter_inappwebview.callHandler(name, value); } catch (e) {}
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  function cleanText(v) {
    return (v == null ? '' : String(v)).replace(/\s+/g, ' ').trim();
  }

  function pushUnique(list, item, sigFn) {
    if (!item) return;
    var sig = sigFn ? sigFn(item) : JSON.stringify(item);
    for (var i = 0; i < list.length; i++) {
      if ((sigFn ? sigFn(list[i]) : JSON.stringify(list[i])) === sig) return;
    }
    list.push(item);
  }

  function pushUniqueQuality(list, item) {
    if (!item) return;
    var sig = [
      cleanText(item.label || '').toLowerCase(),
      cleanText(item.url   || '').toLowerCase()
    ].join('|');
    for (var i = 0; i < list.length; i++) {
      var cur = list[i];
      var curSig = [
        cleanText(cur.label || '').toLowerCase(),
        cleanText(cur.url   || '').toLowerCase()
      ].join('|');
      if (curSig === sig) return;
    }
    list.push(item);
  }

  // ── Detectors ───────────────────────────────────────────────────────────────
  function sameVidfast(url) {
    var u = (url || '').toLowerCase();
    return u.indexOf('vidfast.pro') !== -1 || u.indexOf('vidfast.net') !== -1;
  }

  function looksLikeSourceApi(url, method) {
    var u = (url || '').toLowerCase();
    var m = (method || '').toLowerCase();
    if (!u || !sameVidfast(u)) return false;
    if (u.indexOf('/source') !== -1 || u.indexOf('/sources') !== -1) return true;
    if (u.indexOf('/api/')   !== -1 || u.indexOf('.json')    !== -1) return true;
    if (m === 'post') return true;
    return false;
  }

  function isStreamingUrl(url) {
    var u = (url || '').toLowerCase();
    if (!u) return false;
    return u.indexOf('.m3u8') !== -1 ||
           u.indexOf('.mpd')  !== -1 ||
           u.indexOf('.mp4')  !== -1 ||
           u.indexOf('/playlist.m3u8') !== -1 ||
           u.indexOf('/master.m3u8')   !== -1;
  }

  function qualityLabel(v) {
    var s = cleanText(v);
    var m = s.match(/(2160|1440|1080|720|540|480|360|240)\s*\/?\s*p?/i);
    return m ? (m[1] + 'p') : '';
  }

  function extractUrlsFromText(txt) {
    var out = [];
    if (!txt || typeof txt !== 'string') return out;
    var norm = txt.replace(/\\\//g, '/').replace(/&amp;/g, '&');
    var re   = /https?:\/\/[^\s"'<>\\]+/g;
    var m;
    while ((m = re.exec(norm)) !== null) {
      var u = (m[0] || '').replace(/[)\],]+$/g, '').trim();
      if (u) out.push(u);
    }
    return out;
  }

  // ── Server DOM scanning ──────────────────────────────────────────────────────

  var SERVER_SELECTORS = [
    '[class*="server"]',
    '[class*="source"][class*="item"]',
    '[class*="svr"]',
    '[data-server]',
    '[data-source]',
    'ul.servers li',
    '.server-list li',
    '.sources li',
    '.server-item',
    '.source-item',
    'nav [class*="server"]',
    '.server-select li',
    '.multi-server li',
    '[onclick*="server"]',
    '[class*="Server"]',
  ];

  function classText(v) {
    if (v == null) return '';
    if (typeof v === 'string') return v;
    try {
      if (typeof v.baseVal === 'string') return v.baseVal;
    } catch (e) {}
    try { return String(v); } catch (e) { return ''; }
  }

  function isVisibleEl(el) {
    if (!el) return false;
    try {
      var r = el.getBoundingClientRect();
      if (r.width < 16 || r.height < 10) return false;
      var st = getComputedStyle(el);
      if (!st) return false;
      if (st.display === 'none' || st.visibility === 'hidden') return false;
      if (parseFloat(st.opacity || '1') < 0.05) return false;
    } catch (e) { return false; }
    return true;
  }

  function matchesVidfastServerLabel(label) {
    var low = cleanText(label).toLowerCase();
    if (!low) return false;
    return /(^|[\s_\-])(vedge|vrapid|max|nova|upcloud|vidcloud|cypher|cipher|ciper)(\b|$)/i.test(low) ||
           /^server\s*\d+$/i.test(low) ||
           /^srv\s*\d+$/i.test(low) ||
           /^server$/i.test(low);
  }

  function extractServerLabel(el) {
    var parts = [
      el && el.getAttribute ? (el.getAttribute('data-server') || '') : '',
      el && el.getAttribute ? (el.getAttribute('data-source') || '') : '',
      el && el.getAttribute ? (el.getAttribute('data-name') || '') : '',
      el && el.getAttribute ? (el.getAttribute('aria-label') || '') : '',
      el && el.getAttribute ? (el.getAttribute('title') || '') : '',
      el && (el.textContent || el.innerText || '')
    ];
    for (var i = 0; i < parts.length; i++) {
      var label = cleanText(parts[i]);
      if (label && matchesVidfastServerLabel(label)) return label;
    }
    var fallback = cleanText((el && (el.textContent || el.innerText || '')) || '');
    return matchesVidfastServerLabel(fallback) ? fallback : '';
  }

  function extractServerEmbedUrl(el) {
    if (!el || !el.getAttribute) return '';
    return cleanText(
      el.getAttribute('data-embed') ||
      el.getAttribute('data-link')  ||
      el.getAttribute('data-url')   ||
      el.getAttribute('data-src')   ||
      el.getAttribute('href')       || ''
    );
  }

  function isSelectedServerEl(el) {
    try {
      var cls = (classText(el.className) + ' ' + classText(el.parentElement && el.parentElement.className)).toLowerCase();
      return /\bactive\b|\bselected\b|\bcurrent\b|\bon\b/.test(cls) ||
             el.getAttribute('aria-selected') === 'true' ||
             el.getAttribute('aria-current') === 'true' ||
             el.getAttribute('data-active') === 'true';
    } catch (e) {}
    return false;
  }

  function scanDOMServers() {
    var serverOptions = [];
    var seen = {};

    SERVER_SELECTORS.forEach(function(sel) {
      try {
        var els = document.querySelectorAll(sel);
        els.forEach(function(el) {
          if (!isVisibleEl(el)) return;
          var label = extractServerLabel(el);
          if (!label || label.length < 1 || label.length > 80) return;
          var embedUrl = extractServerEmbedUrl(el);
          var sig = (label.toLowerCase() + '|' + embedUrl.toLowerCase());
          if (seen[sig]) return;
          seen[sig] = true;

          serverOptions.push({
            label:    label,
            key:      'srv_' + serverOptions.length + '_' + label.replace(/\W+/g, ''),
            index:    serverOptions.length,
            embedUrl: embedUrl,
            selected: isSelectedServerEl(el),
            _el:      el
          });
        });
      } catch(e) {}
    });

    if (!serverOptions.length) return serverOptions;
    return serverOptions;
  }

  var _lastQualityOptions = [];
  var _lastServerOptions  = [];
  var _currentQualityLabel = '';
  var _currentServerLabel  = '';

  function emitBundle() {
    var cleanServers = _lastServerOptions.map(function(s) {
      return { label: s.label, key: s.key, index: s.index, embedUrl: s.embedUrl || '', selected: s.selected };
    });

    fl('onSourceBundle', {
      qualityOptions:      _lastQualityOptions,
      currentQualityLabel: _currentQualityLabel,
      serverOptions:       cleanServers,
      currentServerLabel:  _currentServerLabel,
      subtitleTracks:      []
    });
  }

  function emitQualities(qualityOptions, currentQualityLabel) {
    _lastQualityOptions  = qualityOptions || [];
    _currentQualityLabel = currentQualityLabel || '';

    var domServers = scanDOMServers();
    if (domServers.length > 0) {
      _lastServerOptions = domServers;
      _currentServerLabel = domServers
        .filter(function(s){ return s.selected; })
        .map(function(s){ return s.label; })[0] || (domServers[0] && domServers[0].label) || '';
    }

    emitBundle();
  }


  var __asdServerScanScheduled = false;
  function scheduleServerScan() {
    if (__asdServerScanScheduled) return;
    __asdServerScanScheduled = true;
    setTimeout(function() {
      __asdServerScanScheduled = false;
      var servers = scanDOMServers();
      if (servers.length > 0) {
        _lastServerOptions = servers;
        _currentServerLabel = servers
          .filter(function(s){ return s.selected; })
          .map(function(s){ return s.label; })[0] || servers[0].label || '';
        emitBundle();

        fl('onServerListFound', {
          serverOptions: servers.map(function(s){
            return { label: s.label, key: s.key, index: s.index, embedUrl: s.embedUrl || '', selected: s.selected };
          }),
          currentServerLabel: _currentServerLabel
        });
      }
    }, 800);
  }

  if (!window.__asdVidfastMutationObserver) {
    window.__asdVidfastMutationObserver = true;
    try {
      var observer = new MutationObserver(function(mutations) {
        for (var i = 0; i < mutations.length; i++) {
          var m = mutations[i];
          if (m.addedNodes && m.addedNodes.length > 0) {
            for (var j = 0; j < m.addedNodes.length; j++) {
              var node = m.addedNodes[j];
              if (node.nodeType !== 1) continue;
              var txt = classText(node.className).toLowerCase();
              if (txt.indexOf('server') !== -1 ||
                  txt.indexOf('source') !== -1 ||
                  txt.indexOf('svr')    !== -1) {
                scheduleServerScan();
                break;
              }
            }
          }
        }
      });
      observer.observe(document.documentElement, { childList: true, subtree: true });
    } catch(e) {}
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
      setTimeout(scheduleServerScan, 1500);
    });
  } else {
    setTimeout(scheduleServerScan, 1500);
  }


  window.__asdSwitchServer = function(serverLabel) {
    var normalLabel = (serverLabel || '').trim().toLowerCase();
    var found = false;

    _lastServerOptions.forEach(function(s) {
      if (found) return;
      if (s.label.toLowerCase() === normalLabel) {
        if (s._el) {
          try { s._el.click(); found = true; } catch(e) {}
        }
      }
    });

    if (!found) {
      SERVER_SELECTORS.forEach(function(sel) {
        if (found) return;
        try {
          document.querySelectorAll(sel).forEach(function(el) {
            if (found) return;
            var lbl = cleanText(
              el.getAttribute('data-server') || el.textContent || ''
            ).toLowerCase();
            if (lbl === normalLabel) {
              el.click();
              found = true;
            }
          });
        } catch(e) {}
      });
    }

    if (found) {
      _currentServerLabel = serverLabel;
      fl('onServerSwitched', { server: serverLabel });
      setTimeout(scheduleServerScan, 1000);
    }
    return found;
  };

  window.__asdSwitchQuality = function(qualityLabel) {
    var normalLabel = (qualityLabel || '').trim().toLowerCase();
    var found = false;

    var QUALITY_SELECTORS = [
      '[class*="quality"]',
      '[class*="resolution"]',
      '[class*="bitrate"]',
      '.quality-item',
      'ul.quality li',
    ];

    QUALITY_SELECTORS.forEach(function(sel) {
      if (found) return;
      try {
        document.querySelectorAll(sel).forEach(function(el) {
          if (found) return;
          var lbl = cleanText(el.textContent || '').toLowerCase();
          if (lbl.indexOf(normalLabel) !== -1) {
            el.click();
            found = true;
            _currentQualityLabel = qualityLabel;
            fl('onQualitySwitched', { quality: qualityLabel });
          }
        });
      } catch(e) {}
    });

    return found;
  };

  window.__asdRescanServers = function() {
    scheduleServerScan();
    return true;
  };

  window.__asdFetchAndParseVidfastQualities = async function(url) {
    try {
      if (!url) return false;
      var response = await fetch(url, {
        credentials: 'include',
        cache: 'no-store',
        headers: {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
          'Accept': 'application/json, text/plain, */*'
        }
      });
      var txt = await response.text();
      return parsePotentialResponseText(txt, response.url || url, 'GET');
    } catch (e) {
      fl('onSourceBundleError', { url: url, error: String(e) });
      return false;
    }
  };

  // ── Source parsers ───────────────────────────────────────────────────────────
  function parseSourceBundle(data, requestUrl) {
    if (!data || typeof data !== 'object') return false;

    var qualityOptions = [];
    var currentQualityLabel = '';
    var foundDirect = false;

    function walk(node) {
      if (!node) return;
      if (Array.isArray(node)) { node.forEach(walk); return; }
      if (typeof node !== 'object') return;

      var mediaUrl = (
        node.file || node.src || node.url || node.playlist || node.stream || ''
      ).toString().trim();

      if (mediaUrl && isStreamingUrl(mediaUrl)) {
        foundDirect = true;
        var q = qualityLabel(node.label || node.quality || node.resolution || '');
        if (!q) q = qualityLabel(mediaUrl);

        if (q) {
          pushUniqueQuality(qualityOptions, {
            label:    q,
            key:      q + '_' + qualityOptions.length,
            url:      mediaUrl,
            selected: qualityOptions.length === 0
          });
          if (!currentQualityLabel) currentQualityLabel = q;
        }

        fl('onVideoFound', {
          url:         mediaUrl,
          pageUrl:     window.location.href,
          currentTime: 0,
          mimeType:    null
        });
      }

      Object.keys(node).forEach(function(k) {
        var v = node[k];
        if (v && typeof v === 'object') walk(v);
      });
    }

    walk(data);

    if (qualityOptions.length > 0) {
      emitQualities(qualityOptions, currentQualityLabel);
      return true;
    }
    return foundDirect;
  }

  function parsePotentialResponseText(txt, requestUrl, method) {
    if (!txt || typeof txt !== 'string') return false;

    var hit = false;
    try {
      if (parseSourceBundle(JSON.parse(txt), requestUrl)) hit = true;
    } catch(e) {}

    var qualityOptions      = [];
    var currentQualityLabel = '';

    extractUrlsFromText(txt).forEach(function(u) {
      if (!isStreamingUrl(u)) return;
      hit = true;
      var q = qualityLabel(u);
      if (q) {
        pushUniqueQuality(qualityOptions, {
          label:    q,
          key:      q + '_' + qualityOptions.length,
          url:      u,
          selected: qualityOptions.length === 0
        });
        if (!currentQualityLabel) currentQualityLabel = q;
      }
      fl('onVideoFound', {
        url: u, pageUrl: window.location.href, currentTime: 0, mimeType: null
      });
    });

    if (qualityOptions.length > 0) emitQualities(qualityOptions, currentQualityLabel);

    if (!hit && !looksLikeSourceApi(requestUrl, method) && !sameVidfast(requestUrl)) {
      return false;
    }
    return hit || qualityOptions.length > 0;
  }

  // ── Fetch hook ───────────────────────────────────────────────────────────────
  if (window.fetch && !window.__asdVidfastFetchHook) {
    window.__asdVidfastFetchHook = true;
    var origFetch = window.fetch;
    window.fetch = function(input, init) {
      var url    = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      var method = (init && init.method) ? init.method
                 : ((input && input.method) ? input.method : 'GET');

      return origFetch.call(window, input, init).then(function(response) {
        var finalUrl    = response.url || url;
        var contentType = '';
        try {
          contentType = (response.headers && response.headers.get &&
            response.headers.get('content-type')) || '';
        } catch(e) {}

        if (looksLikeSourceApi(finalUrl, method) || /json|text|xml/i.test(contentType)) {
          try {
            response.clone().text().then(function(txt) {
              try { parsePotentialResponseText(txt, finalUrl, method); } catch(e) {}
            }).catch(function(){});
          } catch(e) {}
        }
        return response;
      });
    };
  }

  // ── XHR hook ─────────────────────────────────────────────────────────────────
  if (!window.__asdVidfastXHRHook) {
    window.__asdVidfastXHRHook = true;
    var _open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      this._asdSourceMethod = method || 'GET';
      this._asdSourceUrl    = url    || '';
      return _open.apply(this, arguments);
    };
    var _send = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function() {
      this.addEventListener('readystatechange', function() {
        if (this.readyState !== 4) return;
        var finalUrl    = this.responseURL || this._asdSourceUrl || '';
        var method      = this._asdSourceMethod || 'GET';
        var contentType = '';
        try { contentType = this.getResponseHeader('content-type') || ''; } catch(e) {}

        if (looksLikeSourceApi(finalUrl, method) || /json|text|xml/i.test(contentType)) {
          try {
            var txt = typeof this.responseText === 'string' ? this.responseText : '';
            if (txt) parsePotentialResponseText(txt, finalUrl, method);
          } catch(e) {}
        }
      });
      return _send.apply(this, arguments);
    };
  }

})();
""";
}

class AsdPicsPlayer extends StatefulWidget {
  final String initialUrl;
  final String? headerTitle;
  final bool autoDownloadPrompt;
  final bool launchHidden;
  final bool downloadOnlyMode;
  final String? loadingPosterUrl;
  final String? preferredSourceName;
  final int? tmdbId;
  final MediaType? mediaType;
  final int? season;
  final int? episode;
  final List<Map<String, String>> initialSubtitleTracks;
  final Future<List<Map<String, String>>>? deferredSubtitleTracksFuture;
  final bool skipInitialSubtitleFetch;
  final ValueChanged<String>? onDownloadStatusChanged;
  final ValueChanged<String>? onHiddenDownloadFinished;

  const AsdPicsPlayer({
    super.key,
    this.initialUrl = 'https://asd.pics/main6/',
    this.headerTitle,
    this.autoDownloadPrompt = false,
    this.launchHidden = false,
    this.downloadOnlyMode = false,
    this.loadingPosterUrl,
    this.preferredSourceName,
    this.tmdbId,
    this.mediaType,
    this.season,
    this.episode,
    this.initialSubtitleTracks = const <Map<String, String>>[],
    this.deferredSubtitleTracksFuture,
    this.skipInitialSubtitleFetch = false,
    this.onDownloadStatusChanged,
    this.onHiddenDownloadFinished,
  });

  @override
  State<AsdPicsPlayer> createState() => _AsdPicsPlayerState();
}

class _AsdPicsPlayerState extends State<AsdPicsPlayer>
    with WidgetsBindingObserver {
  InAppWebViewController? _wc;
  PullToRefreshController? _ptr;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 25),
      receiveTimeout: const Duration(minutes: 30),
      followRedirects: true,
      maxRedirects: 10,
      validateStatus: (status) => status != null && status >= 200 && status < 400,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      },
    ),
  );

  double _progress = 0;
  bool _fullscreen = false;
  bool _videoPlaying = false;
  bool _inPip = false;
  bool _videoDetected = false;
  bool _nativePlayerActive = false;
  bool _nativePlayerOpening = false;
  bool _nativePauseSentForBackground = false;
  bool _nativePlayerShellOnly = false;
  bool _nativePlayerShellRequested = false;
  String? _pendingShellMediaUrl;
  String? _pendingShellPageUrl;
  String? _pendingShellMimeType;
  bool _preventAutoReopenAfterNativeClose = false;
  bool _exitHiddenRouteAfterNativeClose = false;
  bool _revealHiddenLaunchUi = false;
  String? _lastNativePlayerUrl;
  int _nativeOpenTicket = 0;
  int _suppressAutoOpenUntil = 0;
  List<PageQualityOption> _pageQualityOptions = const [];
  List<PageServerOption> _pageServerOptions = const [];
  String? _currentPageQualityLabel;
  String? _currentServerLabel;
  List<Map<String, String>> _externalSubtitleTracks = const [];
  final Map<String, String> _materializedSubtitleUrlCache = <String, String>{};
  final Set<String> _downloadingSubtitleUrls = <String>{};
  bool _subtitleFetchBusy = false;
  bool _subtitleRefreshQueued = false;
  bool _subtitlePersistBusy = false;
  bool _pendingSubtitleOptionsSync = false;
  String? _lastPersistedSubtitleFingerprint;
  String? _lastSubtitleFetchKey;
  String? _lastAttachRequestUrl;
  int _lastAttachRequestAt = 0;
  String? _lastDetectedSourceApiUrl;
  bool _nativeDecoderFallbackBusy = false;
  final Set<String> _nativeDecoderFallbackTriedUrls = <String>{};

  void _popHiddenPlayerRouteSoon() {
    if (!widget.launchHidden || widget.downloadOnlyMode) return;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) {
        nav.pop();
      }
    });
  }
  String? _lastFetchedSourceApiUrl;
  bool _sourceBundleFetchBusy = false;
  final Map<String, int> _sourceBundleFetchTimestamps = {};
  static const String _subsourceApiKey = String.fromEnvironment(
    'SUBSOURCE_API_KEY',
    defaultValue: '',
  );
  static const String _subsourceApiBase = 'https://subsource.net';
  static const String _subsourceWebBase = 'https://subsource.net';
  static const String _subsourceFreeApiBase = 'https://api.subsource.net/api';
  bool _qualitySwitchPending = false;
  bool _manualPlayAfterQualitySwitchPending = false;
  bool _serverSwitchPending = false;
  final bool _autoQualityApplied = false;
  bool _qualityDownloadSwitchPending = false;
  bool _hiddenQualityHarvesting = false;
  double _pendingNativeStartTime = 0;
  String? _pendingServerSwitchEmbedUrl;
  final int _serverSwitchToken = 0;
  bool _pendingNativeOpenOnPlayableCapture = false;
  int _pendingPlayableCaptureToken = 0;
  String? _activeAppSourceName;
  bool _didApplyInitialPreferredSource = false;
  String? _pendingDownloadQualityLabel;
  String? _hiddenHarvestCurrentQuality;
  final Set<String> _harvestedQualityLabels = <String>{};
  bool _downloadQualitySheetShown = false;
  bool _downloadCaptureStarted = false;
  bool _downloadSelectionCommitted = false;
  bool _downloadPromptPending = false;
  bool _downloadPromptConsumed = false;
  bool _downloadPromptFlowLocked = false;
  bool _downloadChoiceLocked = false;
  bool _downloadPassThroughMode = false;
  String? _preparingDownloadPlaceholderId;

  bool get _hasActiveDownloadTask =>
      _downloads.any((d) => d.status == 'preparing' || d.status == 'downloading');

  void _notifyDownloadStatus(String status) {
    if (widget.downloadOnlyMode) {
      widget.onDownloadStatusChanged?.call(status);
    }
  }

  void _enableDownloadPassThrough() {
    if (!widget.downloadOnlyMode || _downloadPassThroughMode) return;
    _downloadPassThroughMode = true;
    if (mounted) setState(() {});
  }

  void _finishHiddenDownloadRoute(String result) {
    if (!widget.downloadOnlyMode || !mounted) return;
    final callback = widget.onHiddenDownloadFinished;
    if (callback != null) {
      Future.delayed(const Duration(milliseconds: 260), () {
        callback(result);
      });
      return;
    }
    Future.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop(result);
    });
  }

  Timer? _delayedQualityHarvestTimer;
  int _delayedQualityHarvestTicket = 0;

  String? _lastTrusted;
  String? _currentHost;
  String? _currentPageUrl;
  String? _currentPageTitle;
  String? _currentMediaTitle;
  String? _lastStableWatchUrl;

  String? _capturedVideoUrl;
  double _capturedVideoTime = 0;
  String? _capturedVideoPageUrl;
  String? _capturedVideoMimeType;

  final int _videoAspectW = 16;
  final int _videoAspectH = 9;

  final List<DownloadItem> _downloads = [];
  Timer? _backgroundDownloadSyncTimer;
  final Set<String> _discoveredDownloadUrls = {};
  final Set<String> _runtimeAllowedHosts = {};
  final List<CapturedMediaItem> _capturedMedia = [];
  final Set<String> _capturedMediaSeen = {};
  final Map<String, Map<String, String>> _capturedRequestHeadersByUrl = <String, Map<String, String>>{};
  Map<String, String> _latestPlayableRequestHeaders = const <String, String>{};
  String? _latestPlayableRequestUrl;

  bool _showDownloads = false;
  bool _showMediaGrabber = false;
  bool _captureEngineSuspended = false;
  bool _fullscreenBusy = false;
  String? _lastDetectedMediaUrl;
  String? _lastDetectedMediaType;
  bool _autoDownloadPromptShown = false;

  static final MethodChannel _pip = MethodChannel(AppSecureText.s('IhmDL74rYtAK6atQiPOW'));

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36';

  bool get _useLightHiddenWebView => widget.launchHidden || widget.downloadOnlyMode;

  bool get _useMinimalDirectLaunchScripts => widget.launchHidden && !widget.downloadOnlyMode;

  UnmodifiableListView<UserScript> get _activeUserScripts {
    if (_useMinimalDirectLaunchScripts) {
      return UnmodifiableListView([
        UserScript(
          source: _stealthAdBlock,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
        UserScript(
          source: _ads,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
        UserScript(
          source: _networkMediaProbe,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
        UserScript(
          source: _interceptSourceApi,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
        UserScript(
          source: _smartVideasyPlayClick,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
          forMainFrameOnly: false,
        ),
      ]);
    }

    return UnmodifiableListView([
      UserScript(
        source: _stealthAdBlock,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
      UserScript(
        source: _ads,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
      UserScript(
        source: _desktopViewport,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
      UserScript(
        source: _css,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
      UserScript(
        source: _forcePhoneFullscreen,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
      UserScript(
        source: _fsVid,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
      UserScript(
        source: _touchFix,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
      UserScript(
        source: _iframeVideoFix,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
      UserScript(
        source: _hideServers,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
      ),
      UserScript(
        source: _dlCapture,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
      ),
      UserScript(
        source: _networkMediaProbe,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
      UserScript(
        source: _captureOptions,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
        forMainFrameOnly: false,
      ),
      UserScript(
        source: _interceptSourceApi,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
      UserScript(
        source: _smartVideasyPlayClick,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
        forMainFrameOnly: false,
      ),
    ]);
  }

  Widget _buildWebViewHost(Widget child) {
    if (widget.downloadOnlyMode) {
      return Positioned(
        right: 0,
        bottom: 0,
        width: 2,
        height: 2,
        child: IgnorePointer(ignoring: true, child: child),
      );
    }
    if (_hideSiteDuringDirectLaunch) {
      return Positioned(
        left: -10000,
        top: -10000,
        width: 1,
        height: 1,
        child: IgnorePointer(ignoring: true, child: child),
      );
    }
    return Positioned.fill(child: child);
  }

  static const _videoExts = [
    '.m3u8', '.mp4', '.mkv', '.webm', '.ts', '.m4v', '.avi', '.mov',
  ];

  static const _dlExts = [
    '.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v',
  ];

  // ─── FIX 3: Added download site domains to whitelist ───────────────────
  final _white = const [
    "asd.pics", "hglink", "vibuxer", "audinifer", "huntrexus", "hanerix",
    "dood", "doods", "dooood", "ds2play", "d0o0d", "doodstream", "dood.li",
    "uqload", "uqloads", "minochinos", "minomax", "pixibay", "streamtape",
    "stape", "voe.sx", "voeunblok", "voe", "jwplatform", "jwpcdn",
    "akamaized", "cloudfront", "cdnjs.cloudflare", "fonts.googleapis",
    "fonts.gstatic", "kit-pro.fontawesome", "kit-free.fontawesome",
    "static.cloudflareinsights", "vidtube", "1cloudfile", "masukestin",
    "cdn.vidtube", "s3.amazonaws", "googleapis", "gstatic", "bunnycdn",
    "b-cdn", "storage.googleapis", "cdn-tube", "stellarcrestcreative",
    "server-hls2-stream", "server-hls", "cdn-stream", "arabseed",
    "m.arabseed.show", "arabseed.show",
    "player.videasy.net", "videasy.net", "videasy",
    "api2.videasy.net", "db.videasy.net", "users.videasy.net",
    "vidfast.pro", "www.vidfast.pro",
    "10017.workers.dev",
    "hockey.10017.workers.dev", "hockey",
    "rainorbit33.xyz", "nightbreeze17.site",
    "quietlynx14.site", "megafiles.store",
    "cca.megafiles.store",
    // ✅ FIX 3+: Download hosting sites + redirect targets actually used by ArabSeed
    "mega.nz", "mediafire", "1fichier", "uploadrar", "uptobox",
    "usersdrive", "filerio", "clicknupload", "hexupload", "sendcm",
    "dailyuploads", "turbobit", "nitroflare", "rapidgator", "katfile",
    "filefox", "racaty", "gofile", "pixeldrain", "fembed", "mixdrop",
    "reviewrate", "reviewrate.net", "m.reviewrate.net",
    "fredl", "fredl.ru", "frdl",
    "filespayouts", "filespayouts.com",
    "up-4ever", "up-4ever.net", "up4ever",
  ];

  final _blocked = const [
    "pyppo.com", "popcash.net", "popads.net", "popunder.net", "pop.pro",
    "clickunder.net", "trafficshop.com", "plugrush.com", "adcash.com",
    "zeropark.com", "richpush.co", "doubleclick.net", "googlesyndication.com",
    "adservice.google.com", "pagead2.googlesyndication.com",
    "tpc.googlesyndication.com", "adnxs.com", "rubiconproject.com",
    "openx.net", "casalemedia.com", "criteo.com", "taboola.com",
    "outbrain.com", "revcontent.com", "mgid.com", "propellerads.com",
    "hilltopads.net", "exoclick.com", "juicyads.com", "trafficjunky.net",
    "adsterra.com", "bvtpk.com", "b7510.com", "405kk.com", "071kk.com",
    "crummydevioussucculent.com", "yawncollaremotion.com",
    "preferencenail.com", "newshinyd.com", "bobapsoabauns.com",
    "fleraprt.com", "tzegilo.com", "imasdk.googleapis.com",
    "googletagmanager.com", "mc.yandex.ru", "dtscout.com", "dtscdn.com",
    "mrktmtrcs.net", "onaudience.com", "histats.com", "rtmark.net",
    "44555games.com", "trffk.g2afse.com", "tiktokcdn.com", "llvpn.com",
    "affidavitheadfirstonward.com", "omoonsih.net", "jnbhi.com", "oyo4d.com",
    "sourshaped.com", "deductpursue.com", "protrafficinspector.com",
    "tfnvuckb.pro", "waust.at", "whacmoltibsay.net",
    "fundingchoicesmessages.google.com",
    "ads.pubmatic.com", "securepubads.g.doubleclick.net",
  ];

  final _redirectOk = const [
    "asd.pics", "hglink", "vibuxer", "audinifer", "huntrexus", "hanerix",
    "dood", "doods", "ds2play", "d0o0d", "doodstream", "uqload", "uqloads",
    "minochinos", "minomax", "streamtape", "stape", "voe.sx", "voeunblok",
    "voe", "jwplatform", "jwpcdn", "vidtube", "1cloudfile", "masukestin",
    "cdn.vidtube", "s3.amazonaws", "googleapis", "bunnycdn", "b-cdn",
    "cdn-tube", "stellarcrestcreative", "server-hls2-stream", "server-hls",
    "arabseed", "m.arabseed.show", "arabseed.show",
    "player.videasy.net", "videasy.net", "videasy",
    "vidfast.pro", "www.vidfast.pro", "vidfast",
    "10017.workers.dev",
    "hockey.10017.workers.dev", "hockey",
    "rainorbit33.xyz", "nightbreeze17.site",
    "quietlynx14.site", "megafiles.store",
    "reviewrate", "reviewrate.net", "m.reviewrate.net",
    "fredl", "fredl.ru", "frdl",
    "filespayouts", "filespayouts.com",
    "up-4ever", "up-4ever.net", "up4ever",
  ];

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase().split('?').first;
    return _videoExts.any((e) => lower.endsWith(e));
  }

  bool _isDownloadUrl(String url) {
    final lower = url.toLowerCase().split('?').first;
    return _dlExts.any((e) => lower.endsWith(e));
  }

  bool _isW(String u) => _white.any((d) => u.contains(d));
  bool _isB(String u) => _blocked.any((d) => u.contains(d));
  bool _canRedir(String u) => _redirectOk.any((d) => u.contains(d));

  String? _hostOf(String? rawUrl) {
    final host = Uri.tryParse(rawUrl ?? '')?.host.toLowerCase();
    if (host == null || host.isEmpty) return null;
    return host;
  }

  void _rememberAllowedHost(String? rawUrl) {
    final host = _hostOf(rawUrl);
    if (host == null) return;
    _runtimeAllowedHosts.add(host);
  }

  bool _isRuntimeAllowed(String? rawUrl) {
    final host = _hostOf(rawUrl);
    if (host == null) return false;
    return _runtimeAllowedHosts.any((allowed) =>
        host == allowed || host.endsWith('.$allowed') || allowed.endsWith('.$host'));
  }

  String? _decodeArabseedRedirect(String? rawUrl) {
    final uri = Uri.tryParse(rawUrl ?? '');
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (!(host.contains('asd.pics') || host.contains('arabseed'))) return null;
    if (uri.pathSegments.isEmpty) return null;
    if (uri.pathSegments.first != 'l') return null;

    try {
      var encoded = uri.pathSegments.last;
      encoded = encoded.replaceAll('-', '+').replaceAll('_', '/');
      while (encoded.length % 4 != 0) {
        encoded += '=';
      }
      final decoded = utf8.decode(base64.decode(encoded), allowMalformed: true).trim();
      if (decoded.startsWith('http://') || decoded.startsWith('https://')) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  bool _isLikelyDownloadLandingUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('/downloadz') ||
        lower.contains('/download/') ||
        lower.contains('/l/') ||
        lower.contains('reviewrate') ||
        lower.contains('fredl') ||
        lower.contains('frdl') ||
        lower.contains('filespayouts') ||
        lower.contains('up-4ever') ||
        lower.contains('up4ever');
  }

  String _sanitizeFileName(String input) {
    final clean = input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return clean.isEmpty ? 'video.mp4' : clean;
  }

  String _inferFileName(String url, [String fallback = 'video.mp4']) {
    try {
      final uri = Uri.parse(url);
      final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : fallback;
      final decoded = Uri.decodeComponent(last);
      if (decoded.isNotEmpty && decoded.contains('.')) {
        return _sanitizeFileName(decoded);
      }
    } catch (_) {}
    return _sanitizeFileName(fallback);
  }

  String _cleanMediaTitle(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    value = value.replaceAll(RegExp(r'\s*[|｜\-–—]\s*(arabseed|asd\s*pics|عرب\s*سيد).*$', caseSensitive: false), ' ');
    value = value.replaceAll(RegExp(r'\b(ArabSeed|ASD\s*Pics)\b', caseSensitive: false), ' ');
    value = value.replaceAll(RegExp(r'\b(مشاهدة|تحميل|اون\s*لاين|أون\s*لاين|كامل|مترجم)\b', caseSensitive: false), ' ');
    value = value.replaceAll(RegExp(r'[_\-]+'), ' ');
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return _sanitizeFileName(value);
  }

  String _fallbackTitleFromUrl([String? rawUrl]) {
    final url = (rawUrl ?? _currentPageUrl ?? _capturedVideoPageUrl ?? '').trim();
    if (url.isEmpty) return '';
    try {
      final uri = Uri.parse(url);
      final segs = uri.pathSegments.where((e) => e.trim().isNotEmpty).toList();
      if (segs.isEmpty) return '';
      var slug = Uri.decodeComponent(segs.last);
      slug = slug.replaceAll(RegExp(r'\.(html?|php)$', caseSensitive: false), '');
      return _cleanMediaTitle(slug);
    } catch (_) {
      return '';
    }
  }

  String _preferredMediaBaseName() {
    for (final candidate in <String?>[widget.headerTitle, _currentMediaTitle, _currentPageTitle, _fallbackTitleFromUrl()]) {
      final clean = _cleanMediaTitle(candidate ?? '');
      if (clean.isNotEmpty) return clean;
    }
    return 'video';
  }

  String _downloadLibraryTitle() {
    return _preferredMediaBaseName();
  }

  String _downloadEpisodeCode() {
    if (widget.mediaType == MediaType.tv && widget.season != null && widget.episode != null) {
      return 'S${widget.season!.toString().padLeft(2, '0')}E${widget.episode!.toString().padLeft(2, '0')}';
    }
    return '';
  }

  String _currentMediaTitleForSaving() {
    final title = _preferredMediaBaseName();
    final episodeCode = _downloadEpisodeCode();
    return episodeCode.isEmpty ? title : '$title - $episodeCode';
  }

  Future<Directory> _downloadTargetDirectory() async {
    final base = await _downloadsBaseDir();
    final title = _downloadLibraryTitle();
    Directory dir;
    if (widget.mediaType == MediaType.tv) {
      final seasonFolder = 'Season ${(widget.season ?? 1).toString().padLeft(2, '0')}';
      dir = Directory('${base.path}/Series/$title/$seasonFolder');
    } else {
      dir = Directory('${base.path}/Movies/$title');
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _buildManagedDownloadFileName({
    required String extension,
    String? qualityLabel,
  }) {
    final ext = extension.startsWith('.') ? extension : '.${extension.replaceAll('.', '')}';
    final title = _downloadLibraryTitle();
    final normalizedQuality = _normalizeQualityLabel(qualityLabel ?? '');
    final episodeCode = _downloadEpisodeCode();
    final base = episodeCode.isEmpty ? title : '$title - $episodeCode';
    final suffix = normalizedQuality.isEmpty ? '' : ' - $normalizedQuality';
    return _sanitizeFileName('$base$suffix$ext');
  }

  Future<void> _persistDownloadLibraryEntry({
    required String fullPath,
    required String fileName,
    String? qualityLabel,
    String? thumbnailPath,
  }) async {
    final title = _downloadLibraryTitle();
    final groupKey = widget.mediaType == MediaType.tv
        ? 'tv:${widget.tmdbId ?? title.toLowerCase()}'
        : 'movie:${widget.tmdbId ?? title.toLowerCase()}';
    final existingIndex = await _DownloadLibraryIndexStore.loadIndex();
    final fallbackPosterUrl = existingIndex.values
        .where((e) => e.groupKey == groupKey && (e.posterUrl ?? '').trim().isNotEmpty)
        .map((e) => e.posterUrl!.trim())
        .cast<String?>()
        .firstWhere((e) => e != null && e.isNotEmpty, orElse: () => null);
    final resolvedPosterUrl = (widget.loadingPosterUrl ?? '').trim().isNotEmpty
        ? widget.loadingPosterUrl!.trim()
        : fallbackPosterUrl;
    await _DownloadLibraryIndexStore.upsert(
      _DownloadLibraryMetadata(
        path: fullPath,
        title: title,
        groupKey: groupKey,
        posterUrl: resolvedPosterUrl,
        thumbnailPath: thumbnailPath,
        mediaType: widget.mediaType?.name,
        tmdbId: widget.tmdbId,
        season: widget.season,
        episode: widget.episode,
        qualityLabel: _normalizeQualityLabel(qualityLabel ?? ''),
        fileName: fileName,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }


  Future<void> _persistActiveDownloadLibraryEntry({
    required String tempPath,
    required String finalPath,
    required String fileName,
    String? qualityLabel,
    String? thumbnailPath,
    required String status,
    required double progress,
    String? downloadId,
  }) async {
    final title = _downloadLibraryTitle();
    final groupKey = widget.mediaType == MediaType.tv
        ? 'tv:${widget.tmdbId ?? title.toLowerCase()}'
        : 'movie:${widget.tmdbId ?? title.toLowerCase()}';
    final existingIndex = await _DownloadLibraryIndexStore.loadIndex();
    final fallbackPosterUrl = existingIndex.values
        .where((e) => e.groupKey == groupKey && (e.posterUrl ?? '').trim().isNotEmpty)
        .map((e) => e.posterUrl!.trim())
        .cast<String?>()
        .firstWhere((e) => e != null && e.isNotEmpty, orElse: () => null);
    final resolvedPosterUrl = (widget.loadingPosterUrl ?? '').trim().isNotEmpty
        ? widget.loadingPosterUrl!.trim()
        : fallbackPosterUrl;
    final createdAtMs = DateTime.now().millisecondsSinceEpoch;
    final normalizedQualityLabel = _normalizeQualityLabel(qualityLabel ?? '');
    final normalizedProgress = progress.clamp(0.0, 1.0);

    await _DownloadLibraryIndexStore.upsert(
      _DownloadLibraryMetadata(
        path: tempPath,
        finalPath: finalPath,
        title: title,
        groupKey: groupKey,
        posterUrl: resolvedPosterUrl,
        thumbnailPath: thumbnailPath,
        mediaType: widget.mediaType?.name,
        tmdbId: widget.tmdbId,
        season: widget.season,
        episode: widget.episode,
        qualityLabel: normalizedQualityLabel,
        fileName: fileName,
        status: status,
        progress: normalizedProgress,
        downloadId: downloadId,
        createdAtMs: createdAtMs,
      ),
    );

    final normalizedFinalPath = finalPath.trim();
    if (normalizedFinalPath.isNotEmpty && normalizedFinalPath != tempPath.trim()) {
      await _DownloadLibraryIndexStore.upsert(
        _DownloadLibraryMetadata(
          path: normalizedFinalPath,
          finalPath: normalizedFinalPath,
          title: title,
          groupKey: groupKey,
          posterUrl: resolvedPosterUrl,
          thumbnailPath: thumbnailPath,
          mediaType: widget.mediaType?.name,
          tmdbId: widget.tmdbId,
          season: widget.season,
          episode: widget.episode,
          qualityLabel: normalizedQualityLabel,
          fileName: fileName,
          status: status,
          progress: normalizedProgress,
          downloadId: downloadId,
          createdAtMs: createdAtMs,
        ),
      );
    }
  }

  String _contextualFileName(String url, {String? qualityLabel, String fallbackExt = 'mp4'}) {
    final inferred = _inferFileName(url, 'video.$fallbackExt');
    final dot = inferred.lastIndexOf('.');
    final ext = dot > 0 ? inferred.substring(dot) : '.${fallbackExt.replaceAll('.', '')}';
    final base = _preferredMediaBaseName();
    return _appendQualitySuffixToFileName('$base$ext', qualityLabel);
  }

  bool _looksLikeSubtitleUrl(String? url) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) return false;
    final lower = raw.toLowerCase();
    return lower.contains('.vtt') ||
        lower.contains('.srt') ||
        lower.contains('.ass') ||
        lower.contains('.ssa') ||
        lower.contains('.sub') ||
        lower.contains('mime=text/vtt') ||
        lower.contains('contenttype=text/vtt') ||
        lower.contains('subtitle');
  }

  String _subtitleLanguageCode(Map<String, String> track) {
    final language = (track['language'] ?? '').trim().toLowerCase();
    if (language.startsWith('ar')) return 'ar';
    if (language.startsWith('en')) return 'en';
    if (language.startsWith('zh') || language.startsWith('chi')) return 'zh';
    final label = (track['label'] ?? '').trim().toLowerCase();
    if (label.contains('arab') || label.contains('عرب')) return 'ar';
    if (label.contains('english')) return 'en';
    if (label.contains('中文') || label.contains('chinese')) return 'zh';
    return language.replaceAll(RegExp(r'[^a-z]'), '').ifEmpty('sub');
  }

  Future<void> _ensureSubtitleTracksForSidecarDownload() async {
    if (widget.deferredSubtitleTracksFuture != null) {
      try {
        final tracks = await widget.deferredSubtitleTracksFuture!
            .timeout(const Duration(minutes: 4));
        if (tracks.isNotEmpty) {
          _externalSubtitleTracks = _mergeSubtitleTrackMaps([
            ..._externalSubtitleTracks,
            ...tracks,
          ]);
        }
      } catch (_) {}
    }

    if (_hasTmdbContext && !WyziePrefetchService._hasCompleteStoredSubtitleSet(_externalSubtitleTracks)) {
      try {
        await _refreshExternalSubtitles(force: true);
      } catch (_) {}
    }

    try {
      final stored = await WyziePrefetchService.loadStoredTracks(
        tmdbId: widget.tmdbId ?? 0,
        mediaType: widget.mediaType ?? MediaType.movie,
        season: widget.season,
        episode: widget.episode,
      );
      if (stored.isNotEmpty) {
        _externalSubtitleTracks = _mergeSubtitleTrackMaps([
          ..._externalSubtitleTracks,
          ...stored,
        ]);
      }
    } catch (_) {}
  }

  Future<List<Map<String, String>>> _collectSubtitleTracksForDownloadWindow({
    Duration window = const Duration(minutes: 4),
    Future<void> Function(List<Map<String, String>> tracks)? onTracks,
  }) async {
    final startedAt = DateTime.now();
    final deadline = startedAt.add(window);
    final collected = <Map<String, String>>[];
    String lastPublishedFingerprint = '';

    void absorb(Iterable<Map<String, String>> tracks) {
      final prepared = _sanitizeSubtitleTrackList(tracks);
      if (prepared.isEmpty) return;
      final merged = _mergeSubtitleTrackMaps([
        ..._externalSubtitleTracks,
        ...collected,
        ...prepared,
      ]);
      _externalSubtitleTracks = merged;
      collected
        ..clear()
        ..addAll(merged);
    }

    Future<void> publishIfChanged() async {
      if (onTracks == null || collected.isEmpty) return;
      final snapshot = _mergeSubtitleTrackMaps(collected)
        ..sort((a, b) => _subtitlePreferenceScore(a).compareTo(_subtitlePreferenceScore(b)));
      final fingerprint = snapshot
          .map((track) => WyziePrefetchService._subtitleTrackIdentity(track))
          .join('||');
      if (fingerprint.isEmpty || fingerprint == lastPublishedFingerprint) return;
      lastPublishedFingerprint = fingerprint;
      try {
        await onTracks(snapshot.take(64).toList(growable: false));
      } catch (_) {}
    }

    absorb(_externalSubtitleTracks);
    await publishIfChanged();

    Future<void> collectStored() async {
      if (!_hasTmdbContext) return;
      try {
        final stored = await WyziePrefetchService.loadStoredTracks(
          tmdbId: widget.tmdbId!,
          mediaType: widget.mediaType!,
          season: widget.mediaType == MediaType.tv ? widget.season : null,
          episode: widget.mediaType == MediaType.tv ? widget.episode : null,
        ).timeout(window, onTimeout: () => const <Map<String, String>>[]);
        absorb(stored);
        await publishIfChanged();
      } catch (_) {}
    }

    Future<void> collectDeferred() async {
      final deferred = widget.deferredSubtitleTracksFuture;
      if (deferred == null) return;
      try {
        final tracks = await deferred.timeout(
          window,
          onTimeout: () => const <Map<String, String>>[],
        );
        absorb(tracks);
        await publishIfChanged();
      } catch (_) {}
    }

    Future<void> collectProvider(Future<List<Map<String, String>>> future) async {
      try {
        final tracks = await future.timeout(
          window,
          onTimeout: () => const <Map<String, String>>[],
        );
        absorb(tracks);
        await publishIfChanged();
      } catch (_) {}
    }

    await collectStored();
    await collectDeferred();

    if (WyziePrefetchService._hasCompleteStoredSubtitleSet(collected)) {
      final sorted = _mergeSubtitleTrackMaps(collected)
        ..sort((a, b) => _subtitlePreferenceScore(a).compareTo(_subtitlePreferenceScore(b)));
      return sorted.take(64).toList(growable: false);
    }

    final futures = <Future<void>>[];

    if (_hasTmdbContext) {
      final title = widget.headerTitle ?? _currentMediaTitle ?? _currentPageTitle;
      futures.addAll([
        collectProvider(WyziePrefetchService._fetchSubsourceProviderTracks(
          tmdbId: widget.tmdbId!,
          mediaType: widget.mediaType!,
          title: title,
          season: widget.mediaType == MediaType.tv ? widget.season : null,
          episode: widget.mediaType == MediaType.tv ? widget.episode : null,
        )),
        collectProvider(WyziePrefetchService._fetchSubdlProviderTracks(
          tmdbId: widget.tmdbId!,
          mediaType: widget.mediaType!,
          title: title,
          season: widget.mediaType == MediaType.tv ? widget.season : null,
          episode: widget.mediaType == MediaType.tv ? widget.episode : null,
        )),
        (() async {
          try {
            await _refreshExternalSubtitles(force: true).timeout(
              window,
              onTimeout: () {},
            );
            absorb(_externalSubtitleTracks);
            await publishIfChanged();
          } catch (_) {}
        })(),
      ]);
    }

    while (DateTime.now().isBefore(deadline)) {
      absorb(_externalSubtitleTracks);
      await publishIfChanged();
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      final delay = remaining < const Duration(milliseconds: 420)
          ? remaining
          : const Duration(milliseconds: 420);
      await Future.delayed(delay);
    }

    absorb(_externalSubtitleTracks);
    await publishIfChanged();
    await Future.wait(futures, eagerError: false).timeout(
      const Duration(seconds: 2),
      onTimeout: () => const <void>[],
    ).catchError((_) => const <void>[]);
    absorb(_externalSubtitleTracks);
    await publishIfChanged();

    final sorted = _mergeSubtitleTrackMaps(collected)
      ..sort((a, b) => _subtitlePreferenceScore(a).compareTo(_subtitlePreferenceScore(b)));
    return sorted.take(64).toList(growable: false);
  }

  Future<Map<String, String>?> _pickBestSubtitleTrackForCurrentMedia() async {
    await _ensureSubtitleTracksForSidecarDownload();
    final sortedTracks = List<Map<String, String>>.from(_removeRawArchiveSubtitleTracks(_externalSubtitleTracks))
      ..sort((a, b) => _subtitlePreferenceScore(a).compareTo(_subtitlePreferenceScore(b)));
    for (final track in sortedTracks) {
      final rawUrl = (track['url'] ?? '').trim();
      if (rawUrl.isEmpty) continue;
      String resolvedUrl = rawUrl;
      try {
        final headers = await _buildSmartDownloadHeaders(
          rawUrl,
          pageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted,
        );
        resolvedUrl = await _materializeSubtitleUrlForNative(rawUrl, headers);
      } catch (_) {}
      if (!_looksLikeSubtitleUrl(resolvedUrl)) continue;
      final out = Map<String, String>.from(track);
      out['url'] = resolvedUrl;
      final mime = (out['mimeType'] ?? '').trim().ifEmpty(_subtitleMimeFromName(resolvedUrl));
      if (mime.isNotEmpty) out['mimeType'] = mime;
      if (mime.toLowerCase().contains('zip') || mime.toLowerCase().contains('rar') || mime.toLowerCase().contains('7z')) {
        continue;
      }
      return out;
    }
    return null;
  }

  String _sidecarSubtitlePathForVideo(String videoPath, Map<String, String> track) {
    final file = File(videoPath);
    final parent = file.parent.path;
    final fileName = file.uri.pathSegments.isEmpty ? file.path.split(Platform.pathSeparator).last : file.uri.pathSegments.last;
    final dot = fileName.lastIndexOf('.');
    final baseName = dot > 0 ? fileName.substring(0, dot) : fileName;
    final lang = _subtitleLanguageCode(track);
    final ext = _subtitleMimeFromName((track['url'] ?? '').trim()).contains('vtt')
        ? '.vtt'
        : (_subtitleMimeFromName((track['url'] ?? '').trim()).contains('srt') ? '.srt' : '.vtt');
    final suffix = lang == 'sub' ? '.subtitle' : '.$lang';
    return '$parent/${_sanitizeFileName('$baseName$suffix')}$ext';
  }

  String _sidecarExtFromTrackOrPath(Map<String, String> track, String pathOrUrl) {
    final hinted = (track['mimeType'] ?? '').trim().ifEmpty(_subtitleMimeFromName(pathOrUrl)).toLowerCase();
    final lower = pathOrUrl.toLowerCase();
    if (lower.endsWith('.vtt') || hinted.contains('text/vtt')) return '.vtt';
    if (lower.endsWith('.ass') || hinted.contains('ass') || hinted.contains('ssa')) return '.ass';
    if (lower.endsWith('.ssa')) return '.ssa';
    if (lower.endsWith('.srt') || hinted.contains('subrip')) return '.srt';
    return '.vtt';
  }

  Future<Map<String, String>?> _copyLocalSubtitleSidecar({
    required String videoPath,
    required Map<String, String> track,
    required int index,
  }) async {
    final rawUrl = (track['url'] ?? '').trim();
    if (rawUrl.isEmpty) return null;
    File? sourceFile;
    final parsed = Uri.tryParse(rawUrl);
    if (parsed != null && parsed.scheme == 'file') {
      sourceFile = File.fromUri(parsed);
    } else if (rawUrl.startsWith('/')) {
      sourceFile = File(rawUrl);
    }
    if (sourceFile == null || !await sourceFile.exists()) return null;

    final videoFile = File(videoPath);
    final parent = videoFile.parent;
    final videoName = videoFile.uri.pathSegments.isEmpty
        ? videoFile.path.split(Platform.pathSeparator).last
        : videoFile.uri.pathSegments.last;
    final dot = videoName.lastIndexOf('.');
    final baseName = dot > 0 ? videoName.substring(0, dot) : videoName;
    final lang = _subtitleLanguageCode(track);
    final source = _sanitizeFileName((track['source'] ?? 'Subtitle').replaceAll('•', '-'));
    final label = _sanitizeFileName((track['label'] ?? 'Subtitle').replaceAll('•', '-'));
    final unique = rawUrl.hashCode.abs().toRadixString(16).padLeft(8, '0');
    final ext = _sidecarExtFromTrackOrPath(track, sourceFile.path);
    final fileName = _sanitizeFileName(
      '$baseName ${index.toString().padLeft(2, '0')} - $lang - $source - $label - $unique',
    ) + ext;
    final target = File('${parent.path}/$fileName');
    await target.parent.create(recursive: true);
    if (await target.exists() && await target.length() > 16) {
      return {
        ...track,
        'url': Uri.file(target.path).toString(),
        'mimeType': _subtitleMimeFromName(target.path),
        'fileName': fileName,
      };
    }
    await sourceFile.copy(target.path);
    if (await target.exists() && await target.length() > 16) {
      return {
        ...track,
        'url': Uri.file(target.path).toString(),
        'mimeType': _subtitleMimeNameForLocalFile(target.path),
        'fileName': fileName,
      };
    }
    return null;
  }

  String _localSubtitleMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.vtt')) return 'text/vtt';
    if (lower.endsWith('.srt')) return 'application/x-subrip';
    if (lower.endsWith('.ass') || lower.endsWith('.ssa')) return 'text/x-ssa';
    if (lower.endsWith('.ttml') || lower.endsWith('.xml')) return 'application/ttml+xml';
    return 'text/vtt';
  }

  String _subtitleMimeNameForLocalFile(String path) {
    final mime = _subtitleMimeFromName(path);
    if (mime.isNotEmpty) return mime;
    return _localSubtitleMimeType(path);
  }

  Future<void> _downloadMatchingSubtitleSidecar(
    String videoPath, {
    Duration window = const Duration(minutes: 4),
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      try {
        final existingSidecars = await _collectLocalSidecarSubtitleTracks(videoPath);
        if (WyziePrefetchService._hasCompleteStoredSubtitleSet(existingSidecars)) {
          return;
        }
      } catch (_) {}
    }

    final videoFile = File(videoPath);
    final parent = videoFile.parent;
    final videoName = videoFile.uri.pathSegments.isEmpty
        ? videoFile.path.split(Platform.pathSeparator).last
        : videoFile.uri.pathSegments.last;
    final dot = videoName.lastIndexOf('.');
    final baseName = dot > 0 ? videoName.substring(0, dot) : videoName;
    await parent.create(recursive: true);

    final savedTrackIdentities = <String>{};
    try {
      for (final track in await _collectLocalSidecarSubtitleTracks(videoPath)) {
        savedTrackIdentities.add(WyziePrefetchService._subtitleTrackIdentity(track));
      }
    } catch (_) {}
    var index = savedTrackIdentities.length + 1;

    Future<void> persistTracks(List<Map<String, String>> tracks) async {
      if (tracks.isEmpty) return;
      for (final rawTrack in tracks.take(64)) {
        final rawUrl = (rawTrack['url'] ?? '').trim();
        if (rawUrl.isEmpty) continue;
        final identity = WyziePrefetchService._subtitleTrackIdentity(rawTrack);
        if (identity.isEmpty || savedTrackIdentities.contains(identity)) continue;
        if (!_downloadingSubtitleUrls.add(rawUrl)) continue;

        try {
          final parsed = Uri.tryParse(rawUrl);
          final isLocal = (parsed != null && parsed.scheme == 'file') || rawUrl.startsWith('/');
          Map<String, String>? saved;
          if (isLocal) {
            saved = await _copyLocalSubtitleSidecar(
              videoPath: videoPath,
              track: rawTrack,
              index: index,
            );
          } else {
            saved = await WyziePrefetchService._downloadTrackToFile(
              track: rawTrack,
              targetDir: parent,
              baseName: baseName,
              index: index,
              mediaType: widget.mediaType ?? MediaType.movie,
              title: widget.headerTitle,
              season: widget.season,
              episode: widget.episode,
            );
          }
          if (saved != null) {
            savedTrackIdentities.add(identity);
            index++;
          }
        } catch (_) {
        } finally {
          _downloadingSubtitleUrls.remove(rawUrl);
        }
      }
    }

    final sortedTracks = await _collectSubtitleTracksForDownloadWindow(
      window: window,
      onTracks: persistTracks,
    );
    await persistTracks(sortedTracks);
  }

  Future<List<Map<String, String>>> _collectLocalSidecarSubtitleTracks(String videoPath) async {
    try {
      final file = File(videoPath);
      if (!await file.exists()) return const <Map<String, String>>[];
      final name = file.uri.pathSegments.isEmpty ? file.path.split(Platform.pathSeparator).last : file.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      final baseName = dot > 0 ? name.substring(0, dot) : name;
      final dir = file.parent;
      if (!await dir.exists()) return const <Map<String, String>>[];
      final out = <Map<String, String>>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final childName = entity.uri.pathSegments.isEmpty ? entity.path.split(Platform.pathSeparator).last : entity.uri.pathSegments.last;
        final lower = childName.toLowerCase();
        if (!(lower.endsWith('.vtt') ||
            lower.endsWith('.srt') ||
            lower.endsWith('.ass') ||
            lower.endsWith('.ssa') ||
            lower.endsWith('.ttml') ||
            lower.endsWith('.xml'))) {
          continue;
        }
        final childLower = childName.toLowerCase();
        final baseLower = baseName.toLowerCase();
        final safeBaseLower = _sanitizeFileName(baseName).toLowerCase();
        final matchesBase = childLower == '$baseLower.vtt' ||
            childLower == '$baseLower.srt' ||
            childLower == '$baseLower.ass' ||
            childLower == '$baseLower.ssa' ||
            childLower == '$baseLower.ttml' ||
            childLower == '$baseLower.xml' ||
            childLower.startsWith('$baseLower.') ||
            childLower.startsWith('$baseLower ') ||
            childLower.startsWith('$safeBaseLower.') ||
            childLower.startsWith('$safeBaseLower ');
        if (!matchesBase) {
          continue;
        }
        try {
          if (await entity.length() < 32) continue;
        } catch (_) {
          continue;
        }
        final url = Uri.file(entity.path).toString();
        final langPart = lower.replaceFirst(baseName.toLowerCase(), '').replaceAll('.', ' ').trim();
        final sidecarBlob = '$childName $url'.toLowerCase();
        final isSubSource = sidecarBlob.contains('subsource') || sidecarBlob.contains('عربي 1') || sidecarBlob.contains('arabic 1');
        final isArabic2 = !isSubSource && (sidecarBlob.contains('subdl') || sidecarBlob.contains('عربي 2') || sidecarBlob.contains('arabic2'));
        final isArabic = langPart.contains('ar') || sidecarBlob.contains('arabic') || sidecarBlob.contains('عرب');
        final label = isSubSource
            ? 'عربي 1'
            : (isArabic2 ? 'عربي 2' : (isArabic ? 'Arabic' : (langPart.contains('en') ? 'English' : 'Subtitle')));
        out.add({
          'label': label,
          'url': url,
          'language': isArabic ? 'ar' : (langPart.contains('en') ? 'en' : ''),
          'source': isSubSource ? 'عربي 1' : (isArabic2 ? 'عربي 2' : 'Local Download'),
          if (isArabic2) 'providerGroup': 'arabic2',
          if (isSubSource) 'providerGroup': 'subsource-api',
          'fileName': childName,
          'mimeType': _subtitleMimeFromName(entity.path),
          'default': 'false',
          'autoSelect': 'false',
        });
      }
      out.sort((a, b) {
        int rank(Map<String, String> item) {
          final lang = (item['language'] ?? '').toLowerCase();
          final blob = [item['fileName'], item['label'], item['source'], item['url']]
              .whereType<String>()
              .join(' ')
              .toLowerCase();
          final isArabic2Backup = blob.contains('عربي 2') || blob.contains('subdl');
          final isSubSource = blob.contains('subsource');
          if (isSubSource && (lang == 'ar' || blob.contains('arabic') || blob.contains('عرب'))) return -20;
          if ((lang == 'ar' || blob.contains('arabic') || blob.contains('عرب')) && !isArabic2Backup) return 0;
          if (isArabic2Backup) return 20;
          if (lang == 'en') return 30;
          return 40;
        }
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        return (a['url'] ?? '').toLowerCase().compareTo((b['url'] ?? '').toLowerCase());
      });
      final merged = _mergeSubtitleTrackMaps(out);
      if (merged.isNotEmpty) {
        for (final item in merged) {
          item['default'] = 'false';
          item['autoSelect'] = 'false';
        }
        final primaryIndex = merged.indexWhere((item) => WyziePrefetchService._isPrimarySubsourceTrackMap(item));
        if (primaryIndex >= 0) {
          merged[primaryIndex]['default'] = 'true';
          merged[primaryIndex]['autoSelect'] = 'true';
        }
      }
      return merged;
    } catch (_) {
      return const <Map<String, String>>[];
    }
  }

  Future<void> _deleteLocalSidecarSubtitleFiles(String videoPath) async {
    try {
      final tracks = await _collectLocalSidecarSubtitleTracks(videoPath);
      final seen = <String>{};
      for (final track in tracks) {
        final rawUrl = (track['url'] ?? '').trim();
        if (rawUrl.isEmpty) continue;
        File? file;
        final uri = Uri.tryParse(rawUrl);
        if (uri != null && uri.scheme == 'file') {
          file = File.fromUri(uri);
        } else if (rawUrl.startsWith('/')) {
          file = File(rawUrl);
        }
        if (file == null) continue;
        final path = file.path;
        if (!seen.add(path)) continue;
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> _refreshMatchingSubtitleSidecar(String videoPath) async {
    await _deleteLocalSidecarSubtitleFiles(videoPath);
    await _downloadMatchingSubtitleSidecar(
      videoPath,
      window: const Duration(minutes: 4),
      forceRefresh: true,
    );
  }

  Future<void> _refreshCurrentMediaTitle() async {
    if (_wc == null) return;
    try {
      final raw = await _wc!.evaluateJavascript(source: r'''(function(){
        function pick(selectors){
          for (var i = 0; i < selectors.length; i++) {
            var el = document.querySelector(selectors[i]);
            var txt = (el && (el.textContent || el.innerText || '')) ? (el.textContent || el.innerText || '') : '';
            txt = txt.replace(/\s+/g, ' ').trim();
            if (txt && txt.length >= 2 && txt.length <= 180) return txt;
          }
          return '';
        }
        return JSON.stringify({
          mediaTitle: pick(['h1','.entry-title','.single-title','.movie-title','.watch-title','[class*=\"title\"] h1','[class*=\"single\"] h1']),
          pageTitle: (document.title || '').trim()
        });
      })();''');
      String? decoded;
      if (raw is String) {
        decoded = raw;
      } else if (raw != null) {
        decoded = raw.toString();
      }
      if (decoded != null && decoded.isNotEmpty) {
        try {
          final map = jsonDecode(decoded);
          final mediaTitle = _cleanMediaTitle((map['mediaTitle'] ?? '').toString());
          final pageTitle = _cleanMediaTitle((map['pageTitle'] ?? '').toString());
          if (mediaTitle.isNotEmpty) _currentMediaTitle = mediaTitle;
          if (pageTitle.isNotEmpty) _currentPageTitle = pageTitle;
          if (mounted) setState(() {});
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<Directory> _downloadsBaseDir() async {
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final dir = Directory('${ext.path}/Videos/LightOn');
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      }
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/Videos/LightOn');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _buildReferer(String downloadUrl) {
    try {
      final host = Uri.parse(downloadUrl).host.toLowerCase();
      if (host.contains('cdn-tube') || host.contains('server-hls') || host.contains('cdn-stream')) {
        return _currentHost != null ? 'https://$_currentHost/' : 'https://asd.pics/';
      }
      if (host.contains('1cloudfile')) return 'https://1cloudfile.com/';
      if (host.contains('vidtube')) return 'https://vidtube.one/';
      if (host.contains('10017.workers.dev') ||
          host.contains('workers.dev') ||
          host.contains('rainorbit') ||
          host.contains('nightbreeze') ||
          host.contains('quietlynx') ||
          host.contains('megafiles.store')) {
        if (_isvidfastSession) return 'https://vidfast.pro/';
        final pageRef = _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted;
        if (pageRef != null && pageRef.isNotEmpty) return pageRef;
        return 'https://player.videasy.net/';
      }
    } catch (_) {}
    if (_currentHost != null) return 'https://$_currentHost/';
    return 'https://asd.pics/';
  }

  String _buildOriginForUrl(String url, {String? refererOverride}) {
    final referer = (refererOverride ?? '').trim();
    try {
      if (referer.isNotEmpty) return Uri.parse(referer).origin;
    } catch (_) {}
    try {
      final host = Uri.parse(url).host.toLowerCase();
      if (host.contains('10017.workers.dev') ||
          host.contains('workers.dev') ||
          host.contains('rainorbit') ||
          host.contains('nightbreeze') ||
          host.contains('quietlynx') ||
          host.contains('megafiles.store')) {
        return 'https://player.videasy.net';
      }
      if (host.isNotEmpty) return Uri.parse(url).origin;
    } catch (_) {}
    if (_currentHost != null) return 'https://$_currentHost';
    return 'https://asd.pics';
  }

  Map<String, dynamic> _downloadHeaders(String url) {
    final referer = _buildReferer(url);
    return {
      'User-Agent': _ua,
      'Accept': '*/*',
      'Connection': 'keep-alive',
      'Referer': referer,
      'Origin': _buildOriginForUrl(url, refererOverride: referer),
    };
  }


  String _nativeEpisodeTag() {
    if (_resolvedNativeMediaType == MediaType.tv && widget.season != null && widget.episode != null) {
      return 'S${widget.season!.toString().padLeft(2, '0')}E${widget.episode!.toString().padLeft(2, '0')}';
    }
    return '';
  }


  MediaType get _resolvedNativeMediaType {
    final explicit = widget.mediaType;
    if (explicit != null) return explicit;
    if (widget.season != null || widget.episode != null) return MediaType.tv;
    return MediaType.movie;
  }

  String _nativeSubtitleReleaseContext() {
    final parts = <String>[];
    final title = _cleanMediaTitle(_currentMediaTitle ?? _currentPageTitle ?? widget.headerTitle ?? '');
    if (title.isNotEmpty) parts.add(title);
    final episodeTag = _nativeEpisodeTag();
    if (episodeTag.isNotEmpty) parts.add(episodeTag);
    final quality = _normalizeQualityLabel(_currentPageQualityLabel ?? '');
    if (quality.isNotEmpty) parts.add(quality);
    final server = (_currentServerLabel ?? widget.preferredSourceName ?? '').trim();
    if (server.isNotEmpty) parts.add(server);
    return parts.join(' ').trim();
  }

  String _nativeSubtitleProfileKey() {
    final parts = <String>[
      _resolvedNativeMediaType.name,
      (widget.tmdbId ?? 0).toString(),
    ];
    final episodeTag = _nativeEpisodeTag();
    if (episodeTag.isNotEmpty) parts.add(episodeTag.toLowerCase());
    final quality = _normalizeQualityLabel(_currentPageQualityLabel ?? '');
    if (quality.isNotEmpty) parts.add(quality.toLowerCase());
    final server = (_currentServerLabel ?? widget.preferredSourceName ?? '').trim().toLowerCase();
    if (server.isNotEmpty) {
      parts.add(server.replaceAll(RegExp(r'[^a-z0-9]+'), '_'));
    }
    return parts.join('|');
  }

  Map<String, dynamic> _nativeIdentityArgs() {
    return <String, dynamic>{
      if (widget.tmdbId != null) 'tmdbId': widget.tmdbId,
      'mediaType': _resolvedNativeMediaType.name,
      if (_resolvedNativeMediaType == MediaType.tv && widget.season != null) 'season': widget.season,
      if (_resolvedNativeMediaType == MediaType.tv && widget.episode != null) 'episode': widget.episode,
      'subtitleProfileKey': _nativeSubtitleProfileKey(),
      if ((widget.headerTitle ?? '').trim().isNotEmpty) 'headerTitle': widget.headerTitle,
    };
  }

  Map<String, String> _enrichNativeSubtitleTrack(
    Map<String, String> track, {
    required String resolvedUrl,
    bool markDefault = false,
  }) {
    final release = (track['release'] ?? '').trim().isNotEmpty
        ? (track['release'] ?? '').trim()
        : _nativeSubtitleReleaseContext();
    final item = <String, String>{
      'label': (track['label'] ?? '').ifEmpty('Subtitle'),
      'url': resolvedUrl,
      'language': (track['language'] ?? '').trim(),
      'source': (track['source'] ?? '').ifEmpty('Embedded'),
      if ((track['providerGroup'] ?? '').trim().isNotEmpty) 'providerGroup': (track['providerGroup'] ?? '').trim(),
      if (release.isNotEmpty) 'release': release,
      'subtitleProfileKey': _nativeSubtitleProfileKey(),
      if (widget.tmdbId != null) 'tmdbId': widget.tmdbId.toString(),
      'mediaType': _resolvedNativeMediaType.name,
      if (_resolvedNativeMediaType == MediaType.tv && widget.season != null) 'season': widget.season.toString(),
      if (_resolvedNativeMediaType == MediaType.tv && widget.episode != null) 'episode': widget.episode.toString(),
    };
    for (final key in const [
      'matchedRelease',
      'matchedFilter',
      'matchRank',
      'hearingImpaired',
      'hashMatched',
      'autoSelect',
      'default',
    ]) {
      final value = (track[key] ?? '').trim();
      if (value.isNotEmpty) item[key] = value;
    }
    final mime = _subtitleMimeFromName(resolvedUrl);
    if (mime.isNotEmpty) {
      item['mimeType'] = mime;
    } else if ((track['mimeType'] ?? '').trim().isNotEmpty) {
      item['mimeType'] = (track['mimeType'] ?? '').trim();
    }
    final itemLabel = (item['label'] ?? '').toLowerCase();
    final itemSource = (item['source'] ?? '').toLowerCase();
    final itemGroup = (item['providerGroup'] ?? '').toLowerCase();
    final isArabic2Backup = itemGroup == 'subdl' ||
        itemGroup == 'arabic2' ||
        itemSource.contains('subdl') ||
        itemSource.contains('عربي 2') ||
        itemLabel.contains('subdl') ||
        itemLabel.contains('عربي 2');

    if (!isArabic2Backup && WyziePrefetchService._isPrimarySubsourceTrackMap(item)) {
      item['providerGroup'] = 'subsource-api';
      item['source'] = 'عربي 1';
      final currentLabel = (item['label'] ?? '').trim();
      final compact = currentLabel
          .replaceFirst(RegExp(r'^عربي\s*1\s*[•\-:]\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^SubSource\s*API\s*[•\-:]\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^SubSource\s*[•\-:]\s*', caseSensitive: false), '')
          .trim();
      item['label'] = compact.isEmpty ? ((item['release'] ?? '').trim().isEmpty ? 'Subtitle' : (item['release'] ?? '').trim()) : compact;
    }

    if (isArabic2Backup) {
      item['providerGroup'] = 'arabic2';
      item['source'] = 'عربي 2';
      final currentLabel = (item['label'] ?? '').trim();
      final compact = currentLabel
          .replaceFirst(RegExp(r'^عربي\s*2\s*[•\-:]\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^SubDL\s*API\s*[•\-:]\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^SubDL\s*[•\-:]\s*', caseSensitive: false), '')
          .trim();
      item['label'] = compact.isEmpty ? ((item['release'] ?? '').trim().isEmpty ? 'Subtitle' : (item['release'] ?? '').trim()) : compact;
      item['autoSelect'] = 'false';
      item['default'] = 'false';
    } else {
      if (markDefault && (item['default'] ?? '').trim().isEmpty) {
        item['default'] = 'true';
      }
      if (markDefault && (item['autoSelect'] ?? '').trim().isEmpty) {
        item['autoSelect'] = 'true';
      }
    }
    return item;
  }

  bool _looksLikeVideasyProxyMediaUrl(String? url) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) return false;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    return host.contains('bold-cdn.') && host.contains('workers.dev') && uri.queryParameters.containsKey('q');
  }

  bool _isEphemeralVideasyMediaUrl(String? url) {
    return _looksLikeVideasyProxyMediaUrl(url);
  }

  bool _isVideasyPlayerUrl(String? url) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) return false;
    final host = Uri.tryParse(raw)?.host.toLowerCase() ?? '';
    return host == 'player.videasy.net' || host.endsWith('.videasy.net') || host.contains('videasy.net');
  }

  bool _isvidfastPlayerUrl(String? url) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) return false;
    final host = Uri.tryParse(raw)?.host.toLowerCase() ?? '';
    return host == 'vidfast.pro' || host == 'www.vidfast.pro' || host.endsWith('.vidfast.pro');
  }

  bool get _isvidfastSession {
    final sourceName = (widget.preferredSourceName ?? '').trim().toLowerCase();
    return sourceName == 'vidfast' ||
        _isvidfastPlayerUrl(widget.initialUrl) ||
        _isvidfastPlayerUrl(_currentPageUrl);
  }

  bool _isTsSegmentUrl(String? url) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) return false;
    final lower = raw.toLowerCase();
    if (lower.startsWith('blob:')) return false;
    if (lower.contains('.m3u8')) return false;
    return RegExp(r'\.ts(?:$|[?#])').hasMatch(lower);
  }

  bool _looksLikePlayableMediaUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final lower = url.toLowerCase();
    if (lower.startsWith('blob:')) return false;
    if (_isTsSegmentUrl(url)) return false;
    if (lower.endsWith('.mjs') ||
        lower.contains('.mjs?') ||
        lower.contains('.mjs#') ||
        lower.contains('.mjs/')) {
      return false;
    }
    final uri = Uri.tryParse(url);
    final host = (uri?.host ?? '').toLowerCase();
    if (_isvidfastSession &&
        (host.contains('vidfast.pro') ||
            host.contains('workers.dev') ||
            host.contains('megafiles.store')) &&
        (lower.contains('/download') ||
            lower.contains('/stream') ||
            lower.contains('/file/'))) {
      return true;
    }
    if (_looksLikeVideasyProxyMediaUrl(url)) return true;
    return lower.contains('.m3u8') || lower.contains('.mp4') ||
        lower.contains('.mkv') || lower.contains('.webm') ||
        lower.contains('.m4v') ||
        lower.contains('.mov') || lower.contains('.mpd') ||
        lower.contains('mime=video') || lower.contains('contenttype=video') ||
        lower.contains('/hls/') || lower.contains('/playlist') ||
        lower.contains('/manifest');
  }

  String? _inferMimeType(String? url, [String? hinted]) {
    final hint = hinted?.toLowerCase().trim();
    if (hint != null && hint.isNotEmpty) return hint;
    final raw = (url ?? '').trim();
    final lower = raw.toLowerCase();
    if (_looksLikeVideasyProxyMediaUrl(raw)) {
      final uri = Uri.tryParse(raw);
      final proxyType = (uri?.queryParameters['type'] ?? '').trim().toLowerCase();
      if (proxyType == 'hls') return 'application/x-mpegURL';
      if (proxyType == 'dash') return 'application/dash+xml';
      if (proxyType == 'mp4') return 'video/mp4';
      return 'application/x-mpegURL';
    }
    if (lower.contains('.m3u8')) return 'application/x-mpegURL';
    if (lower.contains('.mpd')) return 'application/dash+xml';
    if (lower.contains('.mp4') || lower.contains('.m4v')) return 'video/mp4';
    if (lower.contains('.webm')) return 'video/webm';
    if (lower.contains('.ts')) return 'video/mp2t';
    if (lower.contains('.mov')) return 'video/quicktime';
    return null;
  }


  bool _isStreamUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    if (_looksLikeVideasyProxyMediaUrl(url)) {
      final proxyType = (Uri.tryParse(url)?.queryParameters['type'] ?? '').trim().toLowerCase();
      return proxyType.isEmpty || proxyType == 'hls' || proxyType == 'dash';
    }
    final u = url.toLowerCase();
    return u.contains('.m3u8') ||
        u.contains('.mpd') ||
        u.contains('/manifest') ||
        u.contains('/playlist') ||
        u.contains('/hls/');
  }

  bool _isDirectMediaFile(String? url) {
    if (url == null || url.isEmpty) return false;
    if (_looksLikeVideasyProxyMediaUrl(url)) {
      final proxyType = (Uri.tryParse(url)?.queryParameters['type'] ?? '').trim().toLowerCase();
      return proxyType == 'mp4';
    }
    final u = url.toLowerCase().split('?').first;
    return u.endsWith('.mp4') ||
        u.endsWith('.mkv') ||
        u.endsWith('.webm') ||
        u.endsWith('.m4v') ||
        u.endsWith('.avi') ||
        u.endsWith('.mov');
  }

  String _mediaKindLabel(CapturedMediaItem item) {
    if (item.qualityLabel != null && item.qualityLabel!.isNotEmpty) {
      return item.qualityLabel!;
    }
    if (item.isDirectFile) return 'Direct';
    if (item.isStream) return 'HLS/DASH';
    return 'Media';
  }

  int _qualityRankLabel(String? label) {
    switch (_normalizeQualityLabel(label ?? '')) {
      case '2160p':
        return 2160;
      case '1440p':
        return 1440;
      case '1080p':
        return 1080;
      case '720p':
        return 720;
      case '540p':
        return 540;
      case '480p':
        return 480;
      case '360p':
        return 360;
      case '240p':
        return 240;
      default:
        return 0;
    }
  }

  String _appendQualitySuffixToFileName(String fileName, String? qualityLabel) {
    final label = _normalizeQualityLabel(qualityLabel ?? '');
    if (label.isEmpty) return _sanitizeFileName(fileName);
    final clean = _sanitizeFileName(fileName);
    final dot = clean.lastIndexOf('.');
    if (dot <= 0) return _sanitizeFileName('${clean}_$label');
    final base = clean.substring(0, dot);
    final ext = clean.substring(dot);
    if (base.endsWith('_$label')) return clean;
    return _sanitizeFileName('${base}_$label$ext');
  }

  List<PageQualityOption> get _sortedQualityOptions {
    final list = List<PageQualityOption>.from(_pageQualityOptions);
    list.sort((a, b) {
      final rank = _qualityRankLabel(b.label).compareTo(_qualityRankLabel(a.label));
      if (rank != 0) return rank;
      return a.label.compareTo(b.label);
    });
    return list;
  }

  PageQualityOption? _bestPreferredQualityOption() {
    final options = _sortedQualityOptions;
    if (options.isEmpty) return null;
    for (final wanted in const ['1080p', '720p', '480p']) {
      for (final opt in options) {
        if (_normalizeQualityLabel(opt.label) == wanted) return opt;
      }
    }
    return options.first;
  }

  PageQualityOption? _preferredDirectNativeQualityOption({String? preferredLabel, bool safeOnly = true}) {
    final options = _sortedQualityOptions
        .where((e) => _looksLikePlayableMediaUrl(e.url))
        .toList(growable: false);
    if (options.isEmpty) return null;

    final wanted = _normalizeQualityLabel(preferredLabel ?? _currentPageQualityLabel ?? '');
    if (wanted.isNotEmpty) {
      for (final opt in options) {
        if (_normalizeQualityLabel(opt.label) == wanted) return opt;
      }
    }

    if (safeOnly) {
      for (final wanted in const ['1080p', '720p', '480p', '360p', '240p']) {
        for (final opt in options) {
          if (_normalizeQualityLabel(opt.label) == wanted) return opt;
        }
      }
      for (final opt in options) {
        final rank = _qualityRankLabel(opt.label);
        if (rank > 0 && rank <= 1080) return opt;
      }
    }

    return options.first;
  }

  Future<String> _resolvePreferredNativeMediaUrl(
    String mediaUrl,
    Map<String, String> headers, {
    String? preferredLabel,
    bool updateCurrentLabel = true,
  }) async {
    var resolvedUrl = mediaUrl.trim();
    if (resolvedUrl.isEmpty) return resolvedUrl;

    if (_looksLikeHlsManifestUrl(resolvedUrl)) {
      resolvedUrl = await _prepareBestNativeMediaUrl(resolvedUrl, headers);
    }

    final preferred = _preferredDirectNativeQualityOption(preferredLabel: preferredLabel);
    final preferredUrl = (preferred?.url ?? '').trim();
    if (_looksLikePlayableMediaUrl(preferredUrl)) {
      if (updateCurrentLabel && preferred != null) {
        _currentPageQualityLabel = preferred.label;
      }
      return preferredUrl;
    }

    return resolvedUrl;
  }

  bool _isNativeDecoderCapabilityIssue(String? message) {
    final lower = (message ?? '').toLowerCase();
    if (lower.isEmpty) return false;
    return lower.contains('decoder') ||
        lower.contains('codec') ||
        lower.contains('capab') ||
        lower.contains('format exceeds') ||
        lower.contains('no_exceeds_capabilities') ||
        lower.contains('video renderer');
  }

  PageQualityOption? _nextLowerNativeQualityFallback([String? failedUrl]) {
    final options = _sortedQualityOptions
        .where((e) => _looksLikePlayableMediaUrl(e.url))
        .toList(growable: false);
    if (options.isEmpty) return null;

    final blockedUrl = (failedUrl ?? _lastNativePlayerUrl ?? '').trim().toLowerCase();
    final currentRank = _qualityRankLabel(_currentPageQualityLabel ?? '');

    for (final opt in options) {
      final url = (opt.url ?? '').trim();
      if (url.isEmpty) continue;
      if (url.toLowerCase() == blockedUrl) continue;
      if (_nativeDecoderFallbackTriedUrls.contains(url.toLowerCase())) continue;
      final rank = _qualityRankLabel(opt.label);
      if (currentRank > 0) {
        if (rank > 0 && rank < currentRank) return opt;
      } else if (rank > 0 && rank <= 1080) {
        return opt;
      }
    }

    for (final opt in options) {
      final url = (opt.url ?? '').trim();
      if (url.isEmpty) continue;
      if (url.toLowerCase() == blockedUrl) continue;
      if (_nativeDecoderFallbackTriedUrls.contains(url.toLowerCase())) continue;
      return opt;
    }

    return null;
  }

  Future<bool> _handleNativeDecoderFallback(String? message) async {
    if (!_isNativeDecoderCapabilityIssue(message)) return false;
    if (_nativeDecoderFallbackBusy) return false;

    final failedUrl = (_lastNativePlayerUrl ?? _capturedVideoUrl ?? '').trim();
    final fallback = _nextLowerNativeQualityFallback(failedUrl);
    final fallbackUrl = (fallback?.url ?? '').trim();
    if (fallback == null || !_looksLikePlayableMediaUrl(fallbackUrl)) {
      return false;
    }

    _nativeDecoderFallbackBusy = true;
    final seekSeconds = await _getCurrentPosition();
    _nativeDecoderFallbackTriedUrls.add(fallbackUrl.toLowerCase());

    if (mounted) {
      setState(() => _currentPageQualityLabel = fallback.label);
    } else {
      _currentPageQualityLabel = fallback.label;
    }

    _showSnack('⚠️ تم خفض الجودة تلقائيًا إلى ${fallback.label}');

    try {
      await _openNativePlayer(
        force: true,
        replace: true,
        startTimeOverride: seekSeconds,
        forcedUrl: fallbackUrl,
        forcedPageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted,
        forcedMimeType: _inferMimeType(fallbackUrl),
      );
      return true;
    } finally {
      _nativeDecoderFallbackBusy = false;
    }
  }

  bool _sameWatchPage(String? a, [String? b]) {
    final first = (a ?? '').trim();
    final second = (b ?? _currentPageUrl ?? _capturedVideoPageUrl ?? '').trim();
    if (first.isEmpty || second.isEmpty) return false;
    final ua = Uri.tryParse(first);
    final ub = Uri.tryParse(second);
    if (ua == null || ub == null) return first == second;
    return ua.host.toLowerCase() == ub.host.toLowerCase() && ua.path == ub.path;
  }

  CapturedMediaItem? _bestQuickMediaForQuality([String? qualityLabel]) {
    final wanted = _normalizeQualityLabel(qualityLabel ?? '');
    final pool = _capturedMedia.where((item) {
      if (!_sameWatchPage(item.pageUrl)) return false;
      if (wanted.isEmpty) return true;
      return _normalizeQualityLabel(item.qualityLabel ?? '') == wanted;
    }).toList();
    if (pool.isEmpty) return null;
    pool.sort((a, b) {
      if (a.isDirectFile != b.isDirectFile) {
        return b.isDirectFile ? 1 : -1;
      }
      final rank = _qualityRankLabel(b.qualityLabel).compareTo(_qualityRankLabel(a.qualityLabel));
      if (rank != 0) return rank;
      return b.foundAt.compareTo(a.foundAt);
    });
    return pool.first;
  }

  void _addCapturedMedia(
    String url, {
    String? pageUrl,
    String? mimeType,
    String? qualityLabel,
    Map<String, String>? headers,
  }) {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;
    if (_isYouTubeUrl(cleanUrl)) return;
    if (!_looksLikePlayableMediaUrl(cleanUrl)) return;

    final resolvedPageUrl = (pageUrl != null && pageUrl.isNotEmpty)
        ? pageUrl
        : (_lastTrusted ?? 'https://asd.pics/');
    final normalizedQuality = _normalizeQualityLabel(
      qualityLabel ?? _pendingDownloadQualityLabel ?? _hiddenHarvestCurrentQuality ?? _currentPageQualityLabel ?? '',
    );

    final key = '${cleanUrl.toLowerCase()}|${resolvedPageUrl.toLowerCase()}|${normalizedQuality.toLowerCase()}';
    if (_capturedMediaSeen.contains(key)) return;
    _capturedMediaSeen.add(key);

    final mime = _inferMimeType(cleanUrl, mimeType);
    final item = CapturedMediaItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      url: cleanUrl,
      pageUrl: resolvedPageUrl,
      fileName: _contextualFileName(cleanUrl, qualityLabel: normalizedQuality),
      foundAt: DateTime.now(),
      isDirectFile: _isDirectMediaFile(cleanUrl),
      isStream: _isStreamUrl(cleanUrl),
      mimeType: mime,
      qualityLabel: normalizedQuality.isEmpty ? null : normalizedQuality,
      headers: headers,
    );

    _capturedMedia.insert(0, item);

    if (item.qualityLabel != null && item.qualityLabel!.isNotEmpty) {
      _harvestedQualityLabels.add(item.qualityLabel!);
    }

    if (_capturedMedia.length > 150) {
      final removed = _capturedMedia.removeLast();
      _capturedMediaSeen.remove(
        '${removed.url.toLowerCase()}|${removed.pageUrl.toLowerCase()}|${_normalizeQualityLabel(removed.qualityLabel ?? '').toLowerCase()}',
      );
    }

    _lastDetectedMediaUrl = cleanUrl;
    _lastDetectedMediaType = mime;

    if (mounted) setState(() {});
  }

  bool _isYouTubeUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final u = url.toLowerCase();
    return u.contains('youtube.com') ||
        u.contains('youtu.be') ||
        u.contains('googlevideo.com') ||
        u.contains('youtube-nocookie.com') ||
        u.contains('ytimg.com');
  }

  bool _isAdResourceUrl(String url) {
    final u = url.toLowerCase();
    if (_isB(url)) return true;
    final adHostHints = <String>[
      'doubleclick.net', 'googlesyndication.com', 'pagead2',
      'googletagmanager.com', 'adnxs.com', 'adnxs',
      'adservice.google.', 'pubmatic.com', 'rubiconproject.com',
      'criteo.com', 'taboola.com', 'outbrain.com', 'revcontent.com',
      'mgid.com', 'propellerads', 'exoclick', 'imasdk',
      'imasdk.googleapis.com', 'gstatic.com/pagead',
      'pagead2.googlesyndication.com',
      'google-analytics.com', 'googleads.', 'e7cod.com',
    ];
    if (widget.launchHidden || widget.downloadOnlyMode) {
      adHostHints.addAll(const [
        'static.cloudflareinsights.com',
        'cloudflareinsights.com',
        'cdn.lordicon.com',
        'lordicon.com',
        'site-assets.fontawesome.com',
        'fonts.googleapis.com',
        'fonts.gstatic.com',
      ]);
    }
    const adPathHints = <String>[
      '/ads/', '/ad/', '/gpt/', 'ad_unit', 'adunit',
      'interstitial', 'rewarded', 'adsbygoogle', '/async/ads',
      '/pagead', 'gpt-ad',
    ];
    return adHostHints.any((h) => u.contains(h)) ||
        adPathHints.any((h) => u.contains(h));
  }


  bool _looksLikeMasterManifestCaptureUrl(String? url) {
    final u = (url ?? '').trim().toLowerCase();
    if (!u.contains('.m3u8')) return false;
    return u.contains('playlist.m3u8') ||
        u.contains('master.m3u8') ||
        u.contains('cgxhewxpc3qubtn1oa==') ||
        u.contains('bwfzdgvylm0zuoa==');
  }

  bool _looksLikeVariantManifestCaptureUrl(String? url) {
    final u = (url ?? '').trim().toLowerCase();
    if (!u.contains('.m3u8')) return false;
    return u.contains('index.m3u8') ||
        u.contains('aw5kzxgubtn1oa==') ||
        RegExp(r'/(2160|1440|1080|720|540|480|360|240)(p)?/').hasMatch(u) ||
        RegExp(r'/(mje2ma==|mtq0ma==|mta4ma==|nziw|ntqw|ndgw|mzyw|mjqw)/').hasMatch(u);
  }

  void _rememberCapturedRequestHeaders(String? url, Map<String, String>? headers) {
    final target = (url ?? '').trim();
    if (target.isEmpty || headers == null || headers.isEmpty) return;
    final cleaned = <String, String>{};
    headers.forEach((k, v) {
      final key = k.toString().trim();
      final value = v.toString().trim();
      if (key.isEmpty || value.isEmpty) return;
      final lower = key.toLowerCase();
      if (lower == 'content-length' || lower == 'host') return;
      cleaned[key] = value;
    });
    if (cleaned.isEmpty) return;
    _capturedRequestHeadersByUrl[target] = cleaned;
    _latestPlayableRequestHeaders = Map<String, String>.from(cleaned);
    _latestPlayableRequestUrl = target;
  }

  Map<String, String> _bestCapturedHeadersForUrl(String url) {
    final exact = _capturedRequestHeadersByUrl[url];
    if (exact != null && exact.isNotEmpty) {
      return Map<String, String>.from(exact);
    }

    final targetHost = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (targetHost.isNotEmpty) {
      final entries = _capturedRequestHeadersByUrl.entries.toList().reversed;
      for (final entry in entries) {
        final host = Uri.tryParse(entry.key)?.host.toLowerCase() ?? '';
        if (host == targetHost && entry.value.isNotEmpty) {
          return Map<String, String>.from(entry.value);
        }
      }
    }

    if (_latestPlayableRequestHeaders.isNotEmpty) {
      return Map<String, String>.from(_latestPlayableRequestHeaders);
    }
    return <String, String>{};
  }

  void _capturePlayableUrl(
    String? rawUrl, {
    String? pageUrl,
    double? currentTime,
    String? mimeType,
    String? qualityLabel,
  }) {
    final url = rawUrl?.trim();
    if (_isTsSegmentUrl(url)) return;
    if (!_looksLikePlayableMediaUrl(url)) return;
    if (_isYouTubeUrl(url)) return;

    final normalizedQuality = _normalizeQualityLabel(
      qualityLabel ?? _pendingDownloadQualityLabel ?? _hiddenHarvestCurrentQuality ?? _currentPageQualityLabel ?? '',
    );
    final isTransientVideasy = _isEphemeralVideasyMediaUrl(url);

    _addCapturedMedia(
      url!,
      pageUrl: pageUrl,
      mimeType: mimeType,
      qualityLabel: normalizedQuality,
      headers: {
        'User-Agent': _ua,
        'Referer': pageUrl ?? (_lastTrusted ?? 'https://asd.pics/'),
      },
    );

    _tryFastAttachFromCapturedPlayable(
      url,
      pageUrl: pageUrl,
      mimeType: mimeType,
      currentTime: currentTime,
    );

    final isHls = url.toLowerCase().contains('.m3u8');
    final current = _capturedVideoUrl?.toLowerCase() ?? '';
    final currentIsHls = current.contains('.m3u8');
    final currentRank = _qualityRankLabel(_currentPageQualityLabel);
    final newRank = _qualityRankLabel(normalizedQuality);
    final currentIsMaster = _looksLikeMasterManifestCaptureUrl(_capturedVideoUrl);
    final newIsMaster = _looksLikeMasterManifestCaptureUrl(url);
    final currentIsVariant = _looksLikeVariantManifestCaptureUrl(_capturedVideoUrl);
    final newIsVariant = _looksLikeVariantManifestCaptureUrl(url);

    final shouldReplaceCaptured = _capturedVideoUrl == null ||
        (_capturedVideoUrl?.startsWith('blob:') ?? false) ||
        (newIsMaster && !currentIsMaster) ||
        (isHls && !currentIsHls && !currentIsMaster) ||
        (!newIsVariant && currentIsVariant) ||
        newRank > currentRank;

    if (shouldReplaceCaptured) {
      _capturedVideoUrl = url;
      if (normalizedQuality.isNotEmpty && !newIsMaster) {
        _currentPageQualityLabel = normalizedQuality;
      }
    }

    _capturedVideoMimeType = _inferMimeType(url, mimeType);
    if (pageUrl != null && pageUrl.isNotEmpty) _capturedVideoPageUrl = pageUrl;
    if (currentTime != null && currentTime >= 0) _capturedVideoTime = currentTime;
    if (mounted && !_videoDetected) setState(() => _videoDetected = true);

    if (isTransientVideasy && !_pendingNativeOpenOnPlayableCapture) {
      return;
    }

    if (widget.downloadOnlyMode) {
      if (_looksLikeHlsManifestUrl(url)) {
        Future.microtask(() async {
          try {
            final headers = await _buildPipHeaders(
              url,
              pageUrl: pageUrl ?? _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted,
            );
            await _prepareBestNativeMediaUrl(url, headers);
          } catch (_) {}
        });
      }
      if (!_downloadSelectionCommitted) {
        _scheduleInitialDownloadChoicesPrompt();
      }
      return;
    }

    if (widget.autoDownloadPrompt && !_qualityDownloadSwitchPending) {
      if (_downloadSelectionCommitted) return;
      if (_autoDownloadPromptShown || _downloadQualitySheetShown) {
        return;
      }
      Future.microtask(() async {
        if (!mounted) return;
        await _ensureDownloadQualityChoicesReady();
        _autoDownloadPromptShown = true;
        await _downloadBestCapturedMedia();
      });
    }
  }

  void _tryFastAttachFromCapturedPlayable(
    String mediaUrl, {
    String? pageUrl,
    String? mimeType,
    double? currentTime,
  }) {
    if (_captureEngineSuspended || _preventAutoReopenAfterNativeClose) return;

    final cleanUrl = mediaUrl.trim();
    if (cleanUrl.isEmpty || cleanUrl.startsWith('blob:')) return;
    if (_isTsSegmentUrl(cleanUrl)) return;
    if (_isEphemeralVideasyMediaUrl(cleanUrl) && !_pendingNativeOpenOnPlayableCapture) return;
    if (!_looksLikePlayableMediaUrl(cleanUrl) || _isYouTubeUrl(cleanUrl)) return;

    final resolvedPageUrl = pageUrl?.trim().isNotEmpty == true
        ? pageUrl!.trim()
        : (_capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted);
    final resolvedMimeType = (mimeType ?? '').trim().isNotEmpty
        ? mimeType!.trim()
        : _inferMimeType(cleanUrl);

    if (widget.autoDownloadPrompt && !_qualityDownloadSwitchPending) {
      if (_downloadSelectionCommitted) return;
      if (_autoDownloadPromptShown || _downloadQualitySheetShown) {
        return;
      }
      debugPrint('[Download] fast request capture: تم منع الفتح التلقائي للمشغل $cleanUrl');
      _autoDownloadPromptShown = true;
      Future.microtask(() async {
        if (!mounted) return;
        await _pauseOriginalSitePlayer();
        await _ensureDownloadQualityChoicesReady();
        await _downloadBestCapturedMedia();
      });
      return;
    }

    if (_nativePlayerShellOnly) {
      debugPrint('[Player] fast request capture: shell نشط، ربط $cleanUrl');
      Future.microtask(() => _attachSourceToNativePlayer(
            mediaUrl: cleanUrl,
            pageUrl: resolvedPageUrl,
            mimeType: resolvedMimeType,
            startTimeOverride: currentTime,
          ));
      return;
    }

    if ((_nativePlayerShellRequested || _pendingNativeOpenOnPlayableCapture) &&
        !_nativePlayerActive &&
        !_nativePlayerOpening) {
      debugPrint('[Player] fast request capture: فتح مباشر $cleanUrl');
      Future.microtask(() => _openNativePlayer(
            force: true,
            replace: true,
            startTimeOverride: currentTime ?? _pendingNativeStartTime,
            forcedUrl: cleanUrl,
            forcedPageUrl: resolvedPageUrl,
            forcedMimeType: resolvedMimeType,
          ));
    }
  }

  Map<String, String> _extractEmbeddedMediaHeaders(String mediaUrl) {
    final out = <String, String>{};
    try {
      final uri = Uri.parse(mediaUrl);
      final raw = uri.queryParameters['headers'];
      if (raw == null || raw.isEmpty) return out;
      final decoded = Uri.decodeComponent(raw);
      final dynamic parsed = jsonDecode(decoded);
      if (parsed is Map) {
        parsed.forEach((key, value) {
          final k = key.toString().trim();
          final v = value?.toString().trim() ?? '';
          if (k.isNotEmpty && v.isNotEmpty) {
            switch (k.toLowerCase()) {
              case 'referer':
                out['Referer'] = v;
                break;
              case 'origin':
                out['Origin'] = v;
                break;
              case 'user-agent':
                out['User-Agent'] = v;
                break;
              case 'cookie':
                out['Cookie'] = v;
                break;
              default:
                out[k] = v;
            }
          }
        });
      }
    } catch (_) {}
    return out;
  }


  bool _looksLikeHlsManifestUrl(String? url) {
    final value = (url ?? '').toLowerCase();
    return value.contains('.m3u8');
  }

  String? _tryDecodePathToken(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    if (value.toLowerCase().endsWith('.m3u8')) {
      value = value.substring(0, value.length - 5);
    }
    try {
      final normalized = base64.normalize(value.replaceAll('-', '+').replaceAll('_', '/'));
      final decoded = utf8.decode(base64.decode(normalized), allowMalformed: true).trim();
      return decoded.isEmpty ? null : decoded;
    } catch (_) {
      return null;
    }
  }

  List<String> _buildHlsManifestCandidates(String mediaUrl) {
    final canonicalMediaUrl = _canonicalizevidfastWorkersUrl(mediaUrl);
    final uri = Uri.tryParse(canonicalMediaUrl);
    if (uri == null || uri.pathSegments.isEmpty) return <String>[canonicalMediaUrl];

    final names = <String>['master.m3u8', 'playlist.m3u8', 'manifest.m3u8', 'index.m3u8', 'main.m3u8'];
    final candidates = <String>[];
    final seen = <String>{};

    void addUrl(String value) {
      final normalized = _canonicalizevidfastWorkersUrl(value);
      if (seen.add(normalized)) candidates.add(normalized);
    }

    void addFrom(List<String> baseSegments, String fileName, {bool encode = false}) {
      var segment = fileName;
      if (encode) {
        segment = '${base64.encode(utf8.encode(fileName))}.m3u8';
      }
      addUrl(uri.replace(pathSegments: [...baseSegments, segment]).toString());
    }

    final segs = List<String>.from(uri.pathSegments);
    addUrl(canonicalMediaUrl);

    for (final depth in <int>[1, 2]) {
      if (segs.length <= depth) continue;
      final base = segs.sublist(0, segs.length - depth);
      for (final name in names) {
        addFrom(base, name, encode: true);
        addFrom(base, name, encode: false);
      }
    }

    return candidates;
  }

  int _workersHostScore(String host) {
    final lower = host.toLowerCase();
    if (!lower.contains('workers.dev')) return -1000;
    if (lower.startsWith('wrong.')) return -100;
    if (lower.startsWith('hockey.10017.workers.dev')) return 40;
    if (lower.startsWith('begin.10017.workers.dev')) return 35;
    if (lower.startsWith('label.10017.workers.dev')) return 30;
    if (lower == '10017.workers.dev') return 20;
    return 10;
  }

  String? _bestWorkersHostFromCurrentContext([String? fallbackUrl]) {
    if (!_isvidfastSession) return null;
    final hostScores = <String, int>{};

    void collectUrl(String? value, {bool samePageOnly = true}) {
      final raw = (value ?? '').trim();
      if (raw.isEmpty) return;
      final uri = Uri.tryParse(raw);
      final host = (uri?.host ?? '').toLowerCase();
      if (!host.contains('workers.dev')) return;
      if (samePageOnly && !_sameWatchPage(uri.toString())) return;
      final score = _workersHostScore(host);
      final current = hostScores[host] ?? -1000;
      if (score > current) hostScores[host] = score;
    }

    collectUrl(fallbackUrl, samePageOnly: false);
    collectUrl(_capturedVideoUrl, samePageOnly: false);
    for (final item in _capturedMedia) {
      if (!_sameWatchPage(item.pageUrl)) continue;
      collectUrl(item.url, samePageOnly: false);
    }
    for (final option in _pageServerOptions) {
      collectUrl(option.embedUrl, samePageOnly: false);
    }

    if (hostScores.isEmpty) return null;
    final sorted = hostScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  String _canonicalizevidfastWorkersUrl(String rawUrl, {String? preferredHost}) {
    final raw = rawUrl.trim();
    if (raw.isEmpty) return rawUrl;
    final uri = Uri.tryParse(raw);
    if (uri == null) return rawUrl;
    final host = uri.host.toLowerCase();
    if (!_isvidfastSession || !host.contains('workers.dev')) return rawUrl;
    final preferred = (preferredHost ?? _bestWorkersHostFromCurrentContext(raw)).toString().trim().toLowerCase();
    if (preferred.isEmpty || preferred == host) return rawUrl;
    final currentScore = _workersHostScore(host);
    final preferredScore = _workersHostScore(preferred);
    final shouldReplace = host.startsWith('wrong.') || preferredScore > currentScore;
    if (!shouldReplace) return rawUrl;
    return uri.replace(host: preferred).toString();
  }

  List<String> _buildWorkersUrlCandidates(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return const <String>[];
    final uri = Uri.tryParse(raw);
    if (uri == null) return <String>[raw];
    final host = uri.host.toLowerCase();
    if (!_isvidfastSession || !host.contains('workers.dev')) {
      return <String>[_canonicalizevidfastWorkersUrl(raw)];
    }
    final seen = <String>{};
    final out = <String>[];

    void addHost(String? candidateHost) {
      final normalizedHost = (candidateHost ?? '').trim().toLowerCase();
      if (normalizedHost.isEmpty) return;
      final candidate = uri.replace(host: normalizedHost).toString();
      final normalizedCandidate = _canonicalizevidfastWorkersUrl(candidate, preferredHost: normalizedHost);
      if (seen.add(normalizedCandidate)) out.add(normalizedCandidate);
    }

    addHost(_bestWorkersHostFromCurrentContext(raw));
    addHost(host);
    if (host.endsWith('10017.workers.dev')) {
      for (final candidate in const <String>[
        'hockey.10017.workers.dev',
        'begin.10017.workers.dev',
        'label.10017.workers.dev',
        '10017.workers.dev',
      ]) {
        addHost(candidate);
      }
    }
    return out.isEmpty ? <String>[raw] : out;
  }

  bool _playlistLooksLikeMaster(String body) {
    final text = body.toUpperCase();
    return text.contains('#EXT-X-STREAM-INF') ||
        text.contains('#EXT-X-MEDIA:TYPE=SUBTITLES') ||
        text.contains('#EXT-X-I-FRAME-STREAM-INF');
  }

  bool _looksLikePlaylistBody(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('#EXTM3U')) return true;
    final upper = trimmed.toUpperCase();
    return upper.contains('#EXTINF') ||
        upper.contains('#EXT-X-TARGETDURATION') ||
        upper.contains('#EXT-X-STREAM-INF') ||
        upper.contains('#EXT-X-MAP');
  }

  Future<String?> _fetchPlaylistBody(String url, Map<String, String> headers) async {
    final requestHeaders = Map<String, String>.from(headers)
      ..putIfAbsent('Accept', () => 'application/vnd.apple.mpegurl, application/x-mpegURL, text/plain, */*');
    for (final candidate in _buildWorkersUrlCandidates(url)) {
      try {
        final response = await _dio.get<String>(
          candidate,
          options: Options(
            headers: requestHeaders,
            responseType: ResponseType.plain,
            validateStatus: (status) => status != null && status >= 200 && status < 400,
            receiveTimeout: const Duration(seconds: 12),
          ),
        );
        final body = response.data?.toString();
        if (body == null || body.trim().isEmpty) continue;
        if (_looksLikePlaylistBody(body)) return body;
      } catch (_) {}
    }
    return null;
  }

  Future<List<int>?> _fetchBinaryWithWorkerFallback(
    String url,
    Map<String, String> headers, {
    CancelToken? cancelToken,
  }) async {
    for (final candidate in _buildWorkersUrlCandidates(url)) {
      try {
        final response = await _dio.get<List<int>>(
          candidate,
          cancelToken: cancelToken,
          options: Options(
            headers: headers,
            responseType: ResponseType.bytes,
            followRedirects: true,
            receiveTimeout: const Duration(minutes: 10),
            validateStatus: (status) => status != null && status >= 200 && status < 400,
          ),
        );
        final data = response.data;
        if (data != null && data.isNotEmpty) return data;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
      } catch (_) {}
    }
    return null;
  }

  String _resolvePlaylistUrl(String baseUrl, String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) return value;
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return _canonicalizevidfastWorkersUrl(uri.toString());
    final base = Uri.tryParse(baseUrl);
    if (base == null) return value;
    return _canonicalizevidfastWorkersUrl(base.resolve(value).toString());
  }

  Map<String, String> _parseM3uAttributes(String line) {
    final out = <String, String>{};
    final idx = line.indexOf(':');
    final raw = idx >= 0 ? line.substring(idx + 1) : line;
    final regex = RegExp(r'([A-Z0-9-]+)=((?:"[^"]*")|[^,]*)');
    for (final m in regex.allMatches(raw)) {
      final key = (m.group(1) ?? '').trim();
      var value = (m.group(2) ?? '').trim();
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = value.substring(1, value.length - 1);
      }
      if (key.isNotEmpty) out[key] = value;
    }
    return out;
  }

  Future<String> _materializeSubtitleUrlForNative(String rawUrl, Map<String, String> headers) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return url;
    final cached = _materializedSubtitleUrlCache[url];
    if (cached != null && cached.trim().isNotEmpty) return cached;
    if (!url.toLowerCase().contains('.m3u8')) {
      _materializedSubtitleUrlCache[url] = url;
      return url;
    }
    final body = await _fetchPlaylistBody(url, headers);
    if (body == null || body.trim().isEmpty) {
      _materializedSubtitleUrlCache[url] = url;
      return url;
    }
    for (final rawLine in body.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final resolved = _resolvePlaylistUrl(url, line);
      _materializedSubtitleUrlCache[url] = resolved;
      return resolved;
    }
    _materializedSubtitleUrlCache[url] = url;
    return url;
  }

  int _subtitlePreferenceScore(Map<String, String> track) {
    final label = (track['label'] ?? '').toLowerCase();
    final language = (track['language'] ?? '').toLowerCase();
    final source = (track['source'] ?? '').toLowerCase();
    final group = (track['providerGroup'] ?? '').toLowerCase();
    final matchRank = int.tryParse((track['matchRank'] ?? '').trim());
    final rank = (matchRank ?? 0).clamp(0, 9999);

    final isArabic2Backup = group == 'subdl' ||
        group == 'arabic2' ||
        source.contains('subdl') ||
        source.contains('عربي 2') ||
        label.contains('subdl') ||
        label.contains('عربي 2');
    if (group.startsWith('subsource') || source.contains('subsource') || source.contains('عربي 1') || label.contains('عربي 1')) return -3000 + rank;
    if ((track['matchedRelease'] ?? '').trim().isNotEmpty) return -1800 + rank;
    if ((track['matchedFilter'] ?? '').trim().isNotEmpty) return -1200 + rank;
    if (isArabic2Backup) return 5000 + rank;
    if (language.startsWith('ar') || label.contains('arab') || label.contains('عرب')) return rank;
    if (language.startsWith('en') || label.contains('english')) return 2000 + rank;
    return 3000 + rank;
  }

  Future<List<Map<String, String>>> _buildNativeSubtitleTracks(Map<String, String> headers) async {
    if (_externalSubtitleTracks.isEmpty) return const <Map<String, String>>[];
    var sortedTracks = List<Map<String, String>>.from(_removeRawArchiveSubtitleTracks(_externalSubtitleTracks))
      ..sort((a, b) => _subtitlePreferenceScore(a).compareTo(_subtitlePreferenceScore(b)));
    final out = <Map<String, String>>[];
    for (final track in sortedTracks) {
      final rawUrl = (track['url'] ?? '').trim();
      if (rawUrl.isEmpty) continue;
      final resolved = await _materializeSubtitleUrlForNative(rawUrl, headers);
      final resolvedMime = (track['mimeType'] ?? '').trim().ifEmpty(_subtitleMimeFromName(resolved));
      if (resolvedMime.toLowerCase().contains('zip') || resolvedMime.toLowerCase().contains('rar') || resolvedMime.toLowerCase().contains('7z')) {
        continue;
      }
      out.add(_enrichNativeSubtitleTrack(
        track,
        resolvedUrl: resolved,
        markDefault: out.isEmpty,
      ));
    }
    final merged = _mergeSubtitleTrackMaps(out);
    if (merged.isNotEmpty) {
      for (final item in merged) {
        item['default'] = 'false';
        item['autoSelect'] = 'false';
      }
      final primaryIndex = merged.indexWhere((item) => WyziePrefetchService._isPrimarySubsourceTrackMap(item));
      if (primaryIndex >= 0) {
        merged[primaryIndex]['default'] = 'true';
        merged[primaryIndex]['autoSelect'] = 'true';
      }
    }
    return merged;
  }

  List<Map<String, String>> _buildFastNativeSubtitleTracks() {
    if (_externalSubtitleTracks.isEmpty) return const <Map<String, String>>[];
    var sortedTracks = List<Map<String, String>>.from(_externalSubtitleTracks)
      ..sort((a, b) => _subtitlePreferenceScore(a).compareTo(_subtitlePreferenceScore(b)));
    final out = <Map<String, String>>[];
    for (final track in sortedTracks) {
      final rawUrl = (track['url'] ?? '').trim();
      if (rawUrl.isEmpty) continue;
      final fastMime = (track['mimeType'] ?? '').trim().ifEmpty(_subtitleMimeFromName(rawUrl));
      if (fastMime.toLowerCase().contains('zip') || fastMime.toLowerCase().contains('rar') || fastMime.toLowerCase().contains('7z')) {
        continue;
      }
      out.add(_enrichNativeSubtitleTrack(
        track,
        resolvedUrl: rawUrl,
        markDefault: out.isEmpty,
      ));
    }
    final merged = _mergeSubtitleTrackMaps(out);
    if (merged.isNotEmpty) {
      for (final item in merged) {
        item['default'] = 'false';
        item['autoSelect'] = 'false';
      }
      final primaryIndex = merged.indexWhere((item) => WyziePrefetchService._isPrimarySubsourceTrackMap(item));
      if (primaryIndex >= 0) {
        merged[primaryIndex]['default'] = 'true';
        merged[primaryIndex]['autoSelect'] = 'true';
      }
    }
    return merged;
  }

  bool _canUseFastNativeSubtitleTracks() {
    if (_externalSubtitleTracks.isEmpty) return true;
    for (final track in _externalSubtitleTracks) {
      final rawUrl = (track['url'] ?? '').trim().toLowerCase();
      if (rawUrl.isEmpty) continue;
      if (rawUrl.contains('.m3u8')) return false;
      final knownMime = (track['mimeType'] ?? '').trim();
      final inferredMime = _subtitleMimeFromName(rawUrl);
      final effectiveMime = knownMime.ifEmpty(inferredMime).toLowerCase();
      if (effectiveMime.contains('zip') || effectiveMime.contains('rar') || effectiveMime.contains('7z')) return false;
      if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
        if (knownMime.isEmpty && inferredMime.isEmpty) return false;
      }
    }
    return true;
  }

  void _applyOptionsFromHlsMaster(String masterUrl, String body) {
    final lines = body.split(RegExp(r'\r?\n'));
    final qualityOptions = <PageQualityOption>[];
    final subtitleTracks = <Map<String, String>>[];
    final seenQualities = <String>{};
    final seenSubtitleUrls = <String>{};

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXT-X-MEDIA:') && line.toUpperCase().contains('TYPE=SUBTITLES')) {
        final attrs = _parseM3uAttributes(line);
        final uri = attrs['URI'];
        if (uri == null || uri.trim().isEmpty) continue;
        final resolved = _resolvePlaylistUrl(masterUrl, uri);
        if (!seenSubtitleUrls.add(resolved.toLowerCase())) continue;
        final mime = _subtitleMimeFromName(resolved);
        subtitleTracks.add({
          'label': (attrs['NAME']?.trim().isNotEmpty == true) ? attrs['NAME']!.trim() : 'Subtitle',
          'url': resolved,
          'language': attrs['LANGUAGE']?.trim() ?? '',
          'source': 'Same server',
          if (mime.isNotEmpty) 'mimeType': mime,
        });
      }
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
      final attrs = _parseM3uAttributes(line);
      String? nextUrl;
      for (var j = i + 1; j < lines.length; j++) {
        final candidate = lines[j].trim();
        if (candidate.isEmpty) continue;
        if (!candidate.startsWith('#')) {
          nextUrl = candidate;
          break;
        }
      }
      if (nextUrl == null || nextUrl.trim().isEmpty) continue;
      final resolved = _resolvePlaylistUrl(masterUrl, nextUrl);
      final resolution = attrs['RESOLUTION'] ?? '';
      final heightMatch = RegExp(r'\d+x(\d+)', caseSensitive: false).firstMatch(resolution);
      final label = heightMatch != null
          ? '${heightMatch.group(1)}p'
          : ((attrs['NAME']?.trim().isNotEmpty == true) ? attrs['NAME']!.trim() : 'Auto');
      final dedupe = '${label.toLowerCase()}|${resolved.toLowerCase()}';
      if (!seenQualities.add(dedupe)) continue;
      qualityOptions.add(PageQualityOption(
        label: label,
        key: 'hls_${label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_${qualityOptions.length}',
        url: resolved,
        selected: qualityOptions.isEmpty,
      ));
    }

    if (qualityOptions.isNotEmpty) {
      qualityOptions.sort((a, b) => _qualityRankLabel(b.label).compareTo(_qualityRankLabel(a.label)));
      final hadExplicitQuality = (_currentPageQualityLabel ?? '').trim().isNotEmpty;
      _updatePageQualityOptions(qualityOptions, hadExplicitQuality ? _currentPageQualityLabel : '');
      if (!hadExplicitQuality) {
        _currentPageQualityLabel = null;
      }
    }

    if (subtitleTracks.isNotEmpty) {
      _externalSubtitleTracks = _mergeSubtitleTrackMaps([
        ..._externalSubtitleTracks,
        ...subtitleTracks,
      ]);
    }

    if (_pendingNativeOpenOnPlayableCapture &&
        !_preventAutoReopenAfterNativeClose &&
        !_nativePlayerActive &&
        !_nativePlayerOpening) {
      final playableEmbed = masterUrl.trim();
      if (_looksLikePlayableMediaUrl(playableEmbed)) {
        _capturePlayableUrl(
          playableEmbed,
          pageUrl: _capturedVideoPageUrl ?? _currentPageUrl,
          mimeType: _inferMimeType(playableEmbed),
          qualityLabel: _currentPageQualityLabel,
        );
        Future.microtask(() => _openNativePlayer(
              force: true,
              replace: true,
              startTimeOverride: _pendingNativeStartTime,
              forcedUrl: playableEmbed,
              forcedPageUrl: _capturedVideoPageUrl ?? _currentPageUrl,
              forcedMimeType: _inferMimeType(playableEmbed),
            ));
      }
    }
  }

  Future<String> _prepareBestNativeMediaUrl(String mediaUrl, Map<String, String> headers) async {
    if (!_looksLikeHlsManifestUrl(mediaUrl)) return mediaUrl;

    final candidates = _buildHlsManifestCandidates(mediaUrl);
    String? bestMasterUrl;
    String? bestMasterBody;

    for (final candidate in candidates) {
      final body = await _fetchPlaylistBody(candidate, headers);
      if (body == null) continue;
      if (_playlistLooksLikeMaster(body)) {
        bestMasterUrl = candidate;
        bestMasterBody = body;
        break;
      }
    }

    if (bestMasterUrl != null && bestMasterBody != null) {
      _applyOptionsFromHlsMaster(bestMasterUrl, bestMasterBody);
      final preferred = _preferredDirectNativeQualityOption();
      final preferredUrl = (preferred?.url ?? '').trim();
      if (_looksLikePlayableMediaUrl(preferredUrl)) {
        _currentPageQualityLabel = preferred!.label;
        return preferredUrl;
      }
      return bestMasterUrl;
    }

    return mediaUrl;
  }

  void _prepareQualityOptionsInBackground(String mediaUrl, Map<String, String> headers) {
    final cleanUrl = mediaUrl.trim();
    if (cleanUrl.isEmpty || !_looksLikeHlsManifestUrl(cleanUrl)) return;
    if (_pageQualityOptions.length > 1) return;

    _delayedQualityHarvestTimer?.cancel();
    final ticket = ++_delayedQualityHarvestTicket;
    _delayedQualityHarvestTimer = Timer(const Duration(seconds: 5), () {
      unawaited(() async {
        try {
          if (!mounted) return;
          if (ticket != _delayedQualityHarvestTicket) return;
          if ((_lastNativePlayerUrl ?? '').trim() != cleanUrl) return;
          await _prepareBestNativeMediaUrl(cleanUrl, headers);
          if (!mounted) return;
          if (ticket != _delayedQualityHarvestTicket) return;
          if (_nativePlayerActive && (_lastNativePlayerUrl ?? '').trim() == cleanUrl) {
            await _updateNativePlayerOptions();
          }
        } catch (_) {}
      }());
    });
  }

  Future<void> _allowSitePlayerForSwitchCapture() async {
    try {
      await _wc?.evaluateJavascript(source: r'''
        (function(){
          try {
            window.__asdNativePlayerActive = false;
            try { clearInterval(window.__asdNativePauseLoop); } catch(e) {}
            window.__asdNativePauseLoop = null;
            document.querySelectorAll('video,audio').forEach(function(v){
              try {
                v.muted = true;
                v.volume = 0;
              } catch(e) {}
            });
            try {
              if (window.jwplayer) {
                var jw = window.jwplayer();
                if (jw && jw.setMute) jw.setMute(true);
              }
            } catch(e) {}
            try {
              if (window.videojs && window.videojs.getPlayers) {
                var players = window.videojs.getPlayers();
                Object.keys(players || {}).forEach(function(key) {
                  try {
                    var p = players[key];
                    if (p && p.muted) p.muted(true);
                  } catch(e) {}
                });
              }
            } catch(e) {}
          } catch(e) {}
        })();
      ''');
    } catch (_) {}
  }

  Future<Map<String, String>> _buildPipHeaders(String mediaUrl, {String? pageUrl}) async {
    final embedded = _extractEmbeddedMediaHeaders(mediaUrl);
    final captured = _bestCapturedHeadersForUrl(mediaUrl);
    final videasyProxy = _looksLikeVideasyProxyMediaUrl(mediaUrl);
    final fallbackReferer = (pageUrl != null && pageUrl.isNotEmpty)
        ? pageUrl
        : (_lastTrusted ?? 'https://asd.pics/');
    final referer = (embedded['Referer'] != null && embedded['Referer']!.isNotEmpty)
        ? embedded['Referer']!
        : ((captured['Referer'] ?? '').isNotEmpty
            ? captured['Referer']!
            : _buildReferer(mediaUrl).ifEmpty(fallbackReferer));
    String origin = (embedded['Origin'] ?? '').isNotEmpty
        ? embedded['Origin']!
        : ((captured['Origin'] ?? '').isNotEmpty
            ? captured['Origin']!
            : _buildOriginForUrl(mediaUrl, refererOverride: referer));
    try {
      if (origin.isEmpty) origin = Uri.parse(referer).origin;
    } catch (_) {}

    final cookieManager = CookieManager.instance();
    final cookieMap = <String, String>{};

    Future<void> appendCookies(String? url) async {
      if (url == null || url.isEmpty) return;
      try {
        final cookies = await cookieManager.getCookies(url: WebUri(url));
        for (final cookie in cookies) {
          if (cookie.name.isNotEmpty) cookieMap[cookie.name] = cookie.value;
        }
      } catch (_) {}
    }

    await appendCookies(pageUrl);
    await appendCookies(referer);
    await appendCookies(mediaUrl);

    final headers = <String, String>{
      ...captured,
      'User-Agent': embedded['User-Agent'] ?? captured['User-Agent'] ?? _ua,
      'Accept': captured['Accept'] ?? '*/*',
      'Accept-Language': captured['Accept-Language'] ?? 'en-US,en;q=0.9',
      'Connection': captured['Connection'] ?? 'keep-alive',
      'Referer': referer,
      'Origin': origin,
      if (!captured.containsKey('sec-ch-ua')) 'sec-ch-ua': '"Chromium";v="146", "Not-A.Brand";v="24", "Android WebView";v="146"',
      if (!captured.containsKey('sec-ch-ua-mobile')) 'sec-ch-ua-mobile': '?1',
      if (!captured.containsKey('sec-ch-ua-platform')) 'sec-ch-ua-platform': '"Android"',
      ...embedded,
    };
    if (videasyProxy) {
      headers['Referer'] = 'https://player.videasy.net/';
      headers['Origin'] = 'https://player.videasy.net';
      headers['Accept'] = '*/*';
      headers.putIfAbsent('Range', () => 'bytes=0-');
    }
    if (_isvidfastSession) {
      final mediaHost = Uri.tryParse(mediaUrl)?.host.toLowerCase() ?? '';
      if (mediaHost.contains('10017.workers.dev') ||
          mediaHost.contains('workers.dev') ||
          mediaHost.contains('megafiles.store') ||
          mediaHost.contains('rainorbit') ||
          mediaHost.contains('nightbreeze') ||
          mediaHost.contains('quietlynx')) {
        headers['Referer'] = 'https://vidfast.pro/';
        headers['Origin'] = 'https://vidfast.pro';
        headers['Accept'] = '*/*';
      }
    }
    if (cookieMap.isNotEmpty && (headers['Cookie'] == null || headers['Cookie']!.isEmpty)) {
      headers['Cookie'] = cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }
    return headers;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stealth ad blocker — injected at DOCUMENT_START
  // ─────────────────────────────────────────────────────────────────────────
  static const String _stealthAdBlock = r"""
(function(){
  'use strict';
  if (window.__asdSABv2) return;
  window.__asdSABv2 = true;

  var fakeSlot = {
    addService: function(){ return fakeSlot; },
    defineSizeMapping: function(){ return fakeSlot; },
    setTargeting: function(){ return fakeSlot; },
    setCollapseEmptyDiv: function(){ return fakeSlot; },
    getSlotElementId: function(){ return 'div-gpt-ad-fake'; },
    getAdUnitPath: function(){ return '/fake/ad'; },
    getResponseInformation: function(){ return null; }
  };

  var fakePubads = {
    enableSingleRequest: function(){},
    setTargeting: function(){ return fakePubads; },
    refresh: function(){},
    clear: function(){ return true; },
    addEventListener: function(){},
    removeEventListener: function(){},
    collapseEmptyDivs: function(){},
    enableLazyLoad: function(){},
    disableInitialLoad: function(){},
    setPrivacySettings: function(){},
    updateCorrelator: function(){},
    getTargeting: function(){ return []; },
    getTargetingKeys: function(){ return []; }
  };

  var fakeSizeMapping = {
    addSize: function(){ return fakeSizeMapping; },
    build: function(){ return []; }
  };

  if (!window.googletag || !window.googletag._asdFaked) {
    window.googletag = {
      _asdFaked: true,
      cmd: [],
      defineSlot: function(){ return fakeSlot; },
      defineOutOfPageSlot: function(){ return fakeSlot; },
      pubads: function(){ return fakePubads; },
      enableServices: function(){},
      display: function(){},
      destroySlots: function(){ return true; },
      sizeMapping: function(){ return fakeSizeMapping; },
      companionAds: function(){ return { enableSyncLoading: function(){}, setRefreshUnfilledSlots: function(){} }; }
    };
    window.googletag.cmd.push = function(fn){
      try { if (typeof fn === 'function') fn(); } catch(e) {}
    };
  }

  if (!window.adsbygoogle) { window.adsbygoogle = []; }
  window.adsbygoogle.loaded = true;
  window.adsbygoogle.push = function(cfg){ Array.prototype.push.call(window.adsbygoogle, cfg); };

  window._taboola = window._taboola || [];
  window._taboola.push = function(){};
  window.OBR = window.OBR || { extern: { renderST: function(){} } };
  window.OutbrainPerf = window.OutbrainPerf || { mark: function(){} };
  window.ExoLoader = window.ExoLoader || { serve: function(){}, load: function(){} };
  window.propellerads = window.propellerads || { push: function(){} };
  window.popns = window.popns || function(){};
  window.IABConsent_CMPPresent = true;
  window.__tcfapi = window.__tcfapi || function(cmd, ver, cb){ try { cb({}, true); } catch(e) {} };
  window.__cmp = window.__cmp || function(cmd, arg, cb){ try { cb({}, true); } catch(e) {} };

  var _adDomains = [
    'pagead2','googlesyndication','doubleclick.net',
    'adnxs','exoclick','juicyads','adsterra',
    'propellerads','popcash','popads','trafficjunky',
    'hilltopads','adcash','zeropark','richpush',
    'revcontent','mgid','rubiconproject','openx','criteo',
    'bvtpk','b7510','oyo4d','omoonsih','jnbhi','sourshaped',
    'tfnvuckb','rtmark','fundingchoicesmessages','imasdk',
    'popunder','clickunder','trafficshop','plugrush'
  ];

  function _isAdDomain(url) {
    if (!url) return false;
    var s = (url + '').toLowerCase();
    return _adDomains.some(function(d){ return s.indexOf(d) !== -1; });
  }

  // ✅ FIX 1: Block location.href navigation to ad domains from inside iframes
  try {
    if (window !== window.top) {
      var _origAssign = window.location.assign.bind(window.location);
      var _origReplace = window.location.replace.bind(window.location);
      
      window.location.assign = function(url) {
        if (_isAdDomain(url ? url.toString() : '')) return;
        _origAssign(url);
      };
      window.location.replace = function(url) {
        if (_isAdDomain(url ? url.toString() : '')) return;
        _origReplace(url);
      };
      
      // Block top-frame navigation from iframe
      try {
        Object.defineProperty(window, 'top', {
          configurable: true,
          get: function() {
            return new Proxy(window.parent, {
              get: function(target, prop) {
                if (prop === 'location') {
                  return new Proxy({href: ''}, {
                    set: function(t, p, v) {
                      if (p === 'href' && _isAdDomain(v ? v.toString() : '')) return true;
                      return true; // silently block all top.location.href assignments
                    },
                    get: function(t, p) {
                      try { return target.location[p]; } catch(e) { return t[p]; }
                    }
                  });
                }
                try { return target[prop]; } catch(e) { return undefined; }
              }
            });
          }
        });
      } catch(e) {}
    }
  } catch(e) {}

  var _origCreateElement = document.createElement.bind(document);
  document.createElement = function(tagName) {
    var el = _origCreateElement(tagName);
    var tag = (tagName + '').toLowerCase();
    if (tag === 'script' || tag === 'iframe') {
      var _origSetAttr = el.setAttribute.bind(el);
      el.setAttribute = function(attr, val) {
        if ((attr === 'src' || attr === 'data-src') && _isAdDomain(val)) {
          el._asdBlocked = true; return;
        }
        _origSetAttr(attr, val);
      };
      try {
        Object.defineProperty(el, 'src', {
          configurable: true,
          set: function(val) {
            if (_isAdDomain(val)) { el._asdBlocked = true; return; }
            _origSetAttr('src', val);
          },
          get: function() { return el.getAttribute('src') || ''; }
        });
      } catch(e) {}
    }
    return el;
  };

  var _origFetch = window.fetch;
  if (_origFetch && !window.__asdSABFetch) {
    window.__asdSABFetch = true;
    window.fetch = function(input, init) {
      var url = (typeof input === 'string' ? input : (input && input.url) || '').toString();
      if (_isAdDomain(url)) {
        return Promise.resolve(new Response('/* ok */', {
          status: 200, headers: { 'Content-Type': 'text/javascript' }
        }));
      }
      return _origFetch.apply(window, arguments);
    };
  }

  var _origGCS = window.getComputedStyle;
  window.getComputedStyle = function(el, pseudo) {
    var style = _origGCS.call(window, el, pseudo);
    try {
      var cls = ((el.className || '') + ' ' + (el.id || '')).toString().toLowerCase();
      if (/adsbox|ad-placement|ads-placeholder|adsbygoogle|ad_unit|ad-slot|adnxs/i.test(cls)) {
        return new Proxy(style, {
          get: function(t, p) {
            if (p === 'height')     return '90px';
            if (p === 'display')    return 'block';
            if (p === 'visibility') return 'visible';
            if (p === 'opacity')    return '1';
            var v = t[p];
            return typeof v === 'function' ? v.bind(t) : v;
          }
        });
      }
    } catch(e) {}
    return style;
  };

  var _antiPhrases = [
    'adblock', 'ad block', 'adblocker', 'ad blocker',
    'disable your ad', 'turn off your ad', 'whitelist',
    'please allow ads', 'please disable', 'detected ad',
    'يرجى إيقاف', 'إيقاف مانع', 'تعطيل مانع'
  ];

  function _hasAntiPhrase(text) {
    var t = text.toLowerCase();
    return _antiPhrases.some(function(p){ return t.indexOf(p) !== -1; });
  }

  function _nukeAntiAdblock() {
    var sel = [
      '[class*="adblock"],[id*="adblock"]',
      '[class*="ad-block"],[id*="ad-block"]',
      '[class*="adblocker"],[id*="adblocker"]',
      '[class*="anti-ad"],[id*="anti-ad"]',
      '[class*="blockad"],[id*="blockad"]',
      '.ab-modal,.ab-overlay,.adblock-notice,.adBlockNotice',
      '#adblock-warning,#ab-warning,#adblock-overlay'
    ].join(',');
    try { document.querySelectorAll(sel).forEach(function(el){ try { el.remove(); } catch(e) {} }); } catch(e) {}
    try {
      var all = document.querySelectorAll('div,section,aside,dialog,article,span');
      for (var i = 0; i < all.length; i++) {
        var el = all[i];
        try {
          var cs = _origGCS.call(window, el);
          var zIdx = parseInt(cs.zIndex || '0');
          var isOverlay = (cs.position === 'fixed' || cs.position === 'absolute') &&
                          zIdx > 999 && cs.display !== 'none';
          if (!isOverlay) continue;
          var txt = (el.textContent || '');
          if (txt.length > 10 && txt.length < 2000 && _hasAntiPhrase(txt)) { el.remove(); }
        } catch(e) {}
      }
    } catch(e) {}
    try {
      if (document.body && !window.__asdForcedFs && !document.fullscreenElement) {
        var bs = _origGCS.call(window, document.body);
        if (bs.overflow === 'hidden') { document.body.style.removeProperty('overflow'); }
      }
    } catch(e) {}
  }

  function _bakeBaits() {
    try {
      document.querySelectorAll('.adsbox,#adsbox,.ad-placement,#ad-placement,.ads,.ad-unit,ins.adsbygoogle').forEach(function(el){
        if (el.offsetHeight === 0) {
          el.style.cssText += ';height:1px!important;display:block!important;visibility:visible!important;';
        }
      });
    } catch(e) {}
  }

  [300, 800, 1500, 3000, 6000].forEach(function(ms){ setTimeout(_nukeAntiAdblock, ms); });
  setTimeout(_bakeBaits, 600);
  setTimeout(_bakeBaits, 2000);

  try {
    new MutationObserver(function(muts) {
      var hasNew = muts.some(function(m){ return m.addedNodes.length > 0; });
      if (hasNew) { setTimeout(_nukeAntiAdblock, 50); setTimeout(_nukeAntiAdblock, 200); }
    }).observe(document.documentElement, { childList: true, subtree: true });
  } catch(e) {}
})();
""";

  // ══════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════════
  //
  //
  // ══════════════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════════
  //
  // ══════════════════════════════════════════════════════════════════
  static const String _desktopViewport = r"""
(function(){
  var existing = document.querySelector('meta[name=\"viewport\"]');
  if (existing) existing.remove();
  var m = document.createElement('meta');
  m.name = 'viewport';
  m.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';
  (document.head || document.documentElement).appendChild(m);
})();
""";

  // ✅ FIX 3: _hideServers — now skips download pages entirely
  static const String _hideServers = r"""
(function(){
  // ✅ FIX: Don't run on download pages — they need to show file hosting links
  var href = window.location.href.toLowerCase();
  var path = window.location.pathname.toLowerCase();
  if (href.indexOf('category/download') !== -1 ||
      href.indexOf('/downloadz') !== -1 ||
      path.indexOf('/downloadz') !== -1 ||
      path.indexOf('download') !== -1) {
    return;
  }

  var removedServers = [
    'mediafire','4shared','zippyshare','uploadrar','uptobox',
    'usersdrive','filerio','clicknupload','hexupload','sendcm',
    'dailyuploads','turbobit','nitroflare','rapidgator','katfile','filefox',
    'uploaded','mega.nz','google drive'
  ];

  function hideServerLinks() {
    // ✅ FIX: Narrowed selector — don't match [class*="download"] which hides everything
    var links = document.querySelectorAll('a, button, [class*="server"], [class*="link-server"]');
    links.forEach(function(el) {
      var text = (el.textContent || el.innerText || '').toLowerCase();
      var href = (el.href || el.getAttribute('data-link') || el.getAttribute('data-url') || '').toLowerCase();
      var matched = removedServers.some(function(s) { return text.includes(s) || href.includes(s); });
      if (matched) el.style.setProperty('display','none','important');
    });
  }

  hideServerLinks();
  setInterval(hideServerLinks, 1000);
})();
""";

  static const String _css = r"""
(function(){
  var s=document.createElement('style');
  s.textContent=`
    .jw-dialog,.jw-dialog-overlay,
    [class*="ad-dialog"],[id*="ad-dialog"],
    [class*="popup"]:not([class*="player"]):not([class*="video"]):not([class*="jw"]):not([class*="vjs"]):not([class*="plyr"]),
    [id*="popup"]:not([id*="player"]):not([id*="video"]):not([id*="jw"]):not([id*="vjs"]),
    .play-overlay-ad,.ad-overlay,
    [class*="ad-overlay"],[class*="adOverlay"],
    .uq-ad,.uq-overlay,#outbrain_widget,.OUTBRAIN,
    [id*="taboola"],[class*="taboola"],
    [id*="adnxs"],[class*="adnxs"],
    [id*="exo_"],[class*="exo-"],
    [id*="pop_"],[class*="pop-up"],
    [id*="overlay_ad"],[class*="overlay_ad"],
    .content-locker,.link-locker,
    [class*="locker"],[id*="locker"]{
      display:none!important;visibility:hidden!important;
      opacity:0!important;pointer-events:none!important;}
  `;
  (document.head||document.documentElement).appendChild(s);
})();
""";

  static const String _ads = r"""
(function(){
  'use strict';

  var adDomains = [
    'popads','popcash','adcash','doubleclick','googlesyndication',
    'adnxs','exoclick','juicyads','adsterra','propellerads',
    'trafficjunky','hilltopads','richpush','zeropark','revcontent',
    'taboola','outbrain','mgid','rubiconproject','openx','criteo',
    'b7510','oyo4d','bvtpk','omoonsih','jnbhi','sourshaped',
    'tfnvuckb','waust','whacmoltibsay','rtmark','fundingchoices',
    'popunder','clickunder','trafficshop','plugrush','imasdk'
  ];

  function isAdUrl(url) {
    if (!url) return true;
    return adDomains.some(function(d){ return url.indexOf(d) !== -1; });
  }

  var _origOpen = window.open;
  window.open = function(url, target, features) {
    if (isAdUrl(url ? url.toString() : '')) return null;
    return _origOpen ? _origOpen.call(window, url, target, features) : null;
  };

  // ✅ FIX 1: Also block location navigation to ad URLs
  try {
    var _origAssign = window.location.assign.bind(window.location);
    window.location.assign = function(url) {
      if (isAdUrl(url ? url.toString() : '')) return;
      _origAssign(url);
    };
  } catch(e) {}

  window.alert = function(){};
  window.confirm = function(){ return false; };
  window.prompt = function(){ return null; };
})();
""";

  static const String _forcePhoneFullscreen = r"""
(function(){
  if (window.__asdForceFsInstalled) return;
  window.__asdForceFsInstalled = true;
  window.__asdForcedFs = false;

  var style = document.createElement('style');
  style.textContent = `
    html.asd-phone-fs,
    body.asd-phone-fs{
      width:100%!important;height:100%!important;
      overflow:hidden!important;background:#000!important;
      margin:0!important;padding:0!important;
    }
    .asd-fs-parent{
      position:fixed!important;inset:0!important;
      width:100vw!important;height:100vh!important;
      max-width:100vw!important;max-height:100vh!important;
      margin:0!important;padding:0!important;transform:none!important;
      z-index:2147483645!important;overflow:hidden!important;
      background:#000!important;border:none!important;border-radius:0!important;
    }
    .asd-fs-target,
    .asd-fs-target iframe,
    .asd-fs-target video,
    .asd-fs-target .jwplayer,
    .asd-fs-target .jw-video,
    .asd-fs-target .jw-media,
    .asd-fs-target .video-js,
    .asd-fs-target .vjs-tech,
    .asd-fs-target .plyr,
    .asd-fs-target .plyr__video-wrapper,
    .asd-fs-target .dplayer,
    .asd-fs-target .mejs-container{
      position:fixed!important;inset:0!important;
      width:100vw!important;height:100vh!important;
      max-width:100vw!important;max-height:100vh!important;
      min-width:100vw!important;min-height:100vh!important;
      margin:0!important;padding:0!important;transform:none!important;
      z-index:2147483647!important;background:#000!important;
      border:none!important;border-radius:0!important;
      aspect-ratio:auto!important;box-sizing:border-box!important;
    }
    .asd-fs-target video,
    .asd-fs-target .jw-video,
    .asd-fs-target .vjs-tech{
      object-fit:contain!important;background:#000!important;
    }
    .asd-fs-target .jw-controlbar,
    .asd-fs-target .jw-controls,
    .asd-fs-target .jw-button-container,
    .asd-fs-target .jw-icon,
    .asd-fs-target .jw-slider-container,
    .asd-fs-target .jw-display-icon-container,
    .asd-fs-target .jw-display,
    .asd-fs-target .jw-display-container,
    .asd-fs-target .vjs-control-bar,
    .asd-fs-target .vjs-big-play-button,
    .asd-fs-target .vjs-control,
    .asd-fs-target .vjs-slider,
    .asd-fs-target .plyr__controls,
    .asd-fs-target .plyr__control,
    .asd-fs-target .dplayer-controller,
    .asd-fs-target .dplayer-bar,
    .asd-fs-target .dplayer-icons,
    .asd-fs-target .mejs__controls,
    .asd-fs-target [class*="controlbar"],
    .asd-fs-target [class*="control-bar"],
    .asd-fs-target [class*="controls"] {
      pointer-events: auto !important;
      z-index: 2147483647 !important;
    }
    .asd-phone-fs .jwplayer.jw-flag-user-inactive .jw-controlbar,
    .asd-phone-fs .jwplayer.jw-flag-user-inactive .jw-controls {
      opacity: 0;
      visibility: hidden;
      transition: opacity 0.3s ease, visibility 0.3s ease;
    }
    .asd-fs-hide{
      opacity:0!important;visibility:hidden!important;
      pointer-events:none!important;
    }
  `;
  (document.head || document.documentElement).appendChild(style);

  var currentTarget = null;
  var _stickyWanted = false;
  var _explicitExit = false;
  var _reenterTimer = null;

  function fl(name, value) {
    try { window.flutter_inappwebview.callHandler(name, value); } catch(e) {}
  }

  function nativeFsActive() {
    return !!(document.fullscreenElement || document.webkitFullscreenElement);
  }

  function isVisible(el) {
    if (!el || !el.getBoundingClientRect) return false;
    var r = el.getBoundingClientRect();
    return r.width > 120 && r.height > 80;
  }

  function hasActiveTarget() {
    return !!(currentTarget && document.contains(currentTarget) && isVisible(currentTarget));
  }

  function pickTarget() {
    var selectors = [
      '.jwplayer','.video-js','.plyr','.dplayer','.mejs-container',
      '#player','[id*="player"]','[class*="player"]','iframe[src]','video'
    ];
    for (var i = 0; i < selectors.length; i++) {
      var els = document.querySelectorAll(selectors[i]);
      for (var j = 0; j < els.length; j++) {
        var el = els[j];
        if (!isVisible(el)) continue;
        if (el.tagName === 'IFRAME' || el.tagName === 'VIDEO' ||
            el.querySelector('video') || el.querySelector('iframe') ||
            selectors[i] === '.jwplayer' || selectors[i] === '.video-js' ||
            selectors[i] === '.plyr' || selectors[i] === '.dplayer') {
          return el;
        }
      }
    }
    var biggest = null, biggestArea = 0;
    var all = document.querySelectorAll('div,section,article,iframe,video');
    for (var k = 0; k < all.length; k++) {
      var node = all[k];
      var rect = node.getBoundingClientRect ? node.getBoundingClientRect() : null;
      if (!rect) continue;
      var area = rect.width * rect.height;
      if (rect.width > 180 && rect.height > 120 && area > biggestArea) {
        if (node.tagName === 'VIDEO' || node.tagName === 'IFRAME' ||
            node.querySelector('video') || node.querySelector('iframe') ||
            /player|video|embed|jw|plyr|vjs/i.test((node.id||'')+' '+(node.className||''))) {
          biggest = node; biggestArea = area;
        }
      }
    }
    return biggest;
  }

  function markParents(el) {
    var p = el && el.parentElement, count = 0;
    while (p && p !== document.body && count < 6) {
      p.classList.add('asd-fs-parent'); count++; p = p.parentElement;
    }
  }

  function unmarkParents(el) {
    var p = el && el.parentElement, count = 0;
    while (p && p !== document.body && count < 6) {
      p.classList.remove('asd-fs-parent'); count++; p = p.parentElement;
    }
  }

  function hidePageNoise(enable) {
    var blocks = document.querySelectorAll(
      'header:not([class*="player"]):not([class*="jw"]):not([class*="vjs"]), ' +
      'footer:not([class*="player"]):not([class*="jw"]), ' +
      'nav.navbar, nav.nav, .site-header, .site-footer, ' +
      '.sidebar:not([class*="player"]), ' +
      '.social-share, .share-buttons, ' +
      '.cookie-banner, .gdpr-banner'
    );
    blocks.forEach(function(el){
      if (enable) el.classList.add('asd-fs-hide');
      else el.classList.remove('asd-fs-hide');
    });
  }

  function applyForcedState() {
    if (!currentTarget) return false;
    window.__asdForcedFs = true;
    document.documentElement.classList.add('asd-phone-fs');
    if (document.body) document.body.classList.add('asd-phone-fs');
    currentTarget.classList.add('asd-fs-target');
    markParents(currentTarget);
    hidePageNoise(true);
    fl('onForcePhoneFs', true);
    return true;
  }

  function clearForcedState() {
    window.__asdForcedFs = false;
    document.documentElement.classList.remove('asd-phone-fs');
    if (document.body) document.body.classList.remove('asd-phone-fs');
    hidePageNoise(false);
    if (currentTarget) {
      currentTarget.classList.remove('asd-fs-target');
      unmarkParents(currentTarget);
    }
    currentTarget = null;
    fl('onForcePhoneFs', false);
  }

  function scheduleReenter(delay) {
    if (_explicitExit || !_stickyWanted) return;
    if (_reenterTimer) clearTimeout(_reenterTimer);
    _reenterTimer = setTimeout(function() {
      _reenterTimer = null;
      if (_explicitExit || !_stickyWanted) return;
      if (!hasActiveTarget()) currentTarget = pickTarget() || currentTarget;
      if (currentTarget) applyForcedState();
    }, delay || 60);
  }

  function enterForcedPhoneFs() {
    currentTarget = pickTarget() || currentTarget;
    if (!currentTarget) return false;
    _stickyWanted = true; _explicitExit = false;
    return applyForcedState();
  }

  function exitForcedPhoneFs(force) {
    if (force !== true && _stickyWanted) { scheduleReenter(60); return false; }
    _stickyWanted = false; _explicitExit = true;
    if (_reenterTimer) { clearTimeout(_reenterTimer); _reenterTimer = null; }
    clearForcedState();
    return true;
  }

  window.__asdForceFullscreenNow = function() {
    _stickyWanted = true; _explicitExit = false; return enterForcedPhoneFs();
  };
  window.__asdExitForcedFullscreen = function() { return exitForcedPhoneFs(true); };

  document.addEventListener('fullscreenchange', function() {
    var active = nativeFsActive();
    if (active) { enterForcedPhoneFs(); return; }
    if (_explicitExit) { exitForcedPhoneFs(true); return; }
    if (_stickyWanted) { scheduleReenter(30); setTimeout(function(){ scheduleReenter(180); }, 0); return; }
    exitForcedPhoneFs(true);
  }, true);

  document.addEventListener('webkitfullscreenchange', function() {
    var active = nativeFsActive();
    if (active) { enterForcedPhoneFs(); return; }
    if (_explicitExit) { exitForcedPhoneFs(true); return; }
    if (_stickyWanted) { scheduleReenter(30); setTimeout(function(){ scheduleReenter(180); }, 0); return; }
    exitForcedPhoneFs(true);
  }, true);

  document.addEventListener('click', function(e) {
    var el = e.target && e.target.closest ? e.target.closest(
      '.jw-icon-fullscreen, .vjs-fullscreen-control, [data-plyr="fullscreen"], ' +
      '.plyr__control--overlaid, .plyr__control--fullscreen, ' +
      '[class*="fullscreen"], [id*="fullscreen"], ' +
      '[aria-label*="full"], [title*="Full"], [title*="fullscreen"]'
    ) : null;
    if (!el) return;
    var txt = ((el.textContent||'')+' '+(el.getAttribute('aria-label')||'')+' '+(el.getAttribute('title')||'')).toLowerCase();
    var cls = (el.className||'').toString().toLowerCase();
    var dataPlyr = ((el.getAttribute&&el.getAttribute('data-plyr'))||'').toLowerCase();
    var pressed = ((el.getAttribute&&el.getAttribute('aria-pressed'))||'').toLowerCase();
    var isExit = txt.indexOf('exit')!==-1||cls.indexOf('exit-fullscreen')!==-1||pressed==='true';
    var isFull = txt.indexOf('full')!==-1||cls.indexOf('fullscreen')!==-1||dataPlyr==='fullscreen';
    if (!isFull && !isExit) return;
    if (isExit) {
      _stickyWanted = false; _explicitExit = true;
      setTimeout(function(){ exitForcedPhoneFs(true); }, 60);
      return;
    }
    _stickyWanted = true; _explicitExit = false;
    setTimeout(function(){ enterForcedPhoneFs(); }, 60);
    setTimeout(function(){ enterForcedPhoneFs(); }, 400);
  }, true);
})();
""";

  static const String _fsVid = r"""
(function injectAll(doc, win) {
  'use strict';

  function fl(n, v) {
    try { win.flutter_inappwebview.callHandler(n, v); } catch(e) {
      try { win.top.flutter_inappwebview.callHandler(n, v); } catch(e2) {}
    }
  }

  win.__asdLastUserGesture = win.__asdLastUserGesture || 0;
  ['pointerdown','touchstart','mousedown','keydown'].forEach(function(evt){
    doc.addEventListener(evt, function(){ win.__asdLastUserGesture = Date.now(); }, true);
  });

  function maybeUrl(url) {
    if (!url || typeof url !== 'string') return null;
    var s = url.trim();
    if (!s || s.indexOf('blob:') === 0) return null;
    var lower = s.toLowerCase();
    if (lower.indexOf('.m3u8')!==-1||lower.indexOf('.mp4')!==-1||
        lower.indexOf('.mkv')!==-1||lower.indexOf('.webm')!==-1||
        lower.indexOf('.m4v')!==-1||
        lower.indexOf('.mov')!==-1||lower.indexOf('.mpd')!==-1||
        lower.indexOf('mime=video')!==-1||lower.indexOf('/playlist')!==-1||
        lower.indexOf('/manifest')!==-1||lower.indexOf('/hls/')!==-1) {
      return s;
    }
    return null;
  }

  function sendCandidate(url, extra) {
    var clean = maybeUrl(url);
    if (!clean) return;
    var payload = { url: clean, pageUrl: win.location.href, currentTime: 0, mimeType: null };
    if (extra) { for (var k in extra) payload[k] = extra[k]; }
    fl('onVideoFound', payload);
  }

  function qualityLabelFromText(text) {
    text = (text || '').replace(/\s+/g, ' ').trim();
    var m = text.match(/(2160|1440|1080|720|540|480|360|240)\s*p?/i);
    return m ? (m[1] + 'p') : null;
  }

  function clickEl(el) {
    if (!el) return false;
    try { el.dispatchEvent(new MouseEvent('pointerdown', {bubbles:true,cancelable:true})); } catch(e) {}
    try { el.dispatchEvent(new MouseEvent('mousedown', {bubbles:true,cancelable:true})); } catch(e) {}
    try { el.dispatchEvent(new MouseEvent('mouseup', {bubbles:true,cancelable:true})); } catch(e) {}
    try { el.click(); return true; } catch(e) {}
    return false;
  }

  function collectQualityOptions() {
    var out = [];
    var seen = {};
    try {
      var nodes = doc.querySelectorAll('a,button,li,div,span');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (!el || !el.textContent) continue;
        var label = qualityLabelFromText((el.textContent || '') + ' ' + (el.getAttribute && (el.getAttribute('title') || el.getAttribute('aria-label')) || ''));
        if (!label) continue;
        var href = (el.href || (el.getAttribute && (el.getAttribute('data-url') || el.getAttribute('data-link') || el.getAttribute('href'))) || '').trim();
        var key = (href || label + '_' + i).replace(/[^a-zA-Z0-9_:\/.\-]/g, '_');
        var selected = /active|current|selected|checked/.test(((el.className || '') + ' ' + (el.parentElement && el.parentElement.className || '')).toLowerCase()) ||
          (el.getAttribute && (el.getAttribute('aria-current') === 'true' || el.getAttribute('aria-selected') === 'true' || el.getAttribute('aria-pressed') === 'true'));
        try { el.setAttribute('data-asd-quality-key', key); } catch(e) {}
        var uniq = (label + '|' + href).toLowerCase();
        if (seen[uniq]) continue;
        seen[uniq] = true;
        out.push({ label: label, key: key, url: href || '', selected: selected });
      }
    } catch(e) {}
    if (out.length) {
      var current = null;
      for (var j = 0; j < out.length; j++) { if (out[j].selected) { current = out[j].label; break; } }
      if (!current) {
        var head = doc.body ? doc.body.innerText || '' : '';
        current = qualityLabelFromText(head) || out[0].label;
      }
      fl('onQualityOptions', { options: out, current: current });
    }
    return out;
  }

  win.__asdSelectQualityOption = function(key, label, url) {
    try {
      collectQualityOptions();
      var byKey = key ? doc.querySelector('[data-asd-quality-key="' + String(key).replace(/"/g,'\"') + '"]') : null;
      if (byKey) return clickEl(byKey);
      var nodes = doc.querySelectorAll('a,button,li,div,span');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        var txt = qualityLabelFromText((el.textContent || '') + ' ' + (el.getAttribute && (el.getAttribute('title') || el.getAttribute('aria-label')) || ''));
        var href = (el.href || (el.getAttribute && (el.getAttribute('data-url') || el.getAttribute('data-link') || el.getAttribute('href'))) || '').trim();
        if ((label && txt === label) || (url && href === url)) {
          return clickEl(el);
        }
      }
    } catch(e) {}
    return false;
  };

  function getVideoInfo(v) {
    var url = maybeUrl(v.currentSrc) || maybeUrl(v.src);
    if (!url) {
      var srcs = v.querySelectorAll('source');
      for (var i = 0; i < srcs.length; i++) {
        var s = maybeUrl(srcs[i].src || srcs[i].getAttribute('src'));
        if (s) { url = s; break; }
      }
    }
    return {
      url: url, pageUrl: win.location.href,
      currentTime: isFinite(v.currentTime) ? v.currentTime : 0,
      duration: isFinite(v.duration) ? v.duration : 0,
      paused: v.paused, isBlob: !url,
      videoWidth: v.videoWidth || 0,
      videoHeight: v.videoHeight || 0,
      mimeType: v.currentSrc && v.currentSrc.toLowerCase().indexOf('.m3u8')!==-1
        ? 'application/x-mpegURL'
        : (v.currentSrc && v.currentSrc.toLowerCase().indexOf('.mp4')!==-1
            ? 'video/mp4' : (v.getAttribute('type') || null))
    };
  }

  try {
    var proto = win.HTMLVideoElement ? win.HTMLVideoElement.prototype : null;
    if (proto && !proto._asd_pip_patched) {
      proto._asd_pip_patched = true;
      var _origPlay = proto.play;
      proto.play = function() {
        var self = this;
        var info = getVideoInfo(self);
        var recentGesture = Date.now() - (win.__asdLastUserGesture || 0) < 1600;
        if (win.__asdNativePlayerActive) {
          try { self.pause(); self.muted = true; self.volume = 0; } catch(e) {}
          return Promise.resolve();
        }
        if (recentGesture && info.url) {
          try { self.pause(); self.muted = true; self.volume = 0; } catch(e) {}
          fl('onPlayIntent', info);
          return Promise.resolve();
        }
        return _origPlay ? _origPlay.apply(this, arguments) : Promise.resolve();
      };
      proto.requestPictureInPicture = function() {
        var self = this;
        var info = getVideoInfo(self);
        if (info.url) sendCandidate(info.url, info);
        fl('onPip', info);
        return Promise.resolve({
          addEventListener: function(){}, removeEventListener: function(){},
          dispatchEvent: function(){ return true; }, width: 0, height: 0
        });
      };
    }
  } catch(e) {}

  try {
    if (win.Hls && win.Hls.prototype && !win.Hls.prototype._asd_patched) {
      win.Hls.prototype._asd_patched = true;
      var _origLoadSource = win.Hls.prototype.loadSource;
      win.Hls.prototype.loadSource = function(url) {
        sendCandidate(url, { mimeType: 'application/x-mpegURL' });
        return _origLoadSource ? _origLoadSource.apply(this, arguments) : undefined;
      };
    }
  } catch(e) {}

  function probeJwPlayer() {
    try {
      if (!win.jwplayer) return;
      var jw = win.jwplayer();
      if (!jw) return;
      var item = jw.getPlaylistItem && jw.getPlaylistItem();
      if (item) {
        if (item.file) sendCandidate(item.file, { currentTime: jw.getPosition ? (jw.getPosition()||0) : 0 });
        if (Array.isArray(item.sources)) {
          item.sources.forEach(function(src){
            if (!src) return;
            sendCandidate(src.file||src.src, { currentTime: jw.getPosition?(jw.getPosition()||0):0, mimeType: src.type||null });
          });
        }
      }
    } catch(e) {}
  }

  function probeVideoJs() {
    try {
      if (!win.videojs || !win.videojs.getPlayers) return;
      var players = win.videojs.getPlayers();
      Object.keys(players||{}).forEach(function(key){
        try {
          var p = players[key];
          if (!p) return;
          var src = p.currentSource && p.currentSource();
          sendCandidate(src&&(src.src||src.file), { currentTime: p.currentTime?(p.currentTime()||0):0, mimeType: src&&(src.type||null) });
        } catch(e) {}
      });
    } catch(e) {}
  }

  var _fs = false;
  function onFsChange() {
    var now = !!(doc.fullscreenElement || doc.webkitFullscreenElement);
    if (now != _fs) { _fs = now; fl('onFS', now); }
  }
  doc.addEventListener('fullscreenchange', onFsChange);
  doc.addEventListener('webkitfullscreenchange', onFsChange);

  function setupVideo(v) {
    if (v._asd_vid) return;
    v._asd_vid = true;
    function pushInfo() {
      var info = getVideoInfo(v);
      if (info.url) sendCandidate(info.url, info);
      fl('onVid', { playing: !v.paused && !v.ended, info: info });
    }
    v.addEventListener('play', pushInfo);
    v.addEventListener('playing', pushInfo);
    v.addEventListener('pause', function(){ fl('onVid', { playing: false, info: getVideoInfo(v) }); });
    v.addEventListener('ended', function(){ fl('onVid', { playing: false, info: getVideoInfo(v) }); });
    v.addEventListener('loadedmetadata', pushInfo);
    v.addEventListener('loadeddata', pushInfo);
    pushInfo();
    setInterval(function() {
      if (!v.paused && !v.ended && isFinite(v.currentTime)) {
        var info = getVideoInfo(v);
        if (info.url) sendCandidate(info.url, info);
        fl('onTime', v.currentTime);
        if (v.videoWidth > 0 && v.videoHeight > 0) {
          fl('onVideoDimensions', { width: v.videoWidth, height: v.videoHeight });
        }
      }
    }, 1000);
  }

  function scanVideos(root) {
    try { (root||doc).querySelectorAll('video').forEach(setupVideo); } catch(e) {}
  }

  win.__asdCollectMediaNow = function() {
    scanVideos(doc); probeJwPlayer(); probeVideoJs(); collectQualityOptions();
  };

  scanVideos(doc); probeJwPlayer(); probeVideoJs(); collectQualityOptions();
  setInterval(win.__asdCollectMediaNow, 1500);

  new MutationObserver(function(muts) {
    muts.forEach(function(m) {
      m.addedNodes.forEach(function(node) {
        if (node.tagName === 'VIDEO') setupVideo(node);
        if (node.querySelectorAll) node.querySelectorAll('video').forEach(setupVideo);
      });
    });
  }).observe(doc.body || doc.documentElement, { childList: true, subtree: true });

})(document, window);
""";

  static const String _touchFix = r"""
(function(){
  'use strict';
  if (window.__asdTouchFixInstalled) return;
  window.__asdTouchFixInstalled = true;

  var HOLD_MS = 7000;
  var _hideTimer = null;
  var _styleInjected = false;

  var CONTROL_SELS = [
    '.jw-controlbar','.jw-controls','.jw-button-container',
    '.jw-icon','.jw-slider-container','.jw-text-elapsed','.jw-text-duration',
    '.jw-display-icon-container','.jw-slider-time','.jw-knob',
    '.jw-icon-display','.jw-icon-rewind','.jw-icon-playback',
    '.jw-icon-forward','.jw-icon-fullscreen','.jw-icon-volume',
    '.jw-icon-cast','.jw-icon-settings','.jw-icon-cc',
    '.jw-display','.jw-display-container','.jw-display-icon-next',
    '.vjs-control-bar','.vjs-big-play-button','.vjs-control',
    '.vjs-slider','.vjs-progress-control','.vjs-play-control',
    '.vjs-volume-panel','.vjs-fullscreen-control','.vjs-menu',
    '.plyr__controls','.plyr__control','.plyr__progress',
    '.plyr__time','.plyr__volume','.plyr__menu',
    '.dplayer-controller','.dplayer-bar','.dplayer-icons',
    '.mejs__controls',
    '[class*="controlbar"]','[class*="control-bar"]',
    '[class*="controls"]','[class*="progress"]',
    '[class*="seek"]','[class*="playback"]','[class*="toolbar"]',
    '[role="button"]','[role="slider"]',
    'button','input[type="range"]'
  ];

  function inFs() {
    try {
      if (window !== window.top) {
        return !!(window.top.__asdForcedFs) ||
               !!(window.top.document &&
                  window.top.document.documentElement &&
                  window.top.document.documentElement.classList.contains('asd-phone-fs'));
      }
    } catch(e) {}
    return !!(
      window.__asdForcedFs ||
      document.fullscreenElement ||
      document.webkitFullscreenElement ||
      (document.documentElement &&
       document.documentElement.classList.contains('asd-phone-fs'))
    );
  }

  function injectStyle() {
    if (_styleInjected) return;
    _styleInjected = true;
    var s = document.createElement('style');
    s.id = 'asd-touch-fix-style';
    s.textContent = `
      html.asd-controls-force-visible .jw-controlbar,
      html.asd-controls-force-visible .jw-controls,
      html.asd-controls-force-visible .jw-button-container,
      html.asd-controls-force-visible .jw-icon,
      html.asd-controls-force-visible .jw-slider-container,
      html.asd-controls-force-visible .jw-text-elapsed,
      html.asd-controls-force-visible .jw-text-duration,
      html.asd-controls-force-visible .jw-display-icon-container,
      html.asd-controls-force-visible .jw-display,
      html.asd-controls-force-visible .jw-display-container,
      html.asd-controls-force-visible .jw-slider-time,
      html.asd-controls-force-visible .jw-knob,
      html.asd-controls-force-visible .vjs-control-bar,
      html.asd-controls-force-visible .vjs-big-play-button,
      html.asd-controls-force-visible .vjs-control,
      html.asd-controls-force-visible .vjs-slider,
      html.asd-controls-force-visible .vjs-progress-control,
      html.asd-controls-force-visible .plyr__controls,
      html.asd-controls-force-visible .plyr__control,
      html.asd-controls-force-visible .plyr__progress,
      html.asd-controls-force-visible .dplayer-controller,
      html.asd-controls-force-visible .dplayer-bar,
      html.asd-controls-force-visible .dplayer-icons,
      html.asd-controls-force-visible .mejs__controls,
      html.asd-controls-force-visible [class*="controlbar"],
      html.asd-controls-force-visible [class*="control-bar"],
      html.asd-controls-force-visible [class*="controls"],
      html.asd-controls-force-visible [class*="progress"],
      html.asd-controls-force-visible [class*="seek"] {
        opacity: 1 !important;
        visibility: visible !important;
        pointer-events: auto !important;
        transition-delay: 0s !important;
      }
      html.asd-controls-force-visible .jwplayer.jw-flag-user-inactive .jw-controlbar,
      html.asd-controls-force-visible .jwplayer.jw-flag-user-inactive .jw-controls {
        opacity: 1 !important;
        visibility: visible !important;
        pointer-events: auto !important;
      }
    `;
    (document.head || document.documentElement).appendChild(s);
  }

  function wakePlayer() {
    try {
      var mv = new MouseEvent('mousemove', { bubbles: true, cancelable: true, view: window });
      document.dispatchEvent(mv);
      document.querySelectorAll('video, iframe, .jwplayer, .video-js, .plyr, .dplayer').forEach(function(el){
        try { el.dispatchEvent(mv); } catch(e) {}
      });
    } catch(e) {}
    try {
      if (window.jwplayer) {
        var jw = window.jwplayer();
        if (jw && jw.getState && jw.getState() !== 'idle') {
          var jwEl = document.querySelector('.jwplayer');
          if (jwEl) {
            var evt = new MouseEvent('mousemove', { bubbles: true, view: window });
            jwEl.dispatchEvent(evt);
          }
        }
      }
    } catch(e) {}
    try {
      document.querySelectorAll('.jwplayer.jw-flag-user-inactive').forEach(function(el){
        el.classList.remove('jw-flag-user-inactive');
      });
    } catch(e) {}
  }

  function forceShowNow() {
    injectStyle();
    document.documentElement.classList.add('asd-controls-force-visible');
    if (document.body) document.body.classList.add('asd-controls-force-visible');
    CONTROL_SELS.forEach(function(sel) {
      try {
        document.querySelectorAll(sel).forEach(function(el) {
          el.style.setProperty('opacity', '1', 'important');
          el.style.setProperty('visibility', 'visible', 'important');
          el.style.setProperty('pointer-events', 'auto', 'important');
          if (el.style.display === 'none') el.style.removeProperty('display');
        });
      } catch(e) {}
    });
    try {
      document.querySelectorAll('.jwplayer.jw-flag-user-inactive').forEach(function(el){
        el.classList.remove('jw-flag-user-inactive');
      });
    } catch(e) {}
    wakePlayer();
  }

  function releaseControls() {
    document.documentElement.classList.remove('asd-controls-force-visible');
    if (document.body) document.body.classList.remove('asd-controls-force-visible');
    CONTROL_SELS.forEach(function(sel) {
      try {
        document.querySelectorAll(sel).forEach(function(el) {
          el.style.removeProperty('opacity');
          el.style.removeProperty('visibility');
          el.style.removeProperty('pointer-events');
        });
      } catch(e) {}
    });
  }

  function armHideTimer() {
    if (_hideTimer) clearTimeout(_hideTimer);
    _hideTimer = setTimeout(function() { _hideTimer = null; releaseControls(); }, HOLD_MS);
  }

  function hasInteractiveHints(target) {
    if (!target || !target.getAttribute) return false;
    var role = (target.getAttribute('role') || '').toLowerCase();
    var aria = (target.getAttribute('aria-label') || '').toLowerCase();
    var title = (target.getAttribute('title') || '').toLowerCase();
    return role === 'button' || role === 'slider' ||
      aria.indexOf('play') !== -1 || aria.indexOf('pause') !== -1 ||
      aria.indexOf('seek') !== -1 || aria.indexOf('full') !== -1 ||
      aria.indexOf('volume') !== -1 || aria.indexOf('mute') !== -1 ||
      title.indexOf('play') !== -1 || title.indexOf('pause') !== -1 ||
      title.indexOf('seek') !== -1 || title.indexOf('full') !== -1;
  }

  function isControlElement(node) {
    var target = node;
    while (target && target !== document.documentElement) {
      var cls = (target.className || '').toString();
      var tag = (target.tagName || '').toUpperCase();
      var id  = (target.id || '').toString();
      if (
        /jw-icon|jw-button|jw-controlbar|jw-controls|jw-slider|jw-knob|jw-display|jw-display-icon|jw-display-container|jw-icon-display|jw-icon-rewind|jw-icon-playback|jw-icon-forward|jw-icon-fullscreen|jw-icon-volume|jw-icon-settings|jw-icon-cc|jw-icon-cast/i.test(cls) ||
        /vjs-control|vjs-slider|vjs-big-play|vjs-play-control|vjs-volume|vjs-fullscreen|vjs-menu|vjs-time|vjs-progress/i.test(cls) ||
        /plyr__control|plyr__controls|plyr__progress|plyr__time|plyr__volume|plyr__menu/i.test(cls) ||
        /dplayer-controller|dplayer-bar|dplayer-icons|dplayer-setting|dplayer-volume/i.test(cls) ||
        /mejs__controls|mejs__button|mejs__playpause|mejs__time|mejs__volume/i.test(cls) ||
        /controlbar|control-bar|controls|progress-bar|seekbar|seek-bar|playback|toolbar/i.test(cls) ||
        /jw-|vjs-|plyr/i.test(id) ||
        tag === 'BUTTON' || tag === 'INPUT' || tag === 'A' ||
        tag === 'SELECT' || tag === 'TEXTAREA' || tag === 'LABEL' ||
        tag === 'SUMMARY' || tag === 'SVG' || tag === 'PATH' ||
        tag === 'USE' || tag === 'G' || tag === 'CIRCLE' ||
        tag === 'RECT' || tag === 'POLYGON' || tag === 'POLYLINE' ||
        hasInteractiveHints(target)
      ) { return true; }
      target = target.parentElement;
    }
    return false;
  }

  function handleInteraction(e) {
    if (!inFs()) return;
    if (isControlElement(e.target)) {
      forceShowNow();
      armHideTimer();
      return;
    }
    var tag = e.target ? (e.target.tagName || '').toUpperCase() : '';
    if (tag !== 'VIDEO') return;
    forceShowNow();
    armHideTimer();
  }

  document.addEventListener('touchstart',  handleInteraction, { passive: true,  capture: true });
  document.addEventListener('touchend',    handleInteraction, { passive: true,  capture: true });
  document.addEventListener('pointerdown', handleInteraction, { passive: true,  capture: true });
  document.addEventListener('pointerup',   handleInteraction, { passive: true,  capture: true });
  document.addEventListener('mousedown',   handleInteraction, { passive: true,  capture: true });
  document.addEventListener('click',       handleInteraction, { passive: true,  capture: true });

  document.addEventListener('fullscreenchange', function() {
    if (!inFs()) { if (_hideTimer) { clearTimeout(_hideTimer); _hideTimer = null; } releaseControls(); }
  }, true);
  document.addEventListener('webkitfullscreenchange', function() {
    if (!inFs()) { if (_hideTimer) { clearTimeout(_hideTimer); _hideTimer = null; } releaseControls(); }
  }, true);

  window.__asdShowControls = function() { if (!inFs()) return; forceShowNow(); armHideTimer(); };
  window.__asdStopControls = function() { if (_hideTimer) { clearTimeout(_hideTimer); _hideTimer = null; } releaseControls(); };

  function startJwWatchdog() {
    try {
      var jwEl = document.querySelector('.jwplayer');
      if (!jwEl || jwEl._asdWatchdog) return;
      jwEl._asdWatchdog = true;
      new MutationObserver(function(muts) {
        if (!inFs()) return;
        muts.forEach(function(m) {
          if (m.attributeName === 'class') {
            var el = m.target;
            if (el.classList.contains('jw-flag-user-inactive')) {
              setTimeout(function() {
                if (inFs() && _hideTimer) {
                  el.classList.remove('jw-flag-user-inactive');
                }
              }, 20);
            }
          }
        });
      }).observe(jwEl, { attributes: true, subtree: false });
    } catch(e) {}
  }

  function startVjsWatchdog() {
    try {
      if (!window.videojs || !window.videojs.getPlayers) return;
      var players = window.videojs.getPlayers();
      Object.keys(players || {}).forEach(function(key) {
        try {
          var p = players[key];
          if (!p || p._asdWatchdog) return;
          p._asdWatchdog = true;
          p.on('userinactive', function() {
            if (inFs() && _hideTimer) {
              setTimeout(function() { try { p.userActive(true); } catch(e) {} }, 20);
            }
          });
        } catch(e) {}
      });
    } catch(e) {}
  }

  setTimeout(startJwWatchdog, 1000);
  setTimeout(startJwWatchdog, 3000);
  setTimeout(startVjsWatchdog, 1000);
  setTimeout(startVjsWatchdog, 3000);

  try {
    new MutationObserver(function(muts) {
      var hasNew = muts.some(function(m){ return m.addedNodes.length > 0; });
      if (hasNew) { setTimeout(startJwWatchdog, 500); setTimeout(startVjsWatchdog, 500); }
    }).observe(document.body || document.documentElement, { childList: true, subtree: true });
  } catch(e) {}
})();
""";

  static const String _iframeVideoFix = r"""
(function(){
  'use strict';
  if (window.__asdIframeVideoFixInstalled) return;
  window.__asdIframeVideoFixInstalled = true;

  var _lastTouchTime = 0;
  var _touchPauseBlocked = false;
  var _lastTouchKind = 'other';

  function isInForcedFs() {
    try {
      if (window !== window.top) {
        return !!(window.top.__asdForcedFs) ||
               !!(window.top.document &&
                  window.top.document.documentElement &&
                  window.top.document.documentElement.classList.contains('asd-phone-fs'));
      }
    } catch(e) {}
    return !!(
      window.__asdForcedFs ||
      (document.documentElement && document.documentElement.classList.contains('asd-phone-fs')) ||
      document.fullscreenElement || document.webkitFullscreenElement
    );
  }

  function hasInteractiveHints(target) {
    if (!target || !target.getAttribute) return false;
    var role = (target.getAttribute('role') || '').toLowerCase();
    var aria = (target.getAttribute('aria-label') || '').toLowerCase();
    var title = (target.getAttribute('title') || '').toLowerCase();
    return role === 'button' || role === 'slider' ||
      aria.indexOf('play') !== -1 || aria.indexOf('pause') !== -1 ||
      aria.indexOf('seek') !== -1 || aria.indexOf('full') !== -1 ||
      aria.indexOf('volume') !== -1 || aria.indexOf('mute') !== -1 ||
      title.indexOf('play') !== -1 || title.indexOf('pause') !== -1 ||
      title.indexOf('seek') !== -1 || title.indexOf('full') !== -1;
  }

  function isControlElement(node) {
    var target = node;
    while (target && target !== document.documentElement) {
      var cls = (target.className || '').toString();
      var tag = (target.tagName || '').toUpperCase();
      var id  = (target.id || '').toString();
      if (
        /jw-icon|jw-button|jw-controlbar|jw-controls|jw-slider|jw-knob|jw-display|jw-display-icon|jw-display-container|jw-icon-display|jw-icon-rewind|jw-icon-playback|jw-icon-forward|jw-icon-fullscreen|jw-icon-volume|jw-icon-settings|jw-icon-cc|jw-icon-cast/i.test(cls) ||
        /vjs-control|vjs-slider|vjs-big-play|vjs-play-control|vjs-volume|vjs-fullscreen|vjs-menu|vjs-time|vjs-progress/i.test(cls) ||
        /plyr__control|plyr__controls|plyr__progress|plyr__time|plyr__volume|plyr__menu/i.test(cls) ||
        /dplayer-controller|dplayer-bar|dplayer-icons|dplayer-setting|dplayer-volume/i.test(cls) ||
        /mejs__controls|mejs__button|mejs__playpause|mejs__time|mejs__volume/i.test(cls) ||
        /controlbar|control-bar|controls|progress-bar|seekbar|seek-bar|playback|toolbar/i.test(cls) ||
        /jw-|vjs-|plyr/i.test(id) ||
        tag === 'BUTTON' || tag === 'INPUT' || tag === 'A' ||
        tag === 'SELECT' || tag === 'TEXTAREA' || tag === 'LABEL' ||
        tag === 'SUMMARY' || tag === 'SVG' || tag === 'PATH' ||
        tag === 'USE' || tag === 'G' || tag === 'CIRCLE' ||
        tag === 'RECT' || tag === 'POLYGON' || tag === 'POLYLINE' ||
        hasInteractiveHints(target)
      ) { return true; }
      target = target.parentElement;
    }
    return false;
  }

  function askShowControls() {
    try { if (window.__asdShowControls) window.__asdShowControls(); } catch(e) {}
    try { if (window.top && window.top.__asdShowControls) window.top.__asdShowControls(); } catch(e) {}
  }

  function askKeepFullscreen() {
    try { if (window.__asdForceFullscreenNow) window.__asdForceFullscreenNow(); } catch(e) {}
    try { if (window.top && window.top.__asdForceFullscreenNow) window.top.__asdForceFullscreenNow(); } catch(e) {}
  }

  function syncTapKind(kind) {
    _lastTouchKind = kind;
    try { window.__asdLastTapKind = kind; if (window.top) window.top.__asdLastTapKind = kind; } catch(e) {}
  }

  document.addEventListener('touchstart', function(e) {
    _lastTouchTime = Date.now();
    _touchPauseBlocked = false;
    if (!isInForcedFs()) return;
    if (isControlElement(e.target)) { syncTapKind('control'); askShowControls(); return; }
    var tag = e.target ? (e.target.tagName || '').toUpperCase() : '';
    if (tag === 'VIDEO') { syncTapKind('surface'); askShowControls(); return; }
    syncTapKind('other');
  }, { passive: true, capture: true });

  document.addEventListener('pointerdown', function(e) {
    _lastTouchTime = Date.now();
    _touchPauseBlocked = false;
    if (!isInForcedFs()) return;
    if (isControlElement(e.target)) { syncTapKind('control'); askShowControls(); return; }
    var tag = e.target ? (e.target.tagName || '').toUpperCase() : '';
    if (tag === 'VIDEO') { syncTapKind('surface'); askShowControls(); return; }
    syncTapKind('other');
  }, { passive: true, capture: true });

  try {
    var proto = window.HTMLMediaElement && window.HTMLMediaElement.prototype;
    if (proto && !proto._asdAutoResumePatch) {
      proto._asdAutoResumePatch = true;
      var _origPause = proto.pause;
      proto.pause = function() {
        var self = this;
        var result;
        try { result = _origPause ? _origPause.apply(self, arguments) : undefined; } catch(e) {}
        if (isInForcedFs()) {
          var timeSinceTouch = Date.now() - _lastTouchTime;
          if (timeSinceTouch < 450 && !_touchPauseBlocked && _lastTouchKind === 'surface') {
            _touchPauseBlocked = true;
            setTimeout(function() {
              try {
                if (self.paused && isInForcedFs()) {
                  self.play();
                  askShowControls();
                  askKeepFullscreen();
                }
              } catch(e) {}
              _touchPauseBlocked = false;
            }, 90);
          }
        }
        return result;
      };
    }
  } catch(e) {}

  function blockVideoTap(e) {
    if (!isInForcedFs()) return;
    if (isControlElement(e.target)) {
      syncTapKind('control');
      askShowControls();
      return;
    }
    var tag = e.target ? (e.target.tagName || '').toUpperCase() : '';
    if (tag !== 'VIDEO') { syncTapKind('other'); return; }
    syncTapKind('surface');
    askShowControls();
    askKeepFullscreen();
  }

  document.addEventListener('click',      blockVideoTap, { passive: true, capture: true });
  document.addEventListener('touchend',   blockVideoTap, { passive: true, capture: true });
  document.addEventListener('pointerup',  blockVideoTap, { passive: true, capture: true });
})();
""";

  static const String _dlCapture = r"""
(function(){
  'use strict';

  var dlExts = ['.mp4','.mkv','.avi','.mov','.webm','.m4v'];

  function maybeMedia(url) {
    if (!url || typeof url !== 'string') return null;
    var s = url.trim();
    if (!s || s.indexOf('blob:') === 0) return null;
    var lower = s.toLowerCase();
    if (lower.indexOf('.m3u8')!==-1||lower.indexOf('.mp4')!==-1||
        lower.indexOf('.mkv')!==-1||lower.indexOf('.webm')!==-1||
        lower.indexOf('.m4v')!==-1||
        lower.indexOf('.mov')!==-1||lower.indexOf('.mpd')!==-1||
        lower.indexOf('mime=video')!==-1||lower.indexOf('/playlist')!==-1||
        lower.indexOf('/manifest')!==-1||lower.indexOf('/hls/')!==-1) {
      return s;
    }
    return null;
  }

  function isDlUrl(url) {
    var clean = maybeMedia(url);
    if (!clean) return false;
    var lower = clean.toLowerCase().split('?')[0].split('#')[0];
    return dlExts.some(function(e){ return lower.endsWith(e); });
  }

  function extractName(url) {
    if (!url) return 'video.mp4';
    var parts = url.split('?')[0].split('/');
    var name = parts[parts.length - 1];
    return name && name.length > 0 ? name : 'video.mp4';
  }

  function sendDl(url, name) {
    if (!url || url.length < 5) return;
    try { window.flutter_inappwebview.callHandler('onDownload', { url: url, name: name || extractName(url) }); } catch(e) {}
  }

  function sendVideo(url, mimeType) {
    var clean = maybeMedia(url);
    if (!clean) return;
    try { window.flutter_inappwebview.callHandler('onVideoFound', { url: clean, pageUrl: window.location.href, currentTime: 0, mimeType: mimeType || null }); } catch(e) {}
  }

  document.addEventListener('click', function(e) {
    var el = e.target;
    while (el && el !== document) {
      if (el.tagName === 'A' || el.tagName === 'BUTTON') break;
      el = el.parentElement;
    }
    if (!el || el === document) return;
    var href = el.href || el.getAttribute('data-url') || el.getAttribute('data-link') ||
               el.getAttribute('data-src') || el.getAttribute('data-file') || '';
    if (href && isDlUrl(href)) {
      e.preventDefault(); e.stopPropagation();
      sendDl(href, el.getAttribute('download') || extractName(href));
      return;
    }
    sendVideo(href, null);
  }, true);

  var origFetch = window.fetch;
  if (origFetch && !window.__asdFetchPatched) {
    window.__asdFetchPatched = true;
    window.fetch = function(input, init) {
      var url = '';
      if (typeof input === 'string') url = input;
      else if (input && input.url) url = input.url;
      sendVideo(url, null);
      if (isDlUrl(url)) sendDl(url, extractName(url));
      return origFetch.call(window, input, init).then(function(response) {
        var resUrl = response.url || url;
        var mime = null;
        try { mime = response.headers && response.headers.get ? response.headers.get('content-type') : null; } catch(e) {}
        sendVideo(resUrl, mime);
        if (isDlUrl(resUrl)) sendDl(resUrl, extractName(resUrl));
        return response;
      });
    };
  }

  try {
    if (!XMLHttpRequest.prototype._asdPatched) {
      XMLHttpRequest.prototype._asdPatched = true;
      var _open = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        this._asdUrl = url;
        sendVideo(url, null);
        return _open.apply(this, arguments);
      };
      var _send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function() {
        this.addEventListener('readystatechange', function() {
          if (this.readyState === 2 || this.readyState === 4) {
            var mime = null;
            try { mime = this.getResponseHeader('content-type'); } catch(e) {}
            sendVideo(this.responseURL || this._asdUrl, mime);
          }
        });
        return _send.apply(this, arguments);
      };
    }
  } catch(e) {}
})();
""";

  static const String _networkMediaProbe = r"""
(function(){
  'use strict';
  if (window.__asdNetProbeInstalled) return;
  window.__asdNetProbeInstalled = true;

  function isMedia(url) {
    if (!url || typeof url !== 'string') return false;
    var s = url.toLowerCase();
    if (s.indexOf('blob:') === 0) return false;
    if (/\.ts(?:$|[?#])/.test(s) && s.indexOf('.m3u8') === -1) return false;
    return s.indexOf('.m3u8') !== -1 ||
           s.indexOf('.mpd') !== -1 ||
           s.indexOf('.mp4') !== -1 ||
           s.indexOf('.mkv') !== -1 ||
           s.indexOf('.webm') !== -1 ||
           s.indexOf('.m4v') !== -1 ||
           s.indexOf('.mov') !== -1 ||
           s.indexOf('.avi') !== -1 ||
           s.indexOf('/manifest') !== -1 ||
           s.indexOf('/playlist') !== -1 ||
           s.indexOf('/hls/') !== -1 ||
           s.indexOf('mime=video') !== -1;
  }

  function notify(url, mime) {
    if (!isMedia(url)) return;
    try {
      window.flutter_inappwebview.callHandler('onVideoFound', {
        url: url,
        pageUrl: window.location.href,
        currentTime: 0,
        mimeType: mime || null
      });
    } catch(e) {}
  }

  try {
    var origFetch = window.fetch;
    if (origFetch && !window.__asdFetchMediaProbe) {
      window.__asdFetchMediaProbe = true;
      window.fetch = function(input, init) {
        var url = '';
        if (typeof input === 'string') url = input;
        else if (input && input.url) url = input.url;
        notify(url, null);
        return origFetch.call(this, input, init).then(function(res){
          var resUrl = res && res.url ? res.url : url;
          var mime = null;
          try { mime = res.headers.get('content-type'); } catch(e) {}
          notify(resUrl, mime);
          return res;
        });
      };
    }
  } catch(e) {}

  try {
    if (!XMLHttpRequest.prototype.__asdMediaPatched) {
      XMLHttpRequest.prototype.__asdMediaPatched = true;
      var origOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__asdUrl = url;
        notify(url, null);
        return origOpen.apply(this, arguments);
      };

      var origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function() {
        this.addEventListener('readystatechange', function() {
          if (this.readyState === 2 || this.readyState === 4) {
            var mime = null;
            try { mime = this.getResponseHeader('content-type'); } catch(e) {}
            notify(this.responseURL || this.__asdUrl, mime);
          }
        });
        return origSend.apply(this, arguments);
      };
    }
  } catch(e) {}
})();
""";


  static const String _captureOptions = r"""
(function(){
  'use strict';
  if (window.__asdCaptureOptionsApp) return;
  window.__asdCaptureOptionsApp = true;
  function fl(name, value) {
    try { window.flutter_inappwebview.callHandler(name, value); } catch(e) {}
  }
  function cleanText(v){ return (v || '').replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim(); }
  function qualityLabelFromText(text) {
    text = (text || '').replace(/\s+/g, ' ').trim();
    var m = text.match(/(2160|1440|1080|720|540|480|360|240)\s*p?/i);
    return m ? (m[1] + 'p') : null;
  }
  function collectSubtitles() {
    var out = [], seen = {};
    function push(item) {
      if (!item || !item.url) return;
      var sig = ((item.label || '') + '|' + (item.url || '')).toLowerCase();
      if (seen[sig]) return;
      seen[sig] = true;
      out.push(item);
    }
    function inferMime(u) {
      var s = (u || '').toLowerCase();
      if (s.indexOf('.vtt') !== -1) return 'text/vtt';
      if (s.indexOf('.srt') !== -1) return 'application/x-subrip';
      if (s.indexOf('.ass') !== -1 || s.indexOf('.ssa') !== -1) return 'text/x-ssa';
      if (s.indexOf('.ttml') !== -1 || s.indexOf('.xml') !== -1) return 'application/ttml+xml';
      return '';
    }
    document.querySelectorAll('track[kind="subtitles"], track[kind="captions"]').forEach(function(t) {
      var url = (t.src || t.getAttribute('src') || '').trim();
      if (!url) return;
      var lang = (t.srclang || t.getAttribute('srclang') || '').trim();
      var label = (t.label || t.getAttribute('label') || lang || 'Subtitle').trim();
      push({ label: label, url: url, language: lang, source: 'HTML track', mimeType: inferMime(url) });
    });
    document.querySelectorAll('[data-subtitle],[data-sub],[data-caption],[data-track]').forEach(function(el) {
      var url = (el.getAttribute('data-subtitle') || el.getAttribute('data-sub') || el.getAttribute('data-caption') || el.getAttribute('data-track') || '').trim();
      if (!url) return;
      var lang = (el.getAttribute('data-lang') || el.getAttribute('srclang') || '').trim();
      var label = (el.getAttribute('data-label') || el.getAttribute('title') || el.getAttribute('aria-label') || el.textContent || lang || 'Subtitle').trim();
      push({ label: label, url: url, language: lang, source: 'DOM', mimeType: inferMime(url) });
    });
    try {
      document.querySelectorAll('video').forEach(function(v){
        var tracks = v.textTracks || [];
        for (var i = 0; i < tracks.length; i++) {
          var t = tracks[i];
          var raw = (t && (t.src || (t.track && t.track.src))) || '';
          if (!raw) continue;
          var lang = (t.language || t.srclang || '').trim();
          var label = (t.label || lang || 'Subtitle').trim();
          push({ label: label, url: raw, language: lang, source: 'TextTrack', mimeType: inferMime(raw) });
        }
      });
    } catch(e) {}
    return out;
  }
  function collectQualityOptions() {
    var out = [], seen = {};
    var nodes = document.querySelectorAll('a,button,li,div,span,[class*="quality"],[data-quality]');
    nodes.forEach(function(el) {
      if (!el.textContent) return;
      var label = qualityLabelFromText((el.textContent || '') + ' ' + (el.getAttribute('title') || '') + ' ' + (el.getAttribute('aria-label') || '') + ' ' + (el.getAttribute('data-quality') || ''));
      if (!label) return;
      var href = cleanText(el.href || el.getAttribute('data-url') || el.getAttribute('data-link') || el.getAttribute('data-src') || el.getAttribute('href') || '');
      var key = (href || label + '_' + out.length).replace(/[^a-zA-Z0-9_:\/\.\-]/g,'_');
      var cls = ((el.className || '') + ' ' + ((el.parentElement && el.parentElement.className) || '')).toLowerCase();
      var selected = /active|current|selected|checked/.test(cls) || (el.getAttribute('aria-current') === 'true' || el.getAttribute('aria-selected') === 'true');
      try { el.setAttribute('data-asd-quality-key', key); } catch(e) {}
      var uniq = (label + '|' + href).toLowerCase();
      if (seen[uniq]) return;
      seen[uniq] = true;
      out.push({ label: label, key: key, url: href || '', selected: selected });
    });
    return out;
  }
  function collectServerOptions() {
    var out = [], seen = {};
    var selectors = ['[class*="server"] button','[class*="server"] a','[class*="source"] button','[class*="source"] a','[data-server]','[data-source]','[data-embed]','[data-testid*="server"]','button[aria-label*="server" i]','.servers button','.servers a','.server-list button','.server-list a','.sources button','.sources a','.jw-settings-submenu button','.jw-settings-content-item','[class*="player"] button[data-id]','[class*="player"] button[data-link]','[class*="player"] button[data-url]'];
    var serverKeywords = ['server','srv','source','oxygen','ares','balder','circe','gaia','orion','upcloud','vidsrc','rabbitstream','megacloud','filemoon','streamwish','mixdrop','streamtape','uqload','voe','السيرفر','مصدر'];
    function scoreAsServer(el) {
      var txt = cleanText((el.textContent || '') + ' ' + (el.getAttribute('data-name') || '') + ' ' + (el.getAttribute('data-server') || '') + ' ' + (el.getAttribute('title') || '') + ' ' + (el.getAttribute('aria-label') || '')).toLowerCase();
      if (!txt || txt.length > 80) return 0;
      return serverKeywords.some(function(k){ return txt.indexOf(k) !== -1; }) ? 3 : 0;
    }
    selectors.forEach(function(sel) {
      try {
        document.querySelectorAll(sel).forEach(function(el) {
          var label = cleanText((el.getAttribute('data-name') || el.getAttribute('data-server') || el.getAttribute('title') || el.getAttribute('aria-label') || el.innerText || el.textContent || '').substring(0,60));
          if (!label || /^(servers?|sources?)$/i.test(label)) return;
          var link = cleanText(el.href || el.getAttribute('data-link') || el.getAttribute('data-url') || el.getAttribute('data-embed') || el.getAttribute('data-src') || el.getAttribute('data-id') || '');
          var key = 'srv_' + label.replace(/[^a-zA-Z0-9_-]/g,'') + '_' + out.length;
          try { el.setAttribute('data-asd-srv-key', key); } catch(e) {}
          var cls = ((el.className || '') + ' ' + ((el.parentElement && el.parentElement.className) || '')).toLowerCase();
          var selected = /active|current|selected|on\b/.test(cls) || el.getAttribute('aria-current') === 'true' || el.getAttribute('aria-selected') === 'true';
          var uniq = (label + '|' + link).toLowerCase();
          if (seen[uniq]) return;
          seen[uniq] = true;
          out.push({ label: label, key: key, embedUrl: link, selected: selected });
        });
      } catch(e) {}
    });
    if (out.length < 2) {
      var allBtns = document.querySelectorAll('button, a, li, div[role="button"]');
      allBtns.forEach(function(el) {
        if (scoreAsServer(el) < 1) return;
        var label = cleanText(el.getAttribute('data-name') || el.getAttribute('title') || el.getAttribute('aria-label') || el.innerText || el.textContent || '').substring(0,60);
        if (!label || /^(servers?|sources?)$/i.test(label)) return;
        var link = cleanText(el.href || el.getAttribute('data-link') || el.getAttribute('data-url') || el.getAttribute('data-embed') || '');
        var key = 'srv_' + label.replace(/[^a-zA-Z0-9_-]/g,'') + '_' + out.length;
        try { el.setAttribute('data-asd-srv-key', key); } catch(e) {}
        var cls = ((el.className || '') + ' ' + ((el.parentElement && el.parentElement.className) || '')).toLowerCase();
        var selected = /active|current|selected|on\b/.test(cls);
        var uniq = (label + '|' + link).toLowerCase();
        if (seen[uniq]) return;
        seen[uniq] = true;
        out.push({ label: label, key: key, embedUrl: link, selected: selected });
      });
    }
    return out;
  }
  function sendOptionsUpdate() {
    var qualityOptions = collectQualityOptions();
    var serverOptions = collectServerOptions();
    var subtitleTracks = collectSubtitles();
    if (qualityOptions.length > 0) {
      var current = null;
      qualityOptions.forEach(function(o){ if (o.selected && !current) current = o.label; });
      if (!current && qualityOptions.length > 0) current = qualityOptions[0].label;
      fl('onQualityOptions', { options: qualityOptions, current: current });
    }
    if (serverOptions.length > 0) {
      var currentSrv = null;
      serverOptions.forEach(function(o){ if (o.selected && !currentSrv) currentSrv = o.label; });
      if (!currentSrv && serverOptions.length > 0) currentSrv = serverOptions[0].label;
      fl('onServerOptions', { options: serverOptions, current: currentSrv });
    }
    if (subtitleTracks.length > 0) {
      fl('onSubtitleTracks', { tracks: subtitleTracks });
    }
  }
  window.__asdCollectOptions = sendOptionsUpdate;
  window.__asdSelectServerOption = function(key, label, url) {
    try {
      var byKey = key ? document.querySelector('[data-asd-srv-key="' + String(key).replace(/"/g,'\\"') + '"]') : null;
      if (byKey) { triggerClick(byKey); setTimeout(sendOptionsUpdate, 350); setTimeout(sendOptionsUpdate, 900); return true; }
      var nodes = document.querySelectorAll('button,a,li,div[role="button"]');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        var txt = cleanText(el.getAttribute('data-name') || el.getAttribute('title') || el.textContent || '');
        var href = cleanText(el.href || el.getAttribute('data-link') || el.getAttribute('data-url') || el.getAttribute('data-embed') || '');
        if ((label && txt === label) || (url && href === url)) { triggerClick(el); setTimeout(sendOptionsUpdate, 350); setTimeout(sendOptionsUpdate, 900); return true; }
      }
    } catch(e) {}
    return false;
  };
  setTimeout(sendOptionsUpdate, 800);
  setTimeout(sendOptionsUpdate, 2000);
  setTimeout(sendOptionsUpdate, 4000);
  try {
    new MutationObserver(function(muts) {
      var hasNew = muts.some(function(m){ return m.addedNodes.length > 0 || m.type === 'attributes'; });
      if (hasNew) setTimeout(sendOptionsUpdate, 500);
    }).observe(document.body || document.documentElement, {childList:true, subtree:true, attributes:true, attributeFilter:['class','style','aria-selected','aria-current','data-link','data-url']});
  } catch(e) {}
  setInterval(sendOptionsUpdate, 5000);
})();
""";

  static const String _interceptSourceApi = r"""
(function(){
  'use strict';
  if (window.__asdSourceApiInterceptorApp) return;
  window.__asdSourceApiInterceptorApp = true;
  function fl(name, value) {
    try { window.flutter_inappwebview.callHandler(name, value); } catch(e) {}
  }
  function cleanText(v) {
    return (v || '').toString().replace(/\s+/g, ' ').trim();
  }
  function isStreamingUrl(url) {
    if (!url) return false;
    var s = (url + '').toLowerCase();
    if (s.indexOf('youtube') !== -1 || s.indexOf('youtu.be') !== -1 || s.indexOf('dailymotion') !== -1 || s.indexOf('vimeo') !== -1 || s.indexOf('imdb') !== -1) return false;
    return s.indexOf('.m3u8') !== -1 ||
      s.indexOf('.mpd') !== -1 ||
      s.indexOf('/hls/') !== -1 ||
      s.indexOf('/playlist') !== -1 ||
      s.indexOf('/manifest') !== -1 ||
      s.indexOf('mime=video') !== -1 ||
      s.indexOf('contenttype=video') !== -1 ||
      s.indexOf('.mp4') !== -1 ||
      s.indexOf('.webm') !== -1 ||
      s.indexOf('.mkv') !== -1 ||
      s.indexOf('10017.workers.dev') !== -1 ||
      s.indexOf('megafiles.store') !== -1;
  }
  function samevidfast(url) {
    try {
      var u = new URL(url, window.location.href);
      return u.host === window.location.host && (u.host.indexOf('videasy.net') !== -1 || u.host.indexOf('player.videasy.net') !== -1 || u.host.indexOf('vidfast.pro') !== -1);
    } catch(e) {
      return false;
    }
  }
  function looksLikeServerishUrl(url) {
    var s = (url || '').toLowerCase();
    if (!s) return false;
    return s.indexOf('10017.workers.dev') !== -1 ||
      s.indexOf('megafiles.store') !== -1 ||
      s.indexOf('rainorbit') !== -1 ||
      s.indexOf('nightbreeze') !== -1 ||
      s.indexOf('quietlynx') !== -1 ||
      s.indexOf('videasy.net') !== -1 ||
      s.indexOf('player.videasy.net') !== -1 ||
      s.indexOf('vidfast.pro') !== -1 ||
      s.indexOf('/embed/') !== -1 ||
      s.indexOf('/source') !== -1 ||
      s.indexOf('/sources') !== -1;
  }
  function looksLikeSourceApi(url, method) {
    var u = (url || '').toLowerCase();
    var m = (method || '').toLowerCase();
    if (!u) return false;
    if (u.indexOf('/source') !== -1 || u.indexOf('/sources') !== -1 || u.indexOf('/api/') !== -1 || u.indexOf('.json') !== -1) return true;
    if ((u.indexOf('videasy.net') !== -1 || u.indexOf('player.videasy.net') !== -1 || u.indexOf('vidfast.pro') !== -1) && (m === 'post' || u.indexOf('/api/') !== -1)) return true;
    return false;
  }
  function qualityLabel(v) {
    var s = cleanText(v);
    var m = s.match(/(2160|1440|1080|720|540|480|360|240)\/?p?/i);
    return m ? (m[1] + 'p') : s;
  }
  function providerFrom(url) {
    try {
      var h = new URL(url, window.location.href).host.toLowerCase();
      var p = h.split('.');
      return (p.length > 1 ? p[p.length - 2] : p[0]) || 'Server';
    } catch(e) {
      return 'Server';
    }
  }
  function pushUnique(arr, item) {
    var sig = ((item.label || '') + '|' + ((item.embedUrl || item.url || ''))).toLowerCase();
    for (var i = 0; i < arr.length; i++) {
      var cur = ((arr[i].label || '') + '|' + ((arr[i].embedUrl || arr[i].url || ''))).toLowerCase();
      if (cur === sig) return;
    }
    arr.push(item);
  }
  function emitBundle(qualityOptions, serverOptions, subtitleTracks) {
    if (!qualityOptions.length && !serverOptions.length && !subtitleTracks.length) return;
    fl('onSourceBundle', {
      qualityOptions: qualityOptions,
      currentQualityLabel: qualityOptions.length ? qualityOptions[0].label : '',
      serverOptions: serverOptions,
      currentServerLabel: serverOptions.length ? serverOptions[0].label : '',
      subtitleTracks: subtitleTracks,
    });
  }
  function parseSourceBundle(data, requestUrl) {
    var qualityOptions = [], serverOptions = [], subtitleTracks = [];
    function walk(node) {
      if (!node) return;
      if (Array.isArray(node)) { node.forEach(walk); return; }
      if (typeof node !== 'object') return;
      var mediaUrl = node.file || node.src || node.url || node.stream || node.playlist || node.hls || node.m3u8 || node.link || '';
      if (typeof mediaUrl === 'string' && mediaUrl && isStreamingUrl(mediaUrl)) {
        fl('onVideoFound', { url: mediaUrl, pageUrl: window.location.href, currentTime: 0, mimeType: null });
        var q = qualityLabel(node.label || node.quality || node.resolution || '');
        if (q && q.length > 0) {
          pushUnique(qualityOptions, { label: q, key: q + '_' + qualityOptions.length, url: mediaUrl, selected: qualityOptions.length === 0 });
        }
        var srv = cleanText(node.server || node.source || node.provider || node.name || node.title || providerFrom(mediaUrl) || 'Server');
        if (srv) {
          pushUnique(serverOptions, { label: srv, key: srv.replace(/[^a-zA-Z0-9_-]/g, '') + '_' + serverOptions.length, embedUrl: mediaUrl, selected: serverOptions.length === 0 });
        }
      }
      var subs = node.subtitles || node.subtitle || node.tracks || node.captions || null;
      if (Array.isArray(subs)) {
        subs.forEach(function(t) {
          if (!t || typeof t !== 'object') return;
          var u = (t.file || t.src || t.url || '').toString();
          if (!u) return;
          var lbl = (t.label || t.lang || t.language || t.srclang || 'Subtitle').toString();
          var lang = (t.lang || t.language || t.srclang || '').toString().trim();
          var mime = (t.type || t.mimeType || '').toString().trim();
          if (!mime) {
            var lu = u.toLowerCase();
            if (lu.indexOf('.vtt') !== -1) mime = 'text/vtt';
            else if (lu.indexOf('.srt') !== -1) mime = 'application/x-subrip';
            else if (lu.indexOf('.ass') !== -1 || lu.indexOf('.ssa') !== -1) mime = 'text/x-ssa';
            else if (lu.indexOf('.ttml') !== -1 || lu.indexOf('.xml') !== -1) mime = 'application/ttml+xml';
          }
          subtitleTracks.push({ label: lbl, url: u, language: lang, source: 'Source API', mimeType: mime });
        });
      }
      Object.keys(node).forEach(function(k) {
        if (['subtitles', 'subtitle', 'tracks', 'captions'].indexOf(k) !== -1) return;
        var v = node[k];
        if (v && typeof v === 'object') walk(v);
      });
    }
    walk(data);
    emitBundle(qualityOptions, serverOptions, subtitleTracks);
    return qualityOptions.length > 0 || serverOptions.length > 0 || subtitleTracks.length > 0;
  }
  function extractUrlsFromText(txt) {
    var out = [];
    if (!txt || typeof txt !== 'string') return out;
    var norm = txt.replace(/\\\//g, '/').replace(/&amp;/g, '&');
    var re = /https?:\/\/[^\s"'<>\\]+/g;
    var m;
    while ((m = re.exec(norm)) !== null) {
      var u = (m[0] || '').replace(/[)\],;]+$/g, '').trim();
      if (u) out.push(u);
    }
    return out;
  }
  function parsePotentialResponseText(txt, requestUrl, method) {
    if (!txt || typeof txt !== 'string') return false;
    try {
      if (looksLikeSourceApi(requestUrl, method)) {
        window.__asdLastSourceApiUrl = requestUrl;
      }
    } catch(e) {}
    var hit = false;
    try {
      if (parseSourceBundle(JSON.parse(txt), requestUrl)) hit = true;
    } catch(e) {}
    var qualityOptions = [], serverOptions = [];
    extractUrlsFromText(txt).forEach(function(u) {
      if (isStreamingUrl(u)) {
        hit = true;
        fl('onVideoFound', { url: u, pageUrl: window.location.href, currentTime: 0, mimeType: null });
        pushUnique(serverOptions, { label: providerFrom(u), key: providerFrom(u).replace(/[^a-zA-Z0-9_-]/g, '') + '_' + serverOptions.length, embedUrl: u, selected: serverOptions.length === 0 });
      } else if (looksLikeServerishUrl(u)) {
        hit = true;
        pushUnique(serverOptions, { label: providerFrom(u), key: providerFrom(u).replace(/[^a-zA-Z0-9_-]/g, '') + '_' + serverOptions.length, embedUrl: u, selected: serverOptions.length === 0 });
      }
    });
    if (!hit && !looksLikeSourceApi(requestUrl, method) && !samevidfast(requestUrl)) return false;
    emitBundle(qualityOptions, serverOptions, []);
    return hit || serverOptions.length > 0;
  }
  window.__asdFetchAndParseSourceBundle = async function(url) {
    try {
      if (!url) return false;
      var response = await fetch(url, {
        credentials: 'include',
        cache: 'no-store',
        headers: {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
          'Accept': 'application/json, text/plain, */*'
        }
      });
      var txt = await response.text();
      return parsePotentialResponseText(txt, response.url || url, 'GET');
    } catch (e) {
      fl('onSourceBundleError', { url: url, error: String(e) });
      return false;
    }
  };
  if (window.fetch && !window.__asdSourceApiFetchApp) {
    window.__asdSourceApiFetchApp = true;
    var origFetch = window.fetch;
    window.fetch = function(input, init) {
      var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      var method = (init && init.method) ? init.method : ((input && input.method) ? input.method : 'GET');
      return origFetch.call(window, input, init).then(function(response) {
        var finalUrl = response.url || url;
        try {
          if (looksLikeSourceApi(finalUrl, method)) {
            window.__asdLastSourceApiUrl = finalUrl;
          }
        } catch(e) {}
        var contentType = '';
        try { contentType = (response.headers && response.headers.get && response.headers.get('content-type')) || ''; } catch(e) {}
        if (looksLikeSourceApi(finalUrl, method) || samevidfast(finalUrl) || /json|text|xml/i.test(contentType)) {
          try {
            response.clone().text().then(function(txt) {
              try { parsePotentialResponseText(txt, finalUrl, method); } catch(e) {}
            }).catch(function(){});
          } catch(e) {}
        }
        return response;
      });
    };
  }
  if (!window.__asdSourceApiXHRApp) {
    window.__asdSourceApiXHRApp = true;
    var _open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      this._asdSourceMethod = method || 'GET';
      this._asdSourceUrl = url;
      return _open.apply(this, arguments);
    };
    var _send = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function() {
      this.addEventListener('readystatechange', function() {
        if (this.readyState !== 4) return;
        var finalUrl = this.responseURL || this._asdSourceUrl || '';
        var method = this._asdSourceMethod || 'GET';
        try {
          if (looksLikeSourceApi(finalUrl, method)) {
            window.__asdLastSourceApiUrl = finalUrl;
          }
        } catch(e) {}
        var contentType = '';
        try { contentType = this.getResponseHeader('content-type') || ''; } catch(e) {}
        if (looksLikeSourceApi(finalUrl, method) || samevidfast(finalUrl) || /json|text|xml/i.test(contentType)) {
          try {
            var txt = typeof this.responseText === 'string' ? this.responseText : '';
            if (txt) parsePotentialResponseText(txt, finalUrl, method);
          } catch(e) {}
        }
      });
      return _send.apply(this, arguments);
    };
  }
})();
""";

  static const String _smartVideasyPlayClick = r"""
(function () {
  'use strict';
  if (window.__asdSmartPlayInstalled) return;
  window.__asdSmartPlayInstalled = true;

  var MAX_ATTEMPTS  = 28;
  var INTERVAL_MS   = 380;
  var GIVE_UP_MS    = 12000;

  function isVisible(el) {
    if (!el) return false;
    try {
      var r = el.getBoundingClientRect();
      if (r.width < 4 || r.height < 4) return false;
      if (r.bottom < 0 || r.right < 0) return false;
      if (r.top > window.innerHeight + 40) return false;
      if (r.left > window.innerWidth + 40) return false;
      var st = window.getComputedStyle(el);
      if (st.display === 'none') return false;
      if (st.visibility === 'hidden') return false;
      if (parseFloat(st.opacity || '1') < 0.05) return false;
    } catch (e) { return false; }
    return true;
  }

  function distFromCenter(el) {
    try {
      var r = el.getBoundingClientRect();
      var cx = r.left + r.width  / 2;
      var cy = r.top  + r.height / 2;
      var dx = cx - window.innerWidth  / 2;
      var dy = cy - window.innerHeight / 2;
      return Math.sqrt(dx * dx + dy * dy);
    } catch (e) { return 9999; }
  }

  function scoreEl(el) {
    if (!isVisible(el)) return -1;
    var score = 0;
    var tag  = (el.tagName  || '').toUpperCase();
    var cls  = (el.className || el.getAttribute('class') || '').toString().toLowerCase();
    var id   = (el.id        || '').toString().toLowerCase();
    var aria = (el.getAttribute('aria-label') || '').toLowerCase();
    var title= (el.getAttribute('title')       || '').toLowerCase();
    var role = (el.getAttribute('role')        || '').toLowerCase();
    var txt  = ((el.textContent || el.innerText || '') + ' ' + aria + ' ' + title)
                 .replace(/\s+/g,' ').trim().toLowerCase();

    if (/vjs-big-play-button/.test(cls))             score += 200;
    if (/jw-icon-display|jw-display-icon/.test(cls)) score += 200;
    if (/plyr__control--overlaid/.test(cls))          score += 200;
    if (/dplayer-play-icon|dplayer-bezel/.test(cls)) score += 180;

    if (/play-btn|play_btn|playbtn/.test(cls + id))  score += 160;
    if (/play-button|playbutton/.test(cls + id))     score += 150;
    if (/start-btn|startbtn/.test(cls + id))         score += 130;
    if (role === 'button' && /play|watch/.test(aria))score += 140;

    try {
      var svgs = el.querySelectorAll('svg, path, polygon');
      if (svgs.length > 0) score += 30;
    } catch (e) {}

    if (/^play$|^▶$|^►$|^تشغيل$/.test(txt.trim())) score += 120;
    if (/play|watch|stream|مشاهدة|ابدأ/.test(txt))  score += 50;

    if (tag === 'BUTTON') score += 25;
    if (tag === 'A')      score += 10;

    if (/trailer|teaser|إعلان/.test(txt))  score -= 200;
    if (/skip|ad|banner/.test(cls + id))   score -= 300;
    if (/download|تحميل/.test(txt))        score -= 150;
    if (/settings|gear|share/.test(cls))   score -= 100;

    var dist = distFromCenter(el);
    score -= dist / 20;

    return score;
  }

  function fireClick(el) {
    try {
      var r   = el.getBoundingClientRect();
      var cx  = r.left + r.width  / 2;
      var cy  = r.top  + r.height / 2;
      var hit = document.elementFromPoint(cx, cy) || el;
      var opts = {
        bubbles: true, cancelable: true, composed: true,
        view: window, button: 0, buttons: 1,
        clientX: cx, clientY: cy,
        screenX: cx, screenY: cy
      };
      ['pointerover','pointerenter','pointerdown',
       'mousedown','pointerup','mouseup','click'].forEach(function (evt) {
        try {
          var Cls = evt.startsWith('pointer') ? PointerEvent : MouseEvent;
          hit.dispatchEvent(new Cls(evt, opts));
        } catch (e) {}
      });
      try { hit.click(); } catch (e) {}
    } catch (e) {}
  }

  function findBestPlayTarget() {
    var selectors = [
      '.vjs-big-play-button',
      '.jw-icon-display',
      '.jw-display-icon-container',
      '.plyr__control--overlaid',
      '.dplayer-play-icon',
      '.dplayer-bezel-icon',
      '[class*="play-btn"]',
      '[class*="play-button"]',
      '[class*="playbtn"]',
      '[class*="playButton"]',
      '[id*="play-btn"]',
      '[id*="playBtn"]',
      'button[aria-label*="play" i]',
      'button[aria-label*="تشغيل"]',
      'button[title*="play" i]',
      '[role="button"][aria-label*="play" i]',
      '[data-testid*="play" i]',
      '[data-icon="play"]',
      'button',
      '[role="button"]',
      'div[tabindex="0"]',
      'span[tabindex="0"]',
      'a[href="#"]'
    ];

    var best = null;
    var bestScore = 20;

    selectors.forEach(function (sel) {
      try {
        document.querySelectorAll(sel).forEach(function (el) {
          var s = scoreEl(el);
          if (s > bestScore) { bestScore = s; best = el; }
        });
      } catch (e) {}
    });

    if (!best) {
      var player = document.querySelector(
        'video, .jwplayer, .video-js, .plyr, .dplayer, ' +
        '[class*="player"], [id*="player"], iframe[src]'
      );
      if (player && isVisible(player)) best = player;
    }

    return best;
  }

  var attempts = 0;
  var startTime = Date.now();
  var clicked   = false;

  function attempt() {
    if (clicked)                          return;
    if (Date.now() - startTime > GIVE_UP_MS) return;
    if (attempts++ >= MAX_ATTEMPTS)       return;

    try {
      var vids = document.querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) {
        if (!vids[i].paused && !vids[i].ended && vids[i].readyState >= 2) {
          clicked = true;
          return;
        }
      }
    } catch (e) {}

    var target = findBestPlayTarget();
    if (!target) {
      setTimeout(attempt, INTERVAL_MS);
      return;
    }

    fireClick(target);
    clicked = true;

    setTimeout(function () {
      var playing = false;
      try {
        document.querySelectorAll('video').forEach(function (v) {
          if (!v.paused && !v.ended && v.readyState >= 2) playing = true;
        });
      } catch (e) {}
      if (!playing) {
        clicked = false;
        setTimeout(attempt, INTERVAL_MS);
      }
    }, 600);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { setTimeout(attempt, 200); });
  } else {
    setTimeout(attempt, 100);
  }

  try {
    new MutationObserver(function (muts) {
      if (clicked) return;
      var hasNew = muts.some(function (m) { return m.addedNodes.length > 0; });
      if (hasNew) setTimeout(attempt, 150);
    }).observe(document.body || document.documentElement, {
      childList: true, subtree: true
    });
  } catch (e) {}

  window.__asdSmartPlay = attempt;
})();
""";

  // ─────────────────────────────────────────────────────────────────────────

  String _normalizeServerLabel(String input) => input.trim();

  StreamingSource _preferredAppSource() {
    final active = (_activeAppSourceName ?? '').trim().toLowerCase();
    if (active.isNotEmpty) {
      for (final source in kStreamingSources) {
        if (source.name.trim().toLowerCase() == active) return source;
      }
    }

    final current = (_currentServerLabel ?? '').trim().toLowerCase();
    if (current.isNotEmpty) {
      for (final source in kStreamingSources) {
        if (source.name.trim().toLowerCase() == current) return source;
      }
    }

    if (!_didApplyInitialPreferredSource) {
      final preferred = (widget.preferredSourceName ?? 'vidfast').trim().toLowerCase();
      for (final source in kStreamingSources) {
        if (source.name.trim().toLowerCase() == preferred) return source;
      }
      for (final source in kStreamingSources) {
        if (source.name.trim().toLowerCase() == 'vidfast') return source;
      }
    }

    return kStreamingSources.first;
  }


  bool get _hasTmdbContext => widget.tmdbId != null && widget.mediaType != null;

  List<PageServerOption> _buildAppSourceServerOptions() {
    if (!_hasTmdbContext) return const <PageServerOption>[];
    final preferred = _preferredAppSource();
    return kStreamingSources.map((source) {
      final embedUrl = source.buildUrl(
        widget.tmdbId!,
        season: _resolvedNativeMediaType == MediaType.tv ? widget.season : null,
        episode: _resolvedNativeMediaType == MediaType.tv ? widget.episode : null,
      );
      return PageServerOption(
        label: source.name,
        key: 'appsrc_${source.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}',
        embedUrl: embedUrl,
        selected: source.name == preferred.name,
      );
    }).toList(growable: false);
  }

  bool _isAppSourceEmbedUrl(String? url) {
    final value = (url ?? '').toLowerCase();
    if (value.isEmpty) return false;
    return value.contains('vidfast.pro/movie/') || value.contains('www.vidfast.pro/movie/') || value.contains('vidfast.pro/tv/');
  }

  bool _isVideasyServerOption(PageServerOption option) {
    final label = option.label.trim().toLowerCase();
    final key = option.key.trim().toLowerCase();
    final embedUrl = _normalizeBundleEmbedUrl(option.embedUrl).toLowerCase();
    if (key.startsWith('appsrc_')) return true;
    if (_isVidfastDomServerOption(option)) return true;
    if (label == 'videasy' || label.contains('videasy') || label == 'vidfast' || label.contains('vidfast')) return true;
    if (embedUrl.contains('player.videasy.net/movie/') || embedUrl.contains('player.videasy.net/tv/') || embedUrl.contains('vidfast.pro/movie/') || embedUrl.contains('www.vidfast.pro/movie/') || embedUrl.contains('vidfast.pro/tv/')) return true;
    return false;
  }

  List<PageServerOption> _filterVideasyServerOptions(
    Iterable<PageServerOption> options,
  ) {
    final out = options.where(_isVideasyServerOption).toList(growable: false);
    if (out.isNotEmpty) return out;
    return _buildAppSourceServerOptions();
  }

  List<PageServerOption> _mergeServerOptionLists(
    List<PageServerOption> primary,
    List<PageServerOption> secondary,
  ) {
    final seen = <String>{};
    final merged = <PageServerOption>[];
    void addAllOptions(List<PageServerOption> options) {
      for (final opt in options) {
        final label = _normalizeServerLabel(opt.label);
        if (label.isEmpty) continue;
        final key = opt.key.isNotEmpty ? opt.key : '${label}_${merged.length}';
        final embedUrl = (opt.embedUrl ?? '').trim();
        final dedupe = '${label.toLowerCase()}|${embedUrl.toLowerCase()}';
        if (!seen.add(dedupe)) continue;
        merged.add(PageServerOption(
          label: label,
          key: key,
          index: opt.index,
          embedUrl: embedUrl.isEmpty ? null : embedUrl,
          selected: opt.selected,
        ));
      }
    }
    addAllOptions(primary);
    addAllOptions(secondary);
    return _filterVideasyServerOptions(merged);
  }


  String _subtitleMimeFromName(String raw) {
    final value = raw.toLowerCase();
    if (value.endsWith('.vtt')) return 'text/vtt';
    if (value.endsWith('.srt')) return 'application/x-subrip';
    if (value.endsWith('.ass') || value.endsWith('.ssa')) return 'text/x-ssa';
    if (value.endsWith('.ttml') || value.endsWith('.xml')) return 'application/ttml+xml';
    return '';
  }

  int _subtitleLanguageRank(String value) {
    final v = value.toLowerCase();
    if (v == 'ar' || v.startsWith('ar') || v.contains('arab')) return 0;
    if (v == 'en' || v.startsWith('en') || v.contains('engl')) return 1;
    return 2;
  }

  String _subtitleDisplayLanguage(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return 'Unknown';
    final lower = v.toLowerCase();
    switch (lower) {
      case 'ar':
      case 'ara':
      case 'arabic':
        return 'Arabic';
      case 'en':
      case 'eng':
      case 'english':
        return 'English';
      default:
        return v.length <= 3 ? v.toUpperCase() : '${v[0].toUpperCase()}${v.substring(1)}';
    }
  }
  void _maybeRequestSourceBundleFromConsole(String message) {
    return;
  }

  String? _buildVideasySourceBundleApiUrl() {
    if (!_hasTmdbContext) return null;
    final params = <String, String>{
      'mediaType': _resolvedNativeMediaType == MediaType.tv ? 'tv' : 'movie',
      'tmdbId': widget.tmdbId!.toString(),
      'title': (widget.headerTitle ?? '').trim(),
      'seasonId': (widget.season ?? 1).toString(),
      'episodeId': (widget.episode ?? 1).toString(),
      '_t': DateTime.now().millisecondsSinceEpoch.toString(),
    }..removeWhere((key, value) => value.trim().isEmpty);
    return Uri.https('api.videasy.net', '/moviebox/sources-with-title', params).toString();
  }

  List<String> _buildVideasyApiCandidates(String originalUrl) {
    final uri = Uri.tryParse(originalUrl);
    if (uri == null) return [originalUrl];

    final params = Map<String, String>.from(uri.queryParameters);
    params.remove('_t');
    params['_t'] = DateTime.now().millisecondsSinceEpoch.toString();

    final endpoints = <String>[
      'moviebox/sources-with-title',
      'cdn/sources-with-title',
      'myflixerzupcloud/sources-with-title',
      'upcloud/sources-with-title',
    ];

    final candidates = <String>[];
    final seen = <String>{};

    if (seen.add(originalUrl.toLowerCase())) {
      candidates.add(originalUrl);
    }

    for (final endpoint in endpoints) {
      final candidate =
          Uri.https('api.videasy.net', '/$endpoint', params).toString();
      if (seen.add(candidate.toLowerCase())) {
        candidates.add(candidate);
      }
    }

    return candidates;
  }

  Future<Map<String, dynamic>?> _collectFreshVideasyPlaybackCandidate({
    String? preferredQualityLabel,
  }) async {
    final controller = _wc;
    if (controller == null) return null;
    try {
      final raw = await controller.evaluateJavascript(source: r'''
        (function(preferredLabel){
          try {
            function clean(v) { return String(v || '').trim(); }
            function normalizeQuality(v) {
              var m = clean(v).match(/(2160|1440|1080|720|540|480|360|240)\s*p?/i);
              return m ? (m[1] + 'p') : '';
            }
            function maybeMediaUrl(v) {
              var s = clean(v);
              if (!s || s.indexOf('blob:') === 0) return '';
              var lower = s.toLowerCase();
              if (/\.ts(?:$|[?#])/.test(lower) && lower.indexOf('.m3u8') === -1) return '';
              if (lower.indexOf('bold-cdn.') !== -1 && lower.indexOf('workers.dev') !== -1 && lower.indexOf('q=') !== -1) return s;
              if (lower.indexOf('.m3u8') !== -1 || lower.indexOf('.mp4') !== -1 ||
                  lower.indexOf('.mkv') !== -1 || lower.indexOf('.webm') !== -1 ||
                  lower.indexOf('.m4v') !== -1 ||
                  lower.indexOf('.mov') !== -1 || lower.indexOf('.mpd') !== -1 ||
                  lower.indexOf('mime=video') !== -1 || lower.indexOf('/playlist') !== -1 ||
                  lower.indexOf('/manifest') !== -1 || lower.indexOf('/hls/') !== -1) {
                return s;
              }
              return '';
            }
            function candidateFromVideo(v) {
              if (!v) return null;
              var url = maybeMediaUrl(v.currentSrc) || maybeMediaUrl(v.src);
              if (!url) {
                try {
                  var srcs = v.querySelectorAll('source');
                  for (var i = 0; i < srcs.length; i++) {
                    url = maybeMediaUrl(srcs[i].src || srcs[i].getAttribute('src'));
                    if (url) break;
                  }
                } catch(e) {}
              }
              if (!url) return null;
              var lower = url.toLowerCase();
              var label = normalizeQuality(v.getAttribute('data-quality') || v.getAttribute('label') || document.body.innerText || '');
              var mimeType = '';
              if (lower.indexOf('.m3u8') !== -1) mimeType = 'application/x-mpegURL';
              else if (lower.indexOf('.mpd') !== -1) mimeType = 'application/dash+xml';
              else if (lower.indexOf('.mp4') !== -1) mimeType = 'video/mp4';
              return {
                url: url,
                pageUrl: location.href,
                currentTime: isFinite(v.currentTime) ? v.currentTime : 0,
                mimeType: mimeType,
                qualityLabel: label,
                isTransient: lower.indexOf('bold-cdn.') !== -1 && lower.indexOf('workers.dev') !== -1 && lower.indexOf('q=') !== -1,
                from: 'video'
              };
            }
            var preferred = normalizeQuality(preferredLabel || '');
            var candidates = [];
            try {
              document.querySelectorAll('video').forEach(function(v){
                var item = candidateFromVideo(v);
                if (item) candidates.push(item);
              });
            } catch(e) {}
            function score(item) {
              if (!item || !item.url) return -1;
              var s = 0;
              var lower = item.url.toLowerCase();
              if (item.isTransient) s += 60;
              if (lower.indexOf('.m3u8') !== -1) s += 25;
              else if (lower.indexOf('.mp4') !== -1) s += 22;
              else if (lower.indexOf('.mpd') !== -1) s += 20;
              if (preferred && normalizeQuality(item.qualityLabel || '') === preferred) s += 40;
              if (item.from === 'video') s += 10;
              return s;
            }
            candidates.sort(function(a, b){ return score(b) - score(a); });
            return JSON.stringify(candidates.length ? candidates[0] : null);
          } catch (e) {
            return JSON.stringify(null);
          }
        })(${jsonEncode(preferredQualityLabel ?? '')});
      ''');
      if (raw == null) return null;
      final payload = raw is String ? raw : raw.toString();
      final trimmed = payload.trim();
      if (trimmed.isEmpty || trimmed == 'null') return null;
      var decoded = jsonDecode(trimmed);
      if (decoded is String && decoded.trim().isNotEmpty && decoded.trim() != 'null') {
        decoded = jsonDecode(decoded);
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  String _sourceBundleReferer() {
    final candidates = <String?>[
      _capturedVideoPageUrl,
      _currentPageUrl,
      _lastTrusted,
      widget.initialUrl,
    ];
    for (final candidate in candidates) {
      final value = (candidate ?? '').trim();
      if (value.isNotEmpty) return value;
    }
    if (_isvidfastSession) return 'https://vidfast.pro/';
    return 'https://player.videasy.net/';
  }

  String _sourceBundleOrigin() {
    final referer = _sourceBundleReferer();
    final uri = Uri.tryParse(referer);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      return uri.origin;
    }
    if (_isvidfastSession) return 'https://vidfast.pro';
    return 'https://player.videasy.net';
  }

  String _sourceBundleProviderLabel(String? rawUrl) {
    final uri = Uri.tryParse(rawUrl ?? '');
    final host = (uri?.host ?? '').toLowerCase();
    if (host.isEmpty) return 'Server';
    final parts = host.split('.').where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) {
      return parts[parts.length - 2];
    }
    return parts.isNotEmpty ? parts.first : 'Server';
  }

  bool _looksLikeSourceServerUrl(String? rawUrl) {
    final url = (rawUrl ?? '').trim();
    if (url.isEmpty) return false;
    if (_looksLikePlayableMediaUrl(url)) return true;
    final lower = url.toLowerCase();
    if (lower.startsWith('/wyzie/') || lower.startsWith('wyzie/')) return true;
    return lower.contains('/embed/') ||
        lower.contains('/api/') ||
        lower.contains('/wyzie/') ||
        lower.contains('videasy.net') ||
        lower.contains('player.videasy.net') ||
        lower.contains('videasy') ||
        lower.contains('myflixer') ||
        lower.contains('upcloud') ||
        lower.contains('vidcloud') ||
        lower.contains('server=') ||
        lower.contains('source=') ||
        lower.contains('.workers.dev') ||
        lower.contains('workers.dev');
  }

  String _sourceBundleQualityLabel(dynamic raw, [String? url]) {
    final values = <String>[];
    if (raw != null) values.add(raw.toString());
    if ((url ?? '').isNotEmpty) {
      values.add(url!);
      final uri = Uri.tryParse(url);
      if (uri != null) {
        values.addAll(uri.pathSegments);
        for (final segment in uri.pathSegments) {
          final decoded = _tryDecodePathToken(segment);
          if (decoded != null && decoded.isNotEmpty) values.add(decoded);
        }
      }
    }
    for (final value in values) {
      final normalized = _normalizeQualityLabel(value);
      if (RegExp(r'^\d{3,4}p$', caseSensitive: false).hasMatch(normalized)) {
        return normalized;
      }
    }
    return '';
  }

  String _sourceBundleFirstNonEmpty(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  void _collectSourceBundleSubtitles(
    dynamic raw,
    Set<String> seen,
    List<Map<String, String>> out,
  ) {
    if (raw == null) return;
    if (raw is List) {
      for (final item in raw) {
        _collectSourceBundleSubtitles(item, seen, out);
      }
      return;
    }
    if (raw is String) {
      final url = _normalizeBundleEmbedUrl(raw.trim());
      if (url.isEmpty) return;
      final sig = url.toLowerCase();
      if (!seen.add(sig)) return;
      out.add({
        'label': 'Subtitle',
        'url': url,
        'language': '',
        'source': 'Source API',
        'release': _nativeSubtitleReleaseContext(),
        'subtitleProfileKey': _nativeSubtitleProfileKey(),
        'mimeType': _subtitleMimeFromName(url),
      });
      return;
    }
    if (raw is! Map) return;
    final item = Map<String, dynamic>.from(raw);
    final url = _normalizeBundleEmbedUrl(_sourceBundleFirstNonEmpty(item, const ['file', 'src', 'url', 'link']));
    if (url.isEmpty) return;
    final label = _sourceBundleFirstNonEmpty(item, const ['label', 'title', 'name', 'lang', 'language']).ifEmpty('Subtitle');
    final language = _sourceBundleFirstNonEmpty(item, const ['lang', 'language', 'srclang']);
    final mimeType = _sourceBundleFirstNonEmpty(item, const ['mimeType', 'type', 'format']).ifEmpty(_subtitleMimeFromName(url));
    final sig = '${label.toLowerCase()}|${url.toLowerCase()}';
    if (!seen.add(sig)) return;
    out.add({
      'label': label,
      'url': url,
      'language': language,
      'source': _sourceBundleFirstNonEmpty(item, const ['source', 'provider', 'origin']).ifEmpty('Source API'),
      'release': _sourceBundleFirstNonEmpty(item, const ['release', 'release_name', 'fileName', 'filename', 'name']).ifEmpty(_nativeSubtitleReleaseContext()),
      'subtitleProfileKey': _nativeSubtitleProfileKey(),
      if (_sourceBundleFirstNonEmpty(item, const ['autoSelect', 'default']).toLowerCase() == 'true') 'autoSelect': 'true',
      if (_sourceBundleFirstNonEmpty(item, const ['hashMatched', 'moviehash_match']).toLowerCase() == 'true') 'hashMatched': 'true',
      if (_sourceBundleFirstNonEmpty(item, const ['hearingImpaired', 'hearing_impaired', 'hi']).toLowerCase() == 'true') 'hearingImpaired': 'true',
      if (mimeType.isNotEmpty) 'mimeType': mimeType,
    });
  }

  Map<String, dynamic>? _parseSourceBundleResponse(dynamic raw, String requestUrl) {
    dynamic data = raw;
    if (data == null) return null;
    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isEmpty) return null;
      try {
        data = jsonDecode(trimmed);
      } catch (_) {
        return null;
      }
    }

    final qualityOptions = <Map<String, String>>[];
    final serverOptions = <Map<String, String>>[];
    final subtitleTracks = <Map<String, String>>[];
    final qualitySeen = <String>{};
    final serverSeen = <String>{};
    final subtitleSeen = <String>{};

    void addQuality(String label, String url, {bool selected = false}) {
      final normalized = _normalizeQualityLabel(label);
      if (!RegExp(r'^\d{3,4}p$', caseSensitive: false).hasMatch(normalized)) return;
      final sig = '${normalized.toLowerCase()}|${url.toLowerCase()}';
      if (!qualitySeen.add(sig)) return;
      qualityOptions.add({
        'label': normalized,
        'key': 'q_${normalized.toLowerCase()}_${qualityOptions.length}',
        'url': url,
        if (selected) 'selected': 'true',
      });
    }

    void addServer(String label, String url, {bool selected = false}) {
      final normalized = _normalizeServerLabel(label);
      if (normalized.isEmpty) return;
      final sig = '${normalized.toLowerCase()}|${url.toLowerCase()}';
      if (!serverSeen.add(sig)) return;
      serverOptions.add({
        'label': normalized,
        'key': 'srv_${normalized.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_${serverOptions.length}',
        'embedUrl': url,
        if (selected) 'selected': 'true',
      });
    }

    void walk(dynamic node) {
      if (node == null) return;
      if (node is List) {
        for (final item in node) {
          walk(item);
        }
        return;
      }
      if (node is! Map) return;

      final map = Map<String, dynamic>.from(node);
      final mediaUrl = _normalizeBundleEmbedUrl(_sourceBundleFirstNonEmpty(
        map,
        const ['file', 'src', 'url', 'stream', 'playlist', 'hls', 'm3u8', 'link', 'embedUrl', 'embed', 'iframe', 'iframeUrl', 'playerUrl', 'watchUrl'],
      ));
      if (mediaUrl.isNotEmpty && !_isYouTubeUrl(mediaUrl)) {
        final serverLabel = _sourceBundleFirstNonEmpty(
          map,
          const ['server', 'source', 'provider', 'name', 'title', 'label'],
        ).ifEmpty(_sourceBundleProviderLabel(mediaUrl));
        if (_looksLikeSourceServerUrl(mediaUrl)) {
          addServer(serverLabel, mediaUrl, selected: serverOptions.isEmpty);
        }
        if (_looksLikePlayableMediaUrl(mediaUrl)) {
          final qualityLabel = _sourceBundleQualityLabel(
            _sourceBundleFirstNonEmpty(map, const ['label', 'quality', 'resolution', 'size', 'title', 'name']),
            mediaUrl,
          );
          if (qualityLabel.isNotEmpty) {
            addQuality(qualityLabel, mediaUrl, selected: qualityOptions.isEmpty);
          }
        }
      }

      for (final key in const ['subtitles', 'subtitle', 'tracks', 'captions']) {
        if (map.containsKey(key)) {
          _collectSourceBundleSubtitles(map[key], subtitleSeen, subtitleTracks);
        }
      }

      for (final entry in map.entries) {
        if (const {'subtitles', 'subtitle', 'tracks', 'captions'}.contains(entry.key)) {
          continue;
        }
        walk(entry.value);
      }
    }

    walk(data);

    if (qualityOptions.isEmpty && serverOptions.isEmpty && subtitleTracks.isEmpty) {
      return null;
    }

    if (serverOptions.isNotEmpty) {
      var selectedIndex = serverOptions.indexWhere((s) => s['selected'] == true || s['selected'] == 'true');
      if (selectedIndex < 0) selectedIndex = 0;
      for (final s in serverOptions) {
        s.remove('selected');
      }
      serverOptions[selectedIndex]['selected'] = 'true';
    }

    return {
      'qualityOptions': qualityOptions,
      'currentQualityLabel': qualityOptions.isNotEmpty ? qualityOptions.first['label'] : null,
      'serverOptions': serverOptions,
      'currentServerLabel': serverOptions.isNotEmpty ? serverOptions.firstWhere((s) => s['selected'] == 'true', orElse: () => serverOptions.first)['label'] : null,
      'subtitleTracks': subtitleTracks,
    };
  }

  Future<void> _fetchSourceBundleFromPageUrl(String url, {bool force = false}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastAttempt = _sourceBundleFetchTimestamps[trimmed] ?? 0;
    final cooldownMs = force ? 5000 : 20000;
    if (nowMs - lastAttempt < cooldownMs) return;
    _sourceBundleFetchTimestamps[trimmed] = nowMs;

    if (_sourceBundleFetchBusy && !force) return;
    final alreadyUseful = _pageServerOptions.length > 1 ||
        _pageQualityOptions.length > 1 ||
        _externalSubtitleTracks.isNotEmpty;
    if (!force && alreadyUseful && _lastFetchedSourceApiUrl == trimmed) return;

    _sourceBundleFetchBusy = true;
    _lastFetchedSourceApiUrl = trimmed;
    try {
      try {
        final response = await _dio.get<String>(
          trimmed,
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 20),
            validateStatus: (s) => s != null && s < 600,
            headers: {
              'User-Agent': _ua,
              'Accept': 'application/json,text/plain,*/*',
              'Referer': _sourceBundleReferer(),
              'Origin': _sourceBundleOrigin(),
              'Cache-Control': 'no-cache, no-store, must-revalidate',
              'Pragma': 'no-cache',
              'Expires': '0',
            },
          ),
        );

        if (response.statusCode == 429) {
          _sourceBundleFetchTimestamps[trimmed] = nowMs + 60000;
          debugPrint('[SourceBundle] 429 rate-limited, backing off: $trimmed');
          return;
        }

        if ((response.statusCode ?? 0) >= 200 && (response.statusCode ?? 0) < 300) {
          final bundle = _parseSourceBundleResponse(response.data, trimmed);
          if (bundle != null) {
            if (mounted) {
              setState(() => _applyCapturedSourceBundle(bundle));
            } else {
              _applyCapturedSourceBundle(bundle);
            }
            if (_nativePlayerActive) {
              unawaited(_updateNativePlayerOptions());
            }
            return;
          }
        }
      } catch (e) {
        debugPrint('[SourceBundleDirectError] $trimmed $e');
        if (e.toString().contains('429')) {
          _sourceBundleFetchTimestamps[trimmed] = nowMs + 60000;
        }
        return;
      }

      if (_wc != null) {
        try {
          await _wc!.evaluateJavascript(source: '''
            (async function(){
              try {
                if (window.__asdFetchAndParseSourceBundle) {
                  return await window.__asdFetchAndParseSourceBundle(${jsonEncode(trimmed)});
                }
                return false;
              } catch (e) {
                return false;
              }
            })();
          ''');
        } catch (_) {}
      }
    } finally {
      _sourceBundleFetchBusy = false;
    }
  }

  Future<void> _maybeFetchLatestSourceBundle({bool force = false}) async {
    if (_isvidfastSession) {
      final candidateUrl = (
        (_currentPageUrl ?? '').trim().isNotEmpty
            ? _currentPageUrl!
            : widget.initialUrl
      ).trim();
      if (candidateUrl.isEmpty) return;

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final lastAttempt = _sourceBundleFetchTimestamps[candidateUrl] ?? 0;
      if (!force && nowMs - lastAttempt < 6000) return;

      await _fetchSourceBundleFromPageUrl(candidateUrl, force: true);

      if (_pageServerOptions.isEmpty && _wc != null) {
        try {
          await _wc!.evaluateJavascript(source: '''
            (async function(){
              try {
                if (window.__asdFetchAndParseSourceBundle) {
                  return await window.__asdFetchAndParseSourceBundle(${jsonEncode(candidateUrl)});
                }
              } catch (e) {}
              return false;
            })();
          ''');
        } catch (_) {}
      }
      return;
    }

    if (!_isVideasyPlayerUrl(widget.initialUrl) &&
        !_isVideasyPlayerUrl(_currentPageUrl)) {
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cooldownCandidateUrl = (_lastDetectedSourceApiUrl?.trim().isNotEmpty == true
            ? _lastDetectedSourceApiUrl!.trim()
            : _buildVideasySourceBundleApiUrl() ?? '');
    if (cooldownCandidateUrl.isNotEmpty) {
      final lastAttempt = _sourceBundleFetchTimestamps[cooldownCandidateUrl] ?? 0;
      if (!force && nowMs - lastAttempt < 15000) return;
    }

    var candidateUrl = (_lastDetectedSourceApiUrl ?? '').trim();

    if (candidateUrl.isEmpty && _wc != null) {
      try {
        final raw = await _wc!.evaluateJavascript(source: '''
          (function(){
            try {
              if (window.__asdLastSourceApiUrl) return String(window.__asdLastSourceApiUrl || '');
              var entries = [];
              try { entries = performance.getEntriesByType('resource') || []; } catch(e) {}
              for (var i = entries.length - 1; i >= 0; i--) {
                var name = String((entries[i] && entries[i].name) || '');
                if (name.indexOf('api.videasy.net/cdn/sources-with-title') !== -1) {
                  return name;
                }
              }
            } catch (e) {}
            return '';
          })();
        ''');
        final extracted = (raw is String ? raw : raw?.toString() ?? '').trim();
        if (extracted.isNotEmpty && extracted != 'null') {
          candidateUrl = extracted;
          _lastDetectedSourceApiUrl = extracted;
        }
      } catch (_) {}
    }

    candidateUrl = candidateUrl.ifEmpty(_buildVideasySourceBundleApiUrl() ?? '');
    if (candidateUrl.isEmpty) return;
    await _fetchSourceBundleFromPageUrl(candidateUrl, force: force);
  }

  Future<List<Map<String, String>>> _fetchWyzieSubtitleTracks() async {
    if (widget.tmdbId == null || widget.mediaType == null) {
      return const <Map<String, String>>[];
    }
    return WyziePrefetchService.fetchArabicTracks(
      tmdbId: widget.tmdbId!,
      mediaType: widget.mediaType!,
      title: widget.headerTitle ?? _currentMediaTitle ?? _currentPageTitle,
      season: widget.mediaType == MediaType.tv ? widget.season : null,
      episode: widget.mediaType == MediaType.tv ? widget.episode : null,
      onProgress: null,
    );
  }

  String _subtitlePersistFingerprint(Iterable<Map<String, String>> tracks) {
    final parts = <String>[];
    for (final track in tracks) {
      final url = (track['url'] ?? '').trim().toLowerCase();
      if (url.isEmpty) continue;
      final label = (track['label'] ?? '').trim().toLowerCase();
      parts.add('$label|$url');
    }
    parts.sort();
    return parts.join('||');
  }

  Future<void> _persistCapturedSubtitlesLight([Iterable<Map<String, String>>? tracks]) async {
    if (_subtitlePersistBusy || !_hasTmdbContext || widget.tmdbId == null) return;
    final prepared = _sanitizeSubtitleTrackList(tracks ?? _externalSubtitleTracks);
    if (prepared.isEmpty) return;
    final fingerprint = _subtitlePersistFingerprint(prepared);
    if (fingerprint.isEmpty || fingerprint == _lastPersistedSubtitleFingerprint) return;
    final title = _cleanMediaTitle(widget.headerTitle ?? _currentMediaTitle ?? _currentPageTitle ?? '').ifEmpty('Media');
    _subtitlePersistBusy = true;
    try {
      final stored = await WyziePrefetchService.persistTracksForItem(
        tmdbId: widget.tmdbId!,
        mediaType: _resolvedNativeMediaType,
        title: title,
        year: null,
        season: _resolvedNativeMediaType == MediaType.tv ? widget.season : null,
        episode: _resolvedNativeMediaType == MediaType.tv ? widget.episode : null,
        tracks: prepared,
      );
      _lastPersistedSubtitleFingerprint = fingerprint;
      if (stored.isNotEmpty) {
        final merged = _mergeSubtitleTrackMaps([
          ..._externalSubtitleTracks,
          ...stored,
        ]);
        if (mounted) {
          setState(() => _externalSubtitleTracks = merged);
        } else {
          _externalSubtitleTracks = merged;
        }
        _requestNativeSubtitleSync();
      }
    } catch (_) {
    } finally {
      _subtitlePersistBusy = false;
    }
  }

  Future<void> _loadStoredSubtitleTracksForNativePlayback({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (!_hasTmdbContext || widget.tmdbId == null || widget.mediaType == null) return;
    try {
      final stored = await WyziePrefetchService.loadStoredTracks(
        tmdbId: widget.tmdbId!,
        mediaType: widget.mediaType!,
        season: widget.mediaType == MediaType.tv ? widget.season : null,
        episode: widget.mediaType == MediaType.tv ? widget.episode : null,
      ).timeout(timeout, onTimeout: () => const <Map<String, String>>[]);
      if (stored.isEmpty) return;
      final merged = _mergeSubtitleTrackMaps([
        ..._externalSubtitleTracks,
        ...stored,
      ]);
      if (merged.length == _externalSubtitleTracks.length &&
          _subtitlePersistFingerprint(merged) == _subtitlePersistFingerprint(_externalSubtitleTracks)) {
        return;
      }
      if (mounted) {
        setState(() => _externalSubtitleTracks = merged);
      } else {
        _externalSubtitleTracks = merged;
      }
      _requestNativeSubtitleSync();
    } catch (_) {}
  }

  Future<void> _primeSubtitleTracksForNativePlayback({
    bool waitForNetwork = false,
  }) async {
    await _loadStoredSubtitleTracksForNativePlayback();
    if (!_hasTmdbContext || widget.skipInitialSubtitleFetch) return;

    if (waitForNetwork) {
      try {
        await _refreshExternalSubtitles(force: _externalSubtitleTracks.isEmpty).timeout(
          const Duration(seconds: 8),
          onTimeout: () {},
        );
      } catch (_) {}
      return;
    }

    if (_externalSubtitleTracks.isEmpty) {
      unawaited(_refreshExternalSubtitles(force: true));
    }
  }

  Future<void> _refreshExternalSubtitles({bool force = false}) async {
    if (_subtitleFetchBusy) {
      if (force) _subtitleRefreshQueued = true;
      return;
    }
    if (widget.tmdbId == null || widget.mediaType == null) return;

    final lookupKey = '${widget.mediaType!.name}|${widget.tmdbId}|${widget.season ?? ''}|${widget.episode ?? ''}';
    if (!force && _lastSubtitleFetchKey == lookupKey && _externalSubtitleTracks.isNotEmpty) return;

    _subtitleFetchBusy = true;

    Future<void> publishTracks(
      Iterable<Map<String, String>> tracks, {
      bool persist = true,
    }) async {
      var prepared = _sanitizeSubtitleTrackList(tracks);
      if (prepared.isEmpty) return;

      if (persist && _hasTmdbContext && widget.tmdbId != null) {
        final archiveTracks = prepared.where(_isArchiveSubtitleTrack).toList(growable: false);
        if (archiveTracks.isNotEmpty) {
          final directTracks = prepared.where((track) => !_isArchiveSubtitleTrack(track)).toList(growable: false);
          try {
            final stored = await WyziePrefetchService.persistTracksForItem(
              tmdbId: widget.tmdbId!,
              mediaType: widget.mediaType!,
              title: (widget.headerTitle ?? _currentMediaTitle ?? _currentPageTitle ?? 'Media').trim(),
              year: null,
              season: widget.mediaType == MediaType.tv ? widget.season : null,
              episode: widget.mediaType == MediaType.tv ? widget.episode : null,
              tracks: archiveTracks,
            );
            prepared = _sanitizeSubtitleTrackList([
              ...directTracks,
              ...stored,
            ]);
          } catch (_) {
            prepared = _sanitizeSubtitleTrackList(directTracks);
          }
        }
      } else {
        prepared = _sanitizeSubtitleTrackList(_removeRawArchiveSubtitleTracks(prepared));
      }

      if (prepared.isEmpty) return;

      final beforeFingerprint = _subtitlePersistFingerprint(_removeRawArchiveSubtitleTracks(_externalSubtitleTracks));
      final merged = _mergeSubtitleTrackMaps([
        ..._removeRawArchiveSubtitleTracks(_externalSubtitleTracks),
        ...prepared,
      ]);
      final afterFingerprint = _subtitlePersistFingerprint(merged);
      if (afterFingerprint == beforeFingerprint) return;

      if (mounted) {
        setState(() => _externalSubtitleTracks = merged);
      } else {
        _externalSubtitleTracks = merged;
      }
      _lastSubtitleFetchKey = lookupKey;
      _requestNativeSubtitleSync();
      unawaited(_updateNativePlayerOptions());
      if (persist) {
        unawaited(
          _persistCapturedSubtitlesLight(prepared)
              .then((_) => _requestNativeSubtitleSync())
              .catchError((_) {}),
        );
      }
    }

    try {
      try {
        final stored = await WyziePrefetchService.loadStoredTracks(
          tmdbId: widget.tmdbId!,
          mediaType: widget.mediaType!,
          season: widget.mediaType == MediaType.tv ? widget.season : null,
          episode: widget.mediaType == MediaType.tv ? widget.episode : null,
        );
        await publishTracks(stored, persist: false);
        if (WyziePrefetchService._hasCompleteStoredSubtitleSet(_externalSubtitleTracks)) return;
      } catch (_) {}

      final title = widget.headerTitle ?? _currentMediaTitle ?? _currentPageTitle;
      try {
        final archiveStored = await WyziePrefetchService._extractTracksFromCachedSeasonArchives(
          tmdbId: widget.tmdbId!,
          mediaType: widget.mediaType!,
          title: (title ?? 'Media').trim(),
          season: widget.mediaType == MediaType.tv ? widget.season : null,
          episode: widget.mediaType == MediaType.tv ? widget.episode : null,
        );
        await publishTracks(archiveStored, persist: false);
        if (WyziePrefetchService._hasCompleteStoredSubtitleSet(_externalSubtitleTracks)) return;
      } catch (_) {}


      final providerFutures = <Future<List<Map<String, String>>>>[
        WyziePrefetchService._fetchSubsourceProviderTracks(
          tmdbId: widget.tmdbId!,
          mediaType: widget.mediaType!,
          title: title,
          season: widget.mediaType == MediaType.tv ? widget.season : null,
          episode: widget.mediaType == MediaType.tv ? widget.episode : null,
        ).timeout(
          const Duration(minutes: 2),
          onTimeout: () => const <Map<String, String>>[],
        ),
        WyziePrefetchService._fetchSubdlProviderTracks(
          tmdbId: widget.tmdbId!,
          mediaType: widget.mediaType!,
          title: title,
          season: widget.mediaType == MediaType.tv ? widget.season : null,
          episode: widget.mediaType == MediaType.tv ? widget.episode : null,
        ).timeout(
          const Duration(minutes: 2),
          onTimeout: () => const <Map<String, String>>[],
        ),
      ];

      final completed = await Future.wait(providerFutures.map((future) async {
        try {
          final tracks = await future;
          await publishTracks(tracks);
          return tracks;
        } catch (_) {
          return const <Map<String, String>>[];
        }
      }));

      final allFetched = _mergeSubtitleTrackMaps(completed.expand((e) => e));
      if (allFetched.isNotEmpty) {
        final merged = _mergeSubtitleTrackMaps([
          ..._externalSubtitleTracks,
          ...allFetched,
        ]).take(64).toList(growable: false);
        _lastSubtitleFetchKey = lookupKey;
        unawaited(
          WyziePrefetchService.persistTracksForItem(
            tmdbId: widget.tmdbId!,
            mediaType: widget.mediaType!,
            title: (widget.headerTitle ?? _currentMediaTitle ?? _currentPageTitle ?? 'Media').trim(),
            year: null,
            season: widget.mediaType == MediaType.tv ? widget.season : null,
            episode: widget.mediaType == MediaType.tv ? widget.episode : null,
            tracks: merged,
          ).then((stored) async {
            await publishTracks(stored, persist: false);
            _requestNativeSubtitleSync();
          }).catchError((_) {}),
        );
      }
    } finally {
      _subtitleFetchBusy = false;
      if (_subtitleRefreshQueued) {
        _subtitleRefreshQueued = false;
        unawaited(_forceRequestMoreArabic1Subtitles());
      }
    }
  }

  Future<void> _forceRequestMoreArabic1Subtitles() async {
    if (!_hasTmdbContext || widget.tmdbId == null || widget.mediaType == null) return;
    if (_subtitleFetchBusy) {
      _subtitleRefreshQueued = true;
      return;
    }
    _subtitleFetchBusy = true;
    try {
      final title = widget.headerTitle ?? _currentMediaTitle ?? _currentPageTitle ?? 'Media';
      final currentStored = await WyziePrefetchService.loadStoredTracks(
        tmdbId: widget.tmdbId!,
        mediaType: widget.mediaType!,
        season: widget.mediaType == MediaType.tv ? widget.season : null,
        episode: widget.mediaType == MediaType.tv ? widget.episode : null,
      );
      if (currentStored.isNotEmpty) {
        final fromCache = _mergeSubtitleTrackMaps([
          ..._externalSubtitleTracks,
          ...currentStored,
        ]);
        if (mounted) {
          setState(() => _externalSubtitleTracks = fromCache);
        } else {
          _externalSubtitleTracks = fromCache;
        }
        _requestNativeSubtitleSync();
      }

      final fetched = await WyziePrefetchService._fetchSubsourceProviderTracks(
        tmdbId: widget.tmdbId!,
        mediaType: widget.mediaType!,
        title: title,
        season: widget.mediaType == MediaType.tv ? widget.season : null,
        episode: widget.mediaType == MediaType.tv ? widget.episode : null,
      );
      if (fetched.isEmpty) {
        await _updateNativePlayerOptions();
        return;
      }

      final stored = await WyziePrefetchService.persistTracksForItem(
        tmdbId: widget.tmdbId!,
        mediaType: widget.mediaType!,
        title: title.trim(),
        year: null,
        season: widget.mediaType == MediaType.tv ? widget.season : null,
        episode: widget.mediaType == MediaType.tv ? widget.episode : null,
        tracks: [
          ...currentStored,
          ..._externalSubtitleTracks,
          ...fetched,
        ],
      );
      final merged = _mergeSubtitleTrackMaps([
        ..._externalSubtitleTracks,
        ...stored,
      ]);
      if (mounted) {
        setState(() => _externalSubtitleTracks = merged);
      } else {
        _externalSubtitleTracks = merged;
      }
      _lastSubtitleFetchKey = '';
      _requestNativeSubtitleSync();
      await _updateNativePlayerOptions();
    } finally {
      _subtitleFetchBusy = false;
      if (_subtitleRefreshQueued) {
        _subtitleRefreshQueued = false;
        unawaited(_forceRequestMoreArabic1Subtitles());
      }
    }
  }

  Future<List<Map<String, String>>> _resolveNativeSubtitleTracksForCurrentSource(
    Map<String, String> headers,
  ) async {
    if (_externalSubtitleTracks.isEmpty) return const <Map<String, String>>[];
    if (_canUseFastNativeSubtitleTracks()) {
      return _buildFastNativeSubtitleTracks();
    }
    final materialized = await _buildNativeSubtitleTracks(headers);
    if (materialized.isNotEmpty) return materialized;
    return _buildFastNativeSubtitleTracks();
  }

  void _requestNativeSubtitleSync() {
    if (_nativePlayerActive) {
      _pendingSubtitleOptionsSync = false;
      unawaited(_updateNativePlayerOptions());
      return;
    }
    if (_nativePlayerOpening || _nativePlayerShellOnly || _nativePlayerShellRequested) {
      _pendingSubtitleOptionsSync = true;
    }
  }

  Future<void> _updateNativePlayerOptions() async {
    if (!_nativePlayerActive) {
      _pendingSubtitleOptionsSync = true;
      return;
    }
    try {
      final currentMediaUrl = _capturedVideoUrl ?? _lastNativePlayerUrl ?? '';
      final headers = currentMediaUrl.trim().isEmpty
          ? const <String, String>{}
          : await _buildPipHeaders(
              currentMediaUrl,
              pageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted,
            );
      final nativeSubtitleTracks = currentMediaUrl.trim().isEmpty
          ? _buildFastNativeSubtitleTracks()
          : await _resolveNativeSubtitleTracksForCurrentSource(headers);
      await _pip.invokeMethod('updatePlayerOptions', {
        ..._nativeIdentityArgs(),
        'qualityOptions': _pageQualityOptions.map((e) => e.toMap()).toList(),
        'currentQualityLabel': _currentPageQualityLabel,
        'serverOptions': _pageServerOptions.map((e) => e.toMap()).toList(),
        'currentServerLabel': _currentServerLabel,
        'subtitleTracks': nativeSubtitleTracks,
      });
      _pendingSubtitleOptionsSync = false;
    } catch (_) {}
  }

  bool _isArchiveSubtitleTrack(Map<String, String> track) {
    final url = (track['url'] ?? '').trim().toLowerCase();
    final mime = (track['mimeType'] ?? '').trim().toLowerCase();
    final label = (track['label'] ?? '').trim().toLowerCase();
    final fileName = (track['fileName'] ?? '').trim().toLowerCase();
    return WyziePrefetchService._isSubtitleArchiveUrl(url) ||
        WyziePrefetchService._isSubtitleArchiveUrl(label) ||
        WyziePrefetchService._isSubtitleArchiveUrl(fileName) ||
        mime.contains('zip') ||
        mime.contains('rar') ||
        mime.contains('7z') ||
        mime.contains('compressed');
  }

  List<Map<String, String>> _removeRawArchiveSubtitleTracks(Iterable<Map<String, String>> tracks) {
    return tracks.where((track) => !_isArchiveSubtitleTrack(track)).toList(growable: false);
  }


  List<Map<String, String>> _sanitizeSubtitleTrackList(Iterable<Map<String, String>> tracks) {
    return _mergeSubtitleTrackMaps(
      tracks.map((track) {
        final cleaned = <String, String>{};
        track.forEach((key, value) {
          final k = key.trim();
          final v = value.trim();
          if (k.isNotEmpty && v.isNotEmpty) cleaned[k] = v;
        });
        if ((cleaned['label'] ?? '').trim().isEmpty) {
          cleaned['label'] = cleaned['language']?.trim().isNotEmpty == true
              ? cleaned['language']!.trim()
              : 'Subtitle';
        }
        if ((cleaned['source'] ?? '').trim().isEmpty) {
          cleaned['source'] = 'Embedded';
        }
        if ((cleaned['mimeType'] ?? '').trim().isEmpty && (cleaned['url'] ?? '').trim().isNotEmpty) {
          cleaned['mimeType'] = _subtitleMimeFromName(cleaned['url']!);
        }
        return cleaned;
      }),
    );
  }

  Future<double> _getCurrentPosition() async {
    try {
      final pos = await _pip.invokeMethod<num>('getCurrentPosition');
      return pos?.toDouble() ?? _capturedVideoTime;
    } catch (_) {
      return _capturedVideoTime;
    }
  }

  List<Map<String, String>> _mergeSubtitleTrackMaps(Iterable<Map<String, String>> tracks) {
    final merged = <String, Map<String, String>>{};
    for (final track in tracks) {
      final rawUrl = (track['url'] ?? '').trim();
      if (rawUrl.isEmpty) continue;
      final rawLabel = (track['label'] ?? 'Subtitle').trim();
      final dedupe = '${rawLabel.toLowerCase()}|${rawUrl.toLowerCase()}';
      final incoming = <String, String>{};
      track.forEach((key, value) {
        final k = key.trim();
        final v = value.trim();
        if (k.isNotEmpty && v.isNotEmpty) incoming[k] = v;
      });
      incoming['label'] = rawLabel.isEmpty ? 'Subtitle' : rawLabel;
      incoming['url'] = rawUrl;
      incoming['language'] = (incoming['language'] ?? '').trim();
      incoming['source'] = (incoming['source'] ?? '').trim();
      if ((incoming['mimeType'] ?? '').trim().isEmpty) {
        final inferred = _subtitleMimeFromName(rawUrl);
        if (inferred.isNotEmpty) incoming['mimeType'] = inferred;
      }
      final existing = merged[dedupe];
      if (existing == null) {
        merged[dedupe] = incoming;
        continue;
      }
      for (final entry in incoming.entries) {
        final key = entry.key;
        final value = entry.value.trim();
        if (value.isEmpty) continue;
        if ((existing[key] ?? '').trim().isEmpty) {
          existing[key] = value;
          continue;
        }
        if ((key == 'default' || key == 'autoSelect' || key == 'hashMatched' || key == 'hearingImpaired') && value.toLowerCase() == 'true') {
          existing[key] = 'true';
          continue;
        }
        if (key == 'matchRank') {
          final oldRank = int.tryParse(existing[key] ?? '');
          final newRank = int.tryParse(value);
          if (newRank != null && (oldRank == null || newRank < oldRank)) {
            existing[key] = value;
          }
          continue;
        }
        if ((key == 'matchedRelease' || key == 'matchedFilter') && value.isNotEmpty) {
          existing[key] = value;
        }
      }
    }
    return merged.values.toList(growable: false);
  }


  bool _isInternalUiServerLabel(String? value) {
    final lbl = (value ?? '').trim().toLowerCase();
    if (lbl.isEmpty) return true;
    if (lbl.startsWith('player_source_')) return true;
    if (lbl.startsWith('player_sourcesbrowser')) return true;
    if (lbl.startsWith('player_') &&
        (lbl.endsWith('btn') ||
         lbl.endsWith('_label') ||
         lbl.endsWith('btn_label'))) {
      return true;
    }
    return false;
  }

  String _normalizeBundleEmbedUrl(String? rawUrl) {
    final raw = (rawUrl ?? '').trim();
    if (raw.isEmpty) return '';
    final direct = Uri.tryParse(raw);
    if (direct != null && direct.hasScheme && direct.host.isNotEmpty) return raw;
    final baseCandidates = <String?>[
      _currentPageUrl,
      _capturedVideoPageUrl,
      _lastTrusted,
      _currentHost != null ? 'https://$_currentHost/' : null,
      'https://player.videasy.net/',
    ];
    for (final base in baseCandidates) {
      final b = (base ?? '').trim();
      if (b.isEmpty) continue;
      final baseUri = Uri.tryParse(b);
      if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) continue;
      try {
        return baseUri.resolve(raw).toString();
      } catch (_) {}
    }
    return raw;
  }

  Future<void> _maybePrimeSourceBundleServer(List<PageServerOption> options) async {
    // Server switching disabled: do not auto-switch/prime alternate servers.
    return;
  }

  void _applyCapturedSourceBundle(Map<String, dynamic> data) {
    final qualityOptions = (data['qualityOptions'] as List?)
            ?.whereType<Map>()
            .map((e) => PageQualityOption.fromMap(Map<String, dynamic>.from(e)))
            .toList(growable: false) ??
        const <PageQualityOption>[];
    // Server switching disabled: ignore serverOptions from source bundles.
    const serverOptions = <PageServerOption>[];
    final subtitleTracks = _sanitizeSubtitleTrackList(
      ((data['subtitleTracks'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, String>.from(
                Map<String, dynamic>.from(e).map((k, v) => MapEntry(k.toString(), (v ?? '').toString())),
              ))
          .map((track) {
            final normalized = <String, String>{...track};
            final rawUrl = (normalized['url'] ?? '').trim();
            if (rawUrl.isNotEmpty) normalized['url'] = _normalizeBundleEmbedUrl(rawUrl);
            if ((normalized['source'] ?? '').trim().isEmpty) normalized['source'] = 'Source API';
            return normalized;
          }),
    );

    if (qualityOptions.isNotEmpty) {
      _updatePageQualityOptions(qualityOptions, data['currentQualityLabel']?.toString());
      if (_pendingNativeOpenOnPlayableCapture &&
          !_nativePlayerActive &&
          !_nativePlayerOpening) {
        final bestOpt = _preferredDirectNativeQualityOption();
        final bestUrl = (bestOpt?.url ?? '').trim();
        if (bestUrl.isNotEmpty && _looksLikePlayableMediaUrl(bestUrl)) {
          Future.microtask(() => _openNativePlayer(
                force: true,
                replace: true,
                forcedUrl: bestUrl,
                forcedPageUrl:
                    _capturedVideoPageUrl ?? _currentPageUrl ?? widget.initialUrl,
                forcedMimeType: _inferMimeType(bestUrl),
              ));
        }
      }
      if (widget.downloadOnlyMode && !_downloadSelectionCommitted) {
        _scheduleInitialDownloadChoicesPrompt();
      }
    }
    if (serverOptions.isNotEmpty) {
      // Server switching disabled. Server switching is intentionally ignored.
    }
    if (subtitleTracks.isNotEmpty) {
      _externalSubtitleTracks = _mergeSubtitleTrackMaps([
        ..._externalSubtitleTracks,
        ...subtitleTracks,
      ]);
      _requestNativeSubtitleSync();
      unawaited(_persistCapturedSubtitlesLight(subtitleTracks));
    }
  }


  String _normalizeQualityLabel(String input) {
    final m = RegExp(r'(2160|1440|1080|720|540|480|360|240)\s*p?', caseSensitive: false)
        .firstMatch(input);
    if (m != null) return '${m.group(1)}p';
    return input.trim();
  }

  List<PageQualityOption> _dedupeQualityOptionsByLabel(List<PageQualityOption> options) {
    final bestByLabel = <String, PageQualityOption>{};
    final order = <String>[];

    int score(PageQualityOption option) {
      final url = (option.url ?? '').trim();
      var s = 0;
      if (_looksLikePlayableMediaUrl(url)) s += 100;
      if (_isDirectMediaFile(url)) s += 30;
      if (_looksLikeHlsManifestUrl(url)) s += 20;
      if (option.selected) s += 10;
      return s;
    }

    for (final opt in options) {
      final label = _normalizeQualityLabel(opt.label).ifEmpty(opt.label.trim());
      if (label.isEmpty) continue;
      final normalized = PageQualityOption(
        label: label,
        key: opt.key.isNotEmpty ? opt.key : '${label}_${order.length}',
        url: (opt.url ?? '').trim().isEmpty ? null : opt.url!.trim(),
        selected: opt.selected,
      );
      final labelKey = label.toLowerCase();
      final existing = bestByLabel[labelKey];
      if (existing == null) {
        bestByLabel[labelKey] = normalized;
        order.add(labelKey);
        continue;
      }
      if (score(normalized) > score(existing)) {
        bestByLabel[labelKey] = PageQualityOption(
          label: normalized.label,
          key: normalized.key,
          url: normalized.url ?? existing.url,
          selected: normalized.selected || existing.selected,
        );
      } else if ((existing.url == null || existing.url!.trim().isEmpty) &&
          (normalized.url?.trim().isNotEmpty == true)) {
        bestByLabel[labelKey] = PageQualityOption(
          label: existing.label,
          key: existing.key,
          url: normalized.url,
          selected: existing.selected || normalized.selected,
        );
      }
    }

    final out = <PageQualityOption>[];
    for (final key in order) {
      final item = bestByLabel[key];
      if (item != null) out.add(item);
    }
    return out;
  }

  void _updatePageQualityOptions(List<PageQualityOption> options, [String? currentLabel]) {
    final normalized = _dedupeQualityOptionsByLabel(options)
      ..sort((a, b) => _qualityRankLabel(b.label).compareTo(_qualityRankLabel(a.label)));
    _pageQualityOptions = normalized;
    _currentPageQualityLabel = currentLabel != null && currentLabel.trim().isNotEmpty
        ? _normalizeQualityLabel(currentLabel)
        : normalized.firstWhere(
            (e) => e.selected,
            orElse: () => normalized.isNotEmpty ? normalized.first : const PageQualityOption(label: '', key: ''),
          ).label;
  }

  Future<void> _switchPageQuality(PageQualityOption option) async {
    final startTime = (() async {
      try {
        final pos = await _pip.invokeMethod<num>('getCurrentPosition');
        return pos?.toDouble() ?? _capturedVideoTime;
      } catch (_) {
        return _capturedVideoTime;
      }
    })();

    final seekSeconds = await startTime;
    final normalizedLabel =
        _normalizeQualityLabel(option.label).ifEmpty(option.label);

    if (mounted) {
      setState(() {
        _currentPageQualityLabel = normalizedLabel;
      });
    } else {
      _currentPageQualityLabel = normalizedLabel;
    }

    if (_looksLikePlayableMediaUrl(option.url)) {
      _qualitySwitchPending = false;
      _manualPlayAfterQualitySwitchPending = false;
      _nativeDecoderFallbackTriedUrls
        ..clear()
        ..add(option.url!.trim().toLowerCase());
      await _openNativePlayer(
        force: true,
        replace: true,
        startTimeOverride: seekSeconds,
        forcedUrl: option.url,
        forcedPageUrl: _capturedVideoPageUrl,
        forcedMimeType: _inferMimeType(option.url),
      );
      return;
    }

    if (_wc != null) {
      _capturedVideoUrl = null;
      _capturedVideoMimeType = null;
      _capturedVideoTime = 0;
      _pendingNativeOpenOnPlayableCapture = true;
      _pendingNativeStartTime = seekSeconds;
      _qualitySwitchPending = true;
      _manualPlayAfterQualitySwitchPending = true;
      await _allowSitePlayerForSwitchCapture();

      bool switched = false;
      try {
        final raw = await _wc!.evaluateJavascript(source: '''
          (function(){
            try {
              if (window.__asdSwitchQuality) {
                var ok = !!window.__asdSwitchQuality(${jsonEncode(normalizedLabel)});
                if (ok) return true;
              }
              if (window.__asdSelectQualityOption) {
                return !!window.__asdSelectQualityOption(
                  ${jsonEncode(option.key)},
                  ${jsonEncode(normalizedLabel)},
                  ${jsonEncode(option.url ?? '')}
                );
              }
            } catch(e) {}
            return false;
          })();
        ''');
        switched = raw == true || raw?.toString() == 'true';
      } catch (_) {}

      if (switched) {
        Future.delayed(const Duration(seconds: 8), () {
          if (!mounted) return;
          if (_qualitySwitchPending &&
              !_nativePlayerActive &&
              !_nativePlayerOpening) {
            _qualitySwitchPending = false;
            _manualPlayAfterQualitySwitchPending = false;
            _showSnack('⚠️ لم تُلتقط هذه الجودة بعد');
          }
        });
        return;
      }
    }

    _qualitySwitchPending = false;
    _manualPlayAfterQualitySwitchPending = false;
    _showSnack('⚠️ هذه الجودة لا تملك رابطًا مباشرًا الآن');
  }


  void _setupVidfastHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'onVideoFound',
      callback: (args) async {
        final raw = args.isNotEmpty ? args.first : null;
        if (raw is! Map) return true;
        final payload = Map<String, dynamic>.from(raw);
        final foundUrl = (payload['url'] ?? payload['src'] ?? '').toString().trim();
        if (!_looksLikePlayableMediaUrl(foundUrl)) return true;
        final foundPageUrl =
            (payload['pageUrl'] ?? _currentPageUrl ?? widget.initialUrl)
                .toString()
                .trim();
        final foundMime = (payload['mimeType'] ?? '').toString().trim();
        final foundQuality =
            (payload['qualityLabel'] ?? payload['label'] ?? '')
                .toString()
                .trim();
        _capturePlayableUrl(
          foundUrl,
          pageUrl: foundPageUrl.isEmpty ? widget.initialUrl : foundPageUrl,
          mimeType: foundMime.isEmpty ? null : foundMime,
          qualityLabel: foundQuality.isEmpty ? null : foundQuality,
        );
        if (mounted && _showQualityResolveLoader) {
          setState(() => _showQualityResolveLoader = false);
        }
        if (widget.downloadOnlyMode && !_downloadSelectionCommitted) {
          _scheduleInitialDownloadChoicesPrompt();
        }
        return true;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onSourceBundle',
      callback: (args) async {
        final raw = args.isNotEmpty ? args.first : null;
        if (raw is! Map) return true;
        final bundle = VidfastSourceBundle.fromMap(
          Map<String, dynamic>.from(raw),
        );
        _applyCapturedSourceBundle({
          'qualityOptions': bundle.qualityOptions.map((e) => e.toMap()).toList(),
          'currentQualityLabel': bundle.currentQualityLabel,
          'serverOptions': bundle.serverOptions.map((e) => e.toMap()).toList(),
          'currentServerLabel': bundle.currentServerLabel,
          'subtitleTracks': bundle.subtitleTracks,
        });
        if (mounted) setState(() {});
        return true;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onServerListFound',
      callback: (args) async {
        // Server switching disabled: keep the handler only to avoid JS-side missing-handler errors.
        return true;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onServerSwitched',
      callback: (args) async {
        final raw = args.isNotEmpty ? args.first : null;
        if (raw is! Map) return true;
        final payload = Map<String, dynamic>.from(raw);
        final server = (payload['server'] ?? '').toString().trim();
        if (server.isNotEmpty) {
          _currentServerLabel = server;
          if (mounted) setState(() {});
        }
        return true;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onQualitySwitched',
      callback: (args) async {
        final raw = args.isNotEmpty ? args.first : null;
        if (raw is! Map) return true;
        final payload = Map<String, dynamic>.from(raw);
        final quality = (payload['quality'] ?? '').toString().trim();
        if (quality.isNotEmpty) {
          _currentPageQualityLabel = quality;
          if (mounted) setState(() {});
        }
        return true;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onSourceBundleError',
      callback: (args) async {
        final raw = args.isNotEmpty ? args.first : null;
        debugPrint('[SourceBundleError] $raw');
        return true;
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onDownload',
      callback: (args) async {
        final raw = args.isNotEmpty ? args.first : null;
        if (raw is Map) {
          final payload = Map<String, dynamic>.from(raw);
          final foundUrl = (payload['url'] ?? '').toString().trim();
          if (_looksLikePlayableMediaUrl(foundUrl)) {
            _capturePlayableUrl(
              foundUrl,
              pageUrl: _currentPageUrl ?? widget.initialUrl,
              mimeType: _inferMimeType(foundUrl),
            );
          }
        }
        return true;
      },
    );
  }

  bool _looksLikeVidfastServerLabel(String label) {
    final value = label.trim().toLowerCase();
    if (value.isEmpty) return false;
    return value == 'server' ||
        value.startsWith('server ') ||
        value.startsWith('srv ') ||
        value.startsWith('vidfast server') ||
        RegExp(r'^server\s*\d+$').hasMatch(value) ||
        RegExp(r'^srv[_\-]?\d+$').hasMatch(value) ||
        RegExp(r'(^|[\s_\-])(vedge|vrapid|max|nova|upcloud|vidcloud|cypher|cipher|ciper)(\b|$)').hasMatch(value);
  }

  bool _isVidfastDomServerOption(PageServerOption option) {
    final label = option.label.trim().toLowerCase();
    final key = option.key.trim().toLowerCase();
    final embedUrl = _normalizeBundleEmbedUrl(option.embedUrl).toLowerCase();
    if (embedUrl.contains('vidfast.pro/movie/') ||
        embedUrl.contains('vidfast.pro/tv/')) {
      return true;
    }
    if (label == 'vidfast') return false;
    if (_looksLikeVidfastServerLabel(label)) return true;
    if (key.startsWith('srv_') || key.startsWith('server_')) return true;
    if (_isvidfastSession && option.selected && label.isNotEmpty && label != 'vidfast') return true;
    return false;
  }

  Future<void> switchServer(String serverLabel) async {
    // Server switching disabled.
    return;
  }

  Future<void> switchQuality(String qualityLabel) async {
    final normalized = qualityLabel.trim();
    if (normalized.isEmpty) return;
    final option = _pageQualityOptions.firstWhere(
      (e) =>
          _normalizeQualityLabel(e.label).toLowerCase() ==
          _normalizeQualityLabel(normalized).toLowerCase(),
      orElse: () => PageQualityOption(
        label: normalized,
        key: normalized,
        selected: true,
      ),
    );
    await _switchPageQuality(option);
  }

  Future<void> rescanServers() async {
    // Server switching disabled.
    return;
  }

  Future<void> fetchVidfastSources(String apiUrl) async {
    if (_wc == null) return;
    try {
      await _wc!.evaluateJavascript(
        source:
            'window.__asdFetchAndParseVidfastQualities && '
            'window.__asdFetchAndParseVidfastQualities(${jsonEncode(apiUrl)});',
      );
    } catch (_) {}
  }

  Future<void> switchServerByIndex(int serverIndex) async {
    // Server switching disabled.
    return;
  }

  bool _isVidfastContext() {
    final candidates = <String?>[
      _currentPageUrl,
      _lastTrusted,
      _pendingServerSwitchEmbedUrl,
      widget.initialUrl,
      widget.preferredSourceName,
    ];
    for (final raw in candidates) {
      final value = (raw ?? '').trim().toLowerCase();
      if (value.contains('vidfast.pro') || value.contains('vidfast.net')) {
        return true;
      }
    }
    return false;
  }

  List<PageServerOption> _fallbackVidfastServerOptions() {
    return const <PageServerOption>[];
  }

  List<PageServerOption> _srvButtonServerOptions() {
    return const <PageServerOption>[];
  }

  String _srvButtonCurrentLabel() {
    return '';
  }

  Future<void> _showSrvServerSheet() async {
    // Server switching disabled: no server-selection sheet.
    return;
  }

  Widget _buildVidfastServerSelector() {
    return const SizedBox.shrink();
  }

  Widget _buildVidfastQualitySelector() {
    if (_pageQualityOptions.isEmpty || !_showQuickMediaButtons) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: _pageQualityOptions.map((q) {
          final label = _normalizeQualityLabel(q.label).ifEmpty(q.label);
          final isSelected =
              label == _normalizeQualityLabel(_currentPageQualityLabel ?? '') ||
              q.selected;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => switchQuality(label),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color:
                      isSelected
                          ? Colors.orange.shade700
                          : Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? Colors.white24 : Colors.transparent,
                  ),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  void _updateServerOptions(List<PageServerOption> options) {
    // Server switching disabled: do not store or show server lists.
    if (_pageServerOptions.isNotEmpty && mounted) {
      setState(() => _pageServerOptions = const <PageServerOption>[]);
    } else {
      _pageServerOptions = const <PageServerOption>[];
    }
  }

  Future<void> _switchServer(PageServerOption option) async {
    // Server switching disabled: server switching was removed intentionally.
    return;
  }

  // ✅ FIX 2: _safePipAspectRatio — fixed math, safe clamping
  //    Old bug: fallback 5:12 = 0.4166 < minRatio 0.418410 → still caused error
  //    New: any out-of-range ratio falls back to safe 16:9 directly
  // ─────────────────────────────────────────────────────────────────────────
  Map<String, int> _safePipAspectRatio() {
    // Android PiP requires: 0.418410 ≤ w/h ≤ 2.390000
    // Use slightly stricter bounds to avoid edge cases
    const double minRatio = 0.42;
    const double maxRatio = 2.38;

    int w = _videoAspectW > 0 ? _videoAspectW : 16;
    int h = _videoAspectH > 0 ? _videoAspectH : 9;

    // Validate inputs
    if (w <= 0 || h <= 0) return {'w': 16, 'h': 9};

    final double ratio = w / h;

    // If ratio is outside safe range, always return 16:9 — never risk it
    if (ratio < minRatio || ratio > maxRatio) {
      return {'w': 16, 'h': 9};
    }

    // Reduce to smallest integers via GCD
    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
    final g = gcd(w.abs(), h.abs());
    final rw = w ~/ g;
    final rh = h ~/ g;

    // If reduced values are too large for Android Rational, fall back to 16:9
    if (rw > 239 || rh > 239 || rw <= 0 || rh <= 0) {
      return {'w': 16, 'h': 9};
    }

    // Final safety check on reduced ratio (GCD reduction can theoretically drift)
    final double reducedRatio = rw / rh;
    if (reducedRatio < minRatio || reducedRatio > maxRatio) {
      return {'w': 16, 'h': 9};
    }

    return {'w': rw, 'h': rh};
  }

// ══════════════════════════════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════════════════════════════

  Future<void> _attemptFastExtraction() async {
    try {
      if (mounted) setState(() => _showQualityResolveLoader = true);

      final uri = Uri.parse(widget.initialUrl);
      if (_isvidfastSession) {
        debugPrint('[vidfast] تم تعطيل Fast Extraction الخاص بـ Videasy لهذه الجلسة');
        if (mounted) {
          setState(() => _showQualityResolveLoader = false);
        }
        return;
      }
      if (_isVideasyPlayerUrl(widget.initialUrl)) {
        debugPrint('[Videasy] سيتم الاعتماد على اعتراض الشبكة داخل الـ WebView بدل API القديم');
        if (mounted) {
          setState(() => _showQualityResolveLoader = false);
        }
        return;
      }

      final pathSegments = uri.pathSegments;

      String mediaType = 'movie';
      String tmdbId = '';
      String seasonId = '1';
      String episodeId = '1';

      final embedIndex = pathSegments.indexOf('embed');
      if (embedIndex >= 0 && pathSegments.length > embedIndex + 2) {
        mediaType = pathSegments[embedIndex + 1].toLowerCase();
        tmdbId = pathSegments[embedIndex + 2];

        if (mediaType == 'tv') {
          if (pathSegments.length > embedIndex + 3) {
            seasonId = pathSegments[embedIndex + 3];
          }
          if (pathSegments.length > embedIndex + 4) {
            episodeId = pathSegments[embedIndex + 4];
          }
        }
      } else if (uri.host.toLowerCase().contains('player.videasy.net') && pathSegments.isNotEmpty) {
        mediaType = pathSegments.first.toLowerCase();
        if (mediaType == 'tv') {
          if (pathSegments.length > 1) tmdbId = pathSegments[1];
          if (pathSegments.length > 2) seasonId = pathSegments[2];
          if (pathSegments.length > 3) episodeId = pathSegments[3];
        } else {
          mediaType = 'movie';
          tmdbId = pathSegments.length > 1 ? pathSegments[1] : '';
        }
      } else {
        tmdbId = pathSegments.isNotEmpty ? pathSegments.last : '';
        mediaType = widget.initialUrl.contains('/tv/') ? 'tv' : 'movie';
      }

      if (tmdbId.trim().isEmpty) {
        throw Exception('TMDB ID not found in ${widget.initialUrl}');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final params = <String, String>{
        'mediaType': mediaType,
        'tmdbId': tmdbId,
        '_t': '$timestamp',
      };
      if (mediaType == 'tv') {
        params['episodeId'] = episodeId;
        params['seasonId'] = seasonId;
      }
      final apiEndpoints = [
        '/moviebox/sources-with-title',
        '/cdn/sources-with-title',
        '/myflixerzupcloud/sources-with-title',
      ];

      String? responseBody;
      final dio = Dio();

      for (final endpoint in apiEndpoints) {
        final apiUri = Uri.https('api.videasy.net', endpoint, params);
        final apiUrl = apiUri.toString();
        debugPrint('====== جاري الاتصال: $apiUrl ======');
        try {
          final response = await dio.get(
            apiUrl,
            options: Options(
              headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
                'Origin': 'https://player.videasy.net',
                'Referer': 'https://player.videasy.net/',
                'Accept': 'application/json, text/plain, */*',
              },
              receiveTimeout: const Duration(seconds: 15),
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          debugPrint('API Status: ${response.statusCode} endpoint: $endpoint');
          if (response.statusCode != null &&
              response.statusCode! >= 200 &&
              response.statusCode! < 300 &&
              response.data != null) {
            responseBody = response.data.toString();
            break;
          }
        } catch (e) {
          debugPrint('❌ فشل $endpoint: $e');
        }
      }

      if (responseBody == null) {
        debugPrint('كل الـ endpoints فشلت');
        if (mounted) setState(() => _showQualityResolveLoader = false);
        return;
      }

      String extractQualityLabel(Map<String, dynamic> item, int index) {
        final raw = [
          item['quality'],
          item['label'],
          item['name'],
          item['title'],
          item['file'],
          item['url'],
          item['src'],
        ].map((e) => (e ?? '').toString()).join(' ');
        final normalized = _normalizeQualityLabel(raw);
        if (normalized.trim().isNotEmpty) return normalized;
        switch (index) {
          case 0:
            return '1080p';
          case 1:
            return '720p';
          case 2:
            return '480p';
          default:
            return 'Quality ${index + 1}';
        }
      }

      List<dynamic> sourceItems = const [];
      final data = jsonDecode(responseBody);
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        if (map['sources'] is List) {
          sourceItems = map['sources'] as List<dynamic>;
        } else if (map['data'] is List) {
          sourceItems = map['data'] as List<dynamic>;
        } else if (map['data'] is Map) {
          final dataMap = Map<String, dynamic>.from(map['data'] as Map);
          if (dataMap['sources'] is List) {
            sourceItems = dataMap['sources'] as List<dynamic>;
          }
        }
      }

      final discoveredOptions = <PageQualityOption>[];
      final seenUrls = <String>{};
      String? directUrl;
      var sourceIndex = 0;

      for (final raw in sourceItems.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        final candidate = (item['file'] ?? item['url'] ?? item['src'] ?? '').toString().trim();
        if (candidate.isEmpty) continue;
        final cleanCandidate = candidate.replaceAll(r'\/', '/');
        if (!seenUrls.add(cleanCandidate.toLowerCase())) continue;
        directUrl ??= cleanCandidate;
        final label = extractQualityLabel(item, sourceIndex);
        discoveredOptions.add(PageQualityOption(
          label: label,
          key: 'api_${sourceIndex}_${label.toLowerCase()}',
          url: cleanCandidate,
          selected: discoveredOptions.isEmpty,
        ));
        sourceIndex += 1;
      }

      if (discoveredOptions.isNotEmpty) {
        discoveredOptions.sort((a, b) => _qualityRankLabel(b.label).compareTo(_qualityRankLabel(a.label)));
        _updatePageQualityOptions(discoveredOptions.take(3).toList(growable: false), discoveredOptions.first.label);
      }

      if (directUrl == null || directUrl.isEmpty) {
        debugPrint('الرد لا يحتوي على sources قابلة للتشغيل: $responseBody');
      } else {
        debugPrint('✅ تم العثور على الرابط المباشر: $directUrl');

        _capturePlayableUrl(
          directUrl,
          pageUrl: widget.initialUrl,
          mimeType: _inferMimeType(directUrl),
          qualityLabel: _pageQualityOptions.isNotEmpty ? _pageQualityOptions.first.label : null,
        );
        _capturedVideoPageUrl = widget.initialUrl;
        _lastTrusted = widget.initialUrl;

        if (mounted) {
          setState(() {
            _showQualityResolveLoader = false;
            _videoDetected = true;
          });
        }

        if (widget.downloadOnlyMode) {
          _scheduleInitialDownloadChoicesPrompt();
          return;
        }

        Future.microtask(() => _openNativePlayer(
              force: true,
              replace: true,
              forcedUrl: directUrl,
              forcedPageUrl: widget.initialUrl,
              forcedMimeType: _inferMimeType(directUrl),
            ));
        return;
      }
    } catch (e) {
      debugPrint('❌ فشل الاتصال بالـ API: $e');
    }

    if (mounted) setState(() => _showQualityResolveLoader = false);
  }


  String? _fastExtractIframeSrc(String html) {
    final patterns = <RegExp>[
      RegExp(r"""<iframe[^>]+src=["']([^"']+)["']""", caseSensitive: false),
      RegExp(r"""<iframe[^>]+data-src=["']([^"']+)["']""", caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) {
        final src = match.group(1)?.trim() ?? '';
        if (src.isNotEmpty &&
            !src.contains('googlesyndication') &&
            !src.contains('doubleclick') &&
            !src.contains('youtube')) {
          if (src.startsWith('//')) return 'https:$src';
          if (src.startsWith('/')) {
            final base = Uri.parse(widget.initialUrl);
            return '${base.scheme}://${base.host}$src';
          }
          return src;
        }
      }
    }
    return null;
  }

  Future<String?> _fetchInnerEmbedUrl(String embedUrl) async {
    try {
      final dio = Dio();
      final response = await dio.get<String>(
        embedUrl,
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/124.0.0.0 Safari/537.36',
            'Referer': widget.initialUrl,
            'Origin': Uri.tryParse(widget.initialUrl)?.origin ?? widget.initialUrl,
          },
          receiveTimeout: const Duration(seconds: 12),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (response.data == null || response.data!.isEmpty) return null;

      String innerHtml = response.data!;
      if (innerHtml.contains("eval(function(p,a,c,k,e,d)") ||
          innerHtml.contains("eval(function(p,a,c,k,e,r)")) {
        innerHtml = _jsUnpacker(innerHtml);
      }

      return _fastExtractMediaUrl(innerHtml) ?? _fastExtractFromJsonBlob(innerHtml);
    } catch (_) {
      return null;
    }
  }

  String? _fastExtractMediaUrl(String html) {
    final patterns = <RegExp>[
      RegExp(
        r'''(?:file|src|source|url|hls|stream|m3u8)\s*[:=]\s*['"](https?://[^'"]{10,}\.m3u8[^'"]*)['"]''',
        caseSensitive: false,
      ),
      RegExp(
        r'''(?:file|src|source|url|hls|stream)\s*[:=]\s*['"](https?://[^'"]{10,}\.mp4[^'"]*)['"]''',
        caseSensitive: false,
      ),
      RegExp(
        r'''"(?:file|src|url|hls|stream|source)"\s*:\s*"(https?://[^"]{10,}\.m3u8[^"]*)"''',
        caseSensitive: false,
      ),
      RegExp(
        r'''"(?:file|src|url|stream|source)"\s*:\s*"(https?://[^"]{10,}\.mp4[^"]*)"''',
        caseSensitive: false,
      ),
      RegExp(r"""(https?://[^\s'"<>\\]{10,}\.m3u8[^\s'"<>\\]*)"""),
      RegExp(r"""(https?://[^\s'"<>\\]{10,}\.mp4[^\s'"<>\\]*)"""),
      RegExp(
        r"""(https?://[^\s'"<>\\]*(?:cdn|stream|media|hls|vod)[^\s'"<>\\]*\.m3u8[^\s'"<>\\]*)""",
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) {
        final raw = match.group(1)?.trim() ?? '';
        if (raw.isEmpty) continue;
        final cleaned = raw
            .replaceAll(r'\/', '/')
            .replaceAll(r'\/\/', '//')
            .replaceAll('\\u0026', '&');
        if (_looksLikePlayableMediaUrl(cleaned) && !_isYouTubeUrl(cleaned)) {
          return cleaned;
        }
      }
    }
    return null;
  }

  String? _fastExtractFromJsonBlob(String html) {
    final jsonPatterns = <RegExp>[
      RegExp(r'sources\s*:\s*\[([^\]]{20,})\]', caseSensitive: false),
      RegExp(r'playlist\s*:\s*\[([^\]]{20,})\]', caseSensitive: false),
      RegExp(r'"sources"\s*:\s*\[([^\]]{20,})\]', caseSensitive: false),
    ];

    for (final pattern in jsonPatterns) {
      final match = pattern.firstMatch(html);
      if (match == null) continue;
      final content = match.group(1) ?? '';

      final urlPattern = RegExp(
        r"""(https?://[^\s'"\\]{10,}\.(?:m3u8|mp4)[^\s'"\\]*)""",
        caseSensitive: false,
      );
      final urlMatch = urlPattern.firstMatch(content);
      if (urlMatch != null) {
        final raw = urlMatch.group(1)?.trim() ?? '';
        if (raw.isNotEmpty && _looksLikePlayableMediaUrl(raw) && !_isYouTubeUrl(raw)) {
          return raw.replaceAll(r'\/', '/');
        }
      }
    }
    return null;
  }

  void _handleFastExtractionSuccess(String mediaUrl, String pageUrl) {
    if (!mounted) return;
    debugPrint('[FastExtract] ✅ تم العثور على رابط: $mediaUrl');

    final cleanUrl = mediaUrl.trim().replaceAll(r'\/', '/');
    _capturePlayableUrl(
      cleanUrl,
      pageUrl: pageUrl,
      mimeType: _inferMimeType(cleanUrl),
    );
    _capturedVideoPageUrl = pageUrl;
    _lastTrusted = pageUrl;

    setState(() {
      _showQualityResolveLoader = false;
      _videoDetected = true;
    });

    Future.microtask(() => _openNativePlayer(
          force: true,
          replace: true,
          forcedUrl: cleanUrl,
          forcedPageUrl: pageUrl,
          forcedMimeType: _inferMimeType(cleanUrl),
        ));
  }

  String _jsUnpacker(String packedJS) {
    try {
      final regExp = RegExp(
        r'''\}\s*\(\s*['"]([^'"]+)['"]\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*['"]([^'"]+)['"]\.split\(['"](\|)['"]\)''',
      );
      final match = regExp.firstMatch(packedJS);

      if (match == null) {
        return _jsUnpackerAlt(packedJS);
      }

      String p = match.group(1)!;
      int a = int.parse(match.group(2)!);
      int c = int.parse(match.group(3)!);
      final List<String> k = match.group(4)!.split('|');

      String decode(int n) {
        final base = n < a
            ? ''
            : decode(n ~/ a);
        final remainder = n % a;
        final char = remainder > 35
            ? String.fromCharCode(remainder + 29)
            : remainder.toRadixString(36);
        return base + char;
      }

      while (c-- > 0) {
        if (c < k.length && k[c].isNotEmpty) {
          p = p.replaceAll(RegExp('\\b${RegExp.escape(decode(c))}\\b'), k[c]);
        }
      }
      return p;
    } catch (e) {
      debugPrint('[JsUnpacker] خطأ: $e');
      return packedJS;
    }
  }

  String _jsUnpackerAlt(String packedJS) {
    try {
      final regExp = RegExp(
        r'''eval\(function\(p,a,c,k,e,(?:d|r)\)\{.*?\}\('([^']+)',(\d+),(\d+),'([^']+)'\.split\('\|'\)''',
        dotAll: true,
      );
      final match = regExp.firstMatch(packedJS);
      if (match == null) return packedJS;

      String p = match.group(1)!;
      int a = int.parse(match.group(2)!);
      int c = int.parse(match.group(3)!);
      final List<String> k = match.group(4)!.split('|');

      String decode(int n) {
        return (n < a ? '' : decode(n ~/ a)) +
            ((n % a) > 35
                ? String.fromCharCode((n % a) + 29)
                : (n % a).toRadixString(36));
      }

      while (c-- > 0) {
        if (c < k.length && k[c].isNotEmpty) {
          p = p.replaceAll(RegExp('\\b${RegExp.escape(decode(c))}\\b'), k[c]);
        }
      }
      return p;
    } catch (_) {
      return packedJS;
    }
  }

// ══════════════════════════════════════════════════════════════════════════════
//  END OF FAST EXTRACTION METHODS
// ══════════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();

    if (!_isvidfastSession) Future.microtask(() => _attemptFastExtraction());
    // ─────────────────────────────────────────────────────────────────────────

    WidgetsBinding.instance.addObserver(this);

    _rememberAllowedHost(widget.initialUrl);
    _lastTrusted = widget.initialUrl;
    _currentHost = Uri.tryParse(widget.initialUrl)?.host;
    _currentPageUrl = widget.initialUrl;
    _capturedVideoPageUrl = widget.initialUrl;
    if (widget.downloadOnlyMode) {
      _revealHiddenLaunchUi = true;
    }
    if (widget.launchHidden && !widget.downloadOnlyMode && !widget.autoDownloadPrompt) {
      _pendingNativeOpenOnPlayableCapture = true;
    }
    if ((_isVideasyPlayerUrl(widget.initialUrl) || _isvidfastSession) &&
        _hasTmdbContext) {
      Future.delayed(
        Duration(milliseconds: widget.downloadOnlyMode ? 400 : 1200),
        () {
          if (!mounted) return;
          unawaited(_maybeFetchLatestSourceBundle(force: true));
        },
      );
    }
    if (widget.initialSubtitleTracks.isNotEmpty) {
      _externalSubtitleTracks = _mergeSubtitleTrackMaps(widget.initialSubtitleTracks);
    }
    if (_hasTmdbContext) {
      if (_isvidfastSession) {
        _pageServerOptions = const <PageServerOption>[];
        _currentServerLabel = '';
      } else {
        _pageServerOptions = _mergeServerOptionLists(_buildAppSourceServerOptions(), const <PageServerOption>[]);
        _currentServerLabel = _preferredAppSource().name;
      }
      _didApplyInitialPreferredSource = true;
      if (!widget.skipInitialSubtitleFetch && widget.deferredSubtitleTracksFuture == null) {
        Future.microtask(() => _refreshExternalSubtitles(force: true));
      } else {
        Future.microtask(() => _refreshExternalSubtitles(force: true));
      }
    }
    if (widget.deferredSubtitleTracksFuture != null) {
      unawaited(widget.deferredSubtitleTracksFuture!.then((tracks) async {
        if (!mounted || tracks.isEmpty) return;
        final mergedTracks = _mergeSubtitleTrackMaps([
          ..._externalSubtitleTracks,
          ...tracks,
        ]);
        if (mounted) {
          setState(() => _externalSubtitleTracks = mergedTracks);
        } else {
          _externalSubtitleTracks = mergedTracks;
        }
        _requestNativeSubtitleSync();
        final lookupKey = '${widget.mediaType?.name ?? ''}|${widget.tmdbId ?? ''}|${widget.season ?? ''}|${widget.episode ?? ''}';
        if (lookupKey.trim().isNotEmpty) {
          _lastSubtitleFetchKey = lookupKey;
        }
        unawaited(_persistCapturedSubtitlesLight(tracks));
        await _updateNativePlayerOptions();
      }).catchError((_) {}));
    }

    if (!_useLightHiddenWebView) {
      _ptr = PullToRefreshController(
        settings: PullToRefreshSettings(color: const Color(0xFFB3202A)),
        onRefresh: () async => await _wc?.reload(),
      );
    } else {
      _ptr = null;
    }



    _pip.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'onPipChanged') {
        final isInPip = call.arguments as bool? ?? false;
        setState(() => _inPip = isInPip);

        if (!isInPip && !_nativePlayerActive) {
          await _restoreUI();
        }
      } else if (call.method == 'onNativePlayerChanged') {
        final active = call.arguments as bool? ?? false;
        setState(() {
          _nativePlayerActive = active;
          if (!active) _lastNativePlayerUrl = null;
          _videoPlaying = active ? false : _videoPlaying;
        });
        if (active) {
          _preventAutoReopenAfterNativeClose = false;
          _suppressAutoOpenUntil = 0;
          if (_pendingSubtitleOptionsSync || _externalSubtitleTracks.isNotEmpty) {
            _pendingSubtitleOptionsSync = false;
            unawaited(_updateNativePlayerOptions());
          }
          if (_nativePlayerShellOnly || _nativePlayerShellRequested) {
            _nativePlayerOpening = false;
            final pendingUrl = (_pendingShellMediaUrl ?? '').trim();
            if (pendingUrl.isNotEmpty) {
              final pageUrl = _pendingShellPageUrl;
              final mimeType = _pendingShellMimeType;
              _pendingShellMediaUrl = null;
              _pendingShellPageUrl = null;
              _pendingShellMimeType = null;
              await _attachSourceToNativePlayer(
                mediaUrl: pendingUrl,
                pageUrl: pageUrl ?? _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted,
                mimeType: mimeType,
              );
            }
          } else {
            await _suspendCaptureEngine();
            _scheduleOriginalPlayerHardPause();
          }
        } else {
          _nativePlayerShellOnly = false;
          _nativePlayerShellRequested = false;
          _pendingShellMediaUrl = null;
          _pendingShellPageUrl = null;
          _pendingShellMimeType = null;
          _preventAutoReopenAfterNativeClose = true;
          _exitHiddenRouteAfterNativeClose = widget.launchHidden && !widget.downloadOnlyMode && !widget.autoDownloadPrompt;
          _pendingNativeOpenOnPlayableCapture = false;
          _pendingPlayableCaptureToken++;
          _pendingSubtitleOptionsSync = false;
          _manualPlayAfterQualitySwitchPending = false;
          _qualitySwitchPending = false;
          _serverSwitchPending = false;
          _qualityDownloadSwitchPending = false;
          _nativePlayerOpening = false;
          _lastAttachRequestUrl = '';
          _lastAttachRequestAt = 0;
          _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 15000;
          await _releaseOriginalSitePlayerBlock();
          await _restoreUI();
          if (widget.launchHidden && !widget.downloadOnlyMode && !widget.autoDownloadPrompt) {
            try {
              await _wc?.stopLoading();
            } catch (_) {}
            _popHiddenPlayerRouteSoon();
            return;
          }
          _resumeCaptureEngine();
          await _returnToWatchPage();
        }
      } else if (call.method == 'onSubtitleRefreshRequested') {
        unawaited(_forceRequestMoreArabic1Subtitles());
      } else if (call.method == 'onNativePipError') {
        _nativePlayerOpening = false;
        final message = call.arguments?.toString();
        if (await _handleNativeDecoderFallback(message)) return;
        final cleanMessage = message?.replaceFirst(RegExp(r'^DECODER_CAPABILITY:'), '').trim();
        if (cleanMessage != null && cleanMessage.isNotEmpty) _showSnack('⚠️ $cleanMessage');
      } else if (call.method == 'onQualitySelected') {
        final arg = call.arguments;
        if (arg is Map) {
          final option = PageQualityOption.fromMap(Map<String, dynamic>.from(arg));
          await _switchPageQuality(option);
        }
      } else if (call.method == 'onServerSelected') {
        // Server switching disabled: ignore native server-switch requests.
      }
    });

    if (widget.launchHidden && !widget.downloadOnlyMode && !widget.autoDownloadPrompt) {
      Future.microtask(() async {
        await _openNativePlayerShell();
        if (!mounted) return;
      });
    }
  }

  @override
  void dispose() {
    _backgroundDownloadSyncTimer?.cancel();
    _backgroundDownloadSyncTimer = null;
    _wc = null;
    _delayedQualityHarvestTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _restoreUI();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      Future.microtask(_pauseNativePlayerForAppBackground);
      return;
    }

    if (state == AppLifecycleState.resumed && mounted) {
      _nativePauseSentForBackground = false;
      setState(() => _inPip = false);

      if (_exitHiddenRouteAfterNativeClose && widget.launchHidden && !widget.downloadOnlyMode && !widget.autoDownloadPrompt) {
        _popHiddenPlayerRouteSoon();
        return;
      }

      if (!_nativePlayerActive && !_preventAutoReopenAfterNativeClose) {
        Future.microtask(() async {
          await _returnToWatchPage();
        });
      }
    }
  }

  Future<void> _pauseNativePlayerForAppBackground() async {
    if (_inPip) return;
    if (!_nativePlayerActive && !_nativePlayerOpening) return;
    if (_nativePauseSentForBackground) return;

    _nativePauseSentForBackground = true;

    Future<bool> callNativePause(String method, [Map<String, dynamic>? args]) async {
      try {
        final result = await _pip.invokeMethod<bool>(method, args);
        return result != false;
      } on MissingPluginException {
        return false;
      } catch (_) {
        return false;
      }
    }

    if (await callNativePause('pauseNativePlayer', {
      'keepOpen': true,
      'reason': 'app_lifecycle',
    })) {
      return;
    }

    if (await callNativePause('setNativePlayerPaused', {
      'paused': true,
      'keepOpen': true,
      'reason': 'app_lifecycle',
    })) {
      return;
    }

    await callNativePause('pausePlayer', {
      'keepOpen': true,
      'reason': 'app_lifecycle',
    });
  }

  String? _normalizeWatchReturnUrl(String? rawUrl) {
    final value = (rawUrl ?? '').trim();
    if (value.isEmpty) return null;

    final uri = Uri.tryParse(value);
    if (uri == null) return value;

    final cleaned = uri.replace(fragment: '');
    return cleaned.toString();
  }

  bool _isWatchLikeUrl(String? rawUrl) {
    final url = (rawUrl ?? '').toLowerCase();
    if (url.isEmpty) return false;
    return url.contains('/watch/') ||
        url.contains('play=true') ||
        url.contains('%d9%85%d8%b4%d8%a7%d9%87');
  }

  void _rememberStableWatchUrl([String? rawUrl]) {
    final normalized = _normalizeWatchReturnUrl(rawUrl);
    if (normalized == null || normalized.isEmpty) return;
    if (_isWatchLikeUrl(normalized)) {
      _lastStableWatchUrl = normalized;
    }
  }

  Future<void> _returnToWatchPage() async {
    if (_wc == null) return;

    final target = _lastStableWatchUrl ??
        _normalizeWatchReturnUrl(_capturedVideoPageUrl) ??
        _normalizeWatchReturnUrl(_currentPageUrl) ??
        _normalizeWatchReturnUrl(_lastTrusted);

    if (target == null || target.isEmpty) return;

    final current = (await _wc!.getUrl())?.toString();
    final currentNormalized = _normalizeWatchReturnUrl(current);

    if (currentNormalized == target) {
      try {
        await _wc!.evaluateJavascript(source: """
          (function(){
            try {
              if (window.location.hash) {
                history.replaceState(null, '', window.location.pathname + window.location.search);
              }
            } catch(e) {}
          })();
        """);
      } catch (_) {}
      return;
    }

    try {
      await _wc!.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(target),
          headers: const {'User-Agent': _ua},
        ),
      );
    } catch (_) {}
  }

  Future<String?> _createVideoThumbnail(String videoPath) async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final tempDir = await getTemporaryDirectory();
      return await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 420,
        quality: 85,
      );
    } catch (_) {
      return null;
    }
  }


  Future<String?> _existingManagedDownloadState({
    required String finalPath,
    required String tempPath,
  }) async {
    final normalizedFinalPath = finalPath.trim();
    final normalizedTempPath = tempPath.trim();

    if (normalizedFinalPath.isNotEmpty) {
      try {
        final finalFile = File(normalizedFinalPath);
        if (await finalFile.exists() && await finalFile.length() > 0) {
          return 'done';
        }
      } catch (_) {}
    }

    if (normalizedTempPath.isNotEmpty) {
      try {
        final tempFile = File(normalizedTempPath);
        if (await tempFile.exists()) {
          return 'active';
        }
      } catch (_) {}
    }

    for (final item in _downloads) {
      final sameFinal = normalizedFinalPath.isNotEmpty &&
          (item.finalPath ?? '').trim() == normalizedFinalPath;
      final sameTemp = normalizedTempPath.isNotEmpty &&
          (item.tempPath ?? item.savedPath ?? '').trim() == normalizedTempPath;
      if (!sameFinal && !sameTemp) continue;

      final status = item.status.trim().toLowerCase();
      if (status == 'done') return 'done';
      if (status == 'preparing' || status == 'downloading' || status == 'paused') {
        return 'active';
      }
    }

    try {
      final snapshots = await BackgroundDownloadBridge.list(source: _backgroundDownloadSource);
      for (final snap in snapshots) {
        final sameFinal = normalizedFinalPath.isNotEmpty &&
            snap.finalPath.trim() == normalizedFinalPath;
        final sameTemp = normalizedTempPath.isNotEmpty &&
            snap.tempPath.trim() == normalizedTempPath;
        if (!sameFinal && !sameTemp) continue;

        final status = snap.status.trim().toLowerCase();
        if (status == 'done') return 'done';
        if (status == 'preparing' || status == 'downloading' || status == 'paused') {
          return 'active';
        }
      }
    } catch (_) {}

    return null;
  }

  Future<void> _startDownload(String url, String fileName, {String? qualityLabel}) async {
    _notifyDownloadStatus('downloading');

    final inferred = _inferFileName(url, fileName);
    final dot = inferred.lastIndexOf('.');
    final extension = dot > 0 ? inferred.substring(dot) : '.mp4';
    final safeName = _buildManagedDownloadFileName(
      extension: extension,
      qualityLabel: qualityLabel,
    );
    final dir = await _downloadTargetDirectory();
    final fullPath = '${dir.path}/$safeName';
    final tempPath = '$fullPath.downloading';

    final existingState = await _existingManagedDownloadState(
      finalPath: fullPath,
      tempPath: tempPath,
    );
    if (existingState == 'done') {
      _clearPreparingDownloadPlaceholder();
      _showSnack('✅ الملف محمّل بنفس الجودة');
      _notifyDownloadStatus('done');
      _finishHiddenDownloadRoute('done');
      return;
    }
    if (existingState == 'active' || _discoveredDownloadUrls.contains(url)) {
      _clearPreparingDownloadPlaceholder();
      _showSnack('⬇️ جاري تحميل هذا الملف بالفعل');
      _notifyDownloadStatus('downloading');
      _finishHiddenDownloadRoute('queued');
      return;
    }

    _discoveredDownloadUrls.add(url);
    _clearPreparingDownloadPlaceholder();

    final item = DownloadItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url,
      fileName: safeName,
      savedPath: tempPath,
      tempPath: tempPath,
      finalPath: fullPath,
      qualityLabel: qualityLabel,
      kind: 'direct',
      pageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted,
      status: 'preparing',
    );

    final subtitleDownloadFuture = _downloadMatchingSubtitleSidecar(fullPath);
    await _persistActiveDownloadLibraryEntry(
      tempPath: tempPath,
      finalPath: fullPath,
      fileName: safeName,
      qualityLabel: qualityLabel,
      status: 'preparing',
      progress: 0,
      downloadId: item.id,
    );

    if (mounted) {
      setState(() {
        _downloads.insert(0, item);
      });
    }

    final headers = await _buildSmartDownloadHeaders(url, pageUrl: item.pageUrl);
    final ok = await _enqueueBackgroundDirectDownload(
      item,
      headers: headers,
      pageUrl: item.pageUrl,
      qualityLabel: qualityLabel,
    );

    if (!ok) {
      _discoveredDownloadUrls.remove(url);
      await _persistDownloadItemState(item, statusOverride: 'error');
      _markPreparingDownloadPlaceholderError('فشل بدء التحميل بالخلفية');
      return;
    }

    unawaited(subtitleDownloadFuture);
    await _persistDownloadItemState(item, statusOverride: 'downloading');
    _notifyDownloadStatus('idle');
    _finishHiddenDownloadRoute('queued');
  }




  Future<Map<String, String>> _buildSmartDownloadHeaders(String mediaUrl, {String? pageUrl}) async {
    final headers = await _buildPipHeaders(mediaUrl, pageUrl: pageUrl);
    headers['Accept'] = headers['Accept']?.trim().isNotEmpty == true ? headers['Accept']! : '*/*';
    headers['Connection'] = 'keep-alive';
    headers['Referer'] = (headers['Referer'] ?? '').trim().isNotEmpty
        ? headers['Referer']!
        : _buildReferer(mediaUrl);
    headers['Origin'] = (headers['Origin'] ?? '').trim().isNotEmpty
        ? headers['Origin']!
        : _buildOriginForUrl(mediaUrl, refererOverride: headers['Referer']);
    return headers;
  }

  PageQualityOption? _pickPreferredHlsQualityOption(List<PageQualityOption> options, String preferredLabel) {
    if (options.isEmpty) return null;
    final wanted = _normalizeQualityLabel(preferredLabel);
    if (wanted.isNotEmpty) {
      for (final option in options) {
        if (_normalizeQualityLabel(option.label) == wanted) return option;
      }
    }
    final sorted = List<PageQualityOption>.from(options)
      ..sort((a, b) => _qualityRankLabel(b.label).compareTo(_qualityRankLabel(a.label)));
    return sorted.first;
  }

  List<PageQualityOption> _extractHlsMasterQualityOptions(String masterUrl, String body) {
    final lines = body.split(RegExp(r'\r?\n'));
    final out = <PageQualityOption>[];
    final seen = <String>{};
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
      final attrs = _parseM3uAttributes(line);
      String? nextUrl;
      for (var j = i + 1; j < lines.length; j++) {
        final candidate = lines[j].trim();
        if (candidate.isEmpty) continue;
        if (!candidate.startsWith('#')) {
          nextUrl = candidate;
          break;
        }
      }
      if (nextUrl == null || nextUrl.trim().isEmpty) continue;
      final resolved = _resolvePlaylistUrl(masterUrl, nextUrl);
      final resolution = attrs['RESOLUTION'] ?? '';
      final heightMatch = RegExp(r'\d+x(\d+)', caseSensitive: false).firstMatch(resolution);
      final label = heightMatch != null
          ? '${heightMatch.group(1)}p'
          : ((attrs['NAME']?.trim().isNotEmpty == true) ? attrs['NAME']!.trim() : 'Auto');
      final normalized = _normalizeQualityLabel(label);
      final dedupe = '${normalized.toLowerCase()}|${resolved.toLowerCase()}';
      if (!seen.add(dedupe)) continue;
      out.add(PageQualityOption(
        label: normalized,
        key: 'dl_hls_${normalized.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_${out.length}',
        url: resolved,
        selected: out.isEmpty,
      ));
    }
    return out;
  }

  Future<Map<String, dynamic>?> _resolveHlsPlaylistForDownload(
    String manifestUrl,
    Map<String, String> headers, {
    String? preferredQualityLabel,
  }) async {
    var currentUrl = manifestUrl.trim();
    if (currentUrl.isEmpty) return null;

    final masterCandidates = _buildHlsManifestCandidates(currentUrl);
    for (final candidate in masterCandidates) {
      final body = await _fetchPlaylistBody(candidate, headers);
      if (body == null || body.trim().isEmpty) continue;
      if (_playlistLooksLikeMaster(body)) {
        final options = _extractHlsMasterQualityOptions(candidate, body);
        final chosen = _pickPreferredHlsQualityOption(options, preferredQualityLabel ?? '');
        if (chosen == null || (chosen.url ?? '').trim().isEmpty) return null;
        final playlistBody = await _fetchPlaylistBody(chosen.url!.trim(), headers);
        if (playlistBody == null || playlistBody.trim().isEmpty) return null;
        return {
          'playlistUrl': chosen.url!.trim(),
          'playlistBody': playlistBody,
          'qualityLabel': _normalizeQualityLabel(chosen.label),
        };
      }
    }

    for (var depth = 0; depth < 3; depth++) {
      final body = await _fetchPlaylistBody(currentUrl, headers);
      if (body == null || body.trim().isEmpty) return null;
      if (!_playlistLooksLikeMaster(body)) {
        return {
          'playlistUrl': currentUrl,
          'playlistBody': body,
          'qualityLabel': _normalizeQualityLabel(preferredQualityLabel ?? ''),
        };
      }
      final options = _extractHlsMasterQualityOptions(currentUrl, body);
      final chosen = _pickPreferredHlsQualityOption(options, preferredQualityLabel ?? '');
      if (chosen == null || (chosen.url ?? '').trim().isEmpty) return null;
      currentUrl = chosen.url!.trim();
      preferredQualityLabel = _normalizeQualityLabel(chosen.label);
    }
    return null;
  }

  Map<String, dynamic> _buildHlsSegmentEntry(
    String playlistUrl,
    String rawUri, {
    String? byterange,
    int? previousRangeEnd,
  }) {
    final resolved = _resolvePlaylistUrl(playlistUrl, rawUri);
    int? rangeStart;
    int? rangeEnd;
    final spec = byterange?.trim() ?? '';
    if (spec.isNotEmpty) {
      final match = RegExp(r'^(\d+)(?:@(\d+))?$').firstMatch(spec);
      final length = int.tryParse(match?.group(1) ?? '');
      final explicitStart = int.tryParse(match?.group(2) ?? '');
      if (length != null && length > 0) {
        rangeStart = explicitStart ?? ((previousRangeEnd ?? -1) + 1);
        rangeEnd = rangeStart + length - 1;
      }
    }
    return {
      'url': resolved,
      'rangeStart': rangeStart,
      'rangeEnd': rangeEnd,
      'key': rangeStart != null && rangeEnd != null
          ? '$resolved|$rangeStart-$rangeEnd'
          : resolved,
    };
  }

  Map<String, dynamic>? _parseHlsMediaPlaylist(String playlistUrl, String body) {
    final segmentEntries = <Map<String, dynamic>>[];
    Map<String, dynamic>? initEntry;
    final lastRangeEndByUrl = <String, int>{};
    var encrypted = false;
    var endList = false;
    var inferredExt = '.ts';
    String? pendingByteRange;
    var targetDuration = 4;
    var mediaSequence = 0;

    for (final rawLine in body.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-KEY:')) {
        final upper = line.toUpperCase();
        if (!upper.contains('METHOD=NONE')) {
          encrypted = true;
        }
        continue;
      }
      if (line.startsWith('#EXT-X-ENDLIST')) {
        endList = true;
        continue;
      }
      if (line.startsWith('#EXT-X-TARGETDURATION:')) {
        final idx = line.indexOf(':');
        final parsed = idx >= 0 ? int.tryParse(line.substring(idx + 1).trim()) : null;
        if (parsed != null && parsed > 0) targetDuration = parsed;
        continue;
      }
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        final idx = line.indexOf(':');
        final parsed = idx >= 0 ? int.tryParse(line.substring(idx + 1).trim()) : null;
        if (parsed != null && parsed >= 0) mediaSequence = parsed;
        continue;
      }
      if (line.startsWith('#EXT-X-BYTERANGE:')) {
        final idx = line.indexOf(':');
        pendingByteRange = idx >= 0 ? line.substring(idx + 1).trim() : null;
        continue;
      }
      if (line.startsWith('#EXT-X-MAP:')) {
        final attrs = _parseM3uAttributes(line);
        final uri = attrs['URI'];
        if (uri != null && uri.trim().isNotEmpty) {
          final resolvedInit = _resolvePlaylistUrl(playlistUrl, uri);
          initEntry = _buildHlsSegmentEntry(
            playlistUrl,
            uri,
            byterange: attrs['BYTERANGE'],
            previousRangeEnd: lastRangeEndByUrl[resolvedInit],
          );
          final initRangeEnd = initEntry['rangeEnd'];
          if (initRangeEnd is int) {
            lastRangeEndByUrl[resolvedInit] = initRangeEnd;
          }
          final lower = resolvedInit.toLowerCase();
          if (lower.contains('.m4s') || lower.contains('.mp4') || lower.contains('.m4v')) {
            inferredExt = '.mp4';
          }
        }
        continue;
      }
      if (line.startsWith('#')) continue;
      final resolved = _resolvePlaylistUrl(playlistUrl, line);
      final entry = _buildHlsSegmentEntry(
        playlistUrl,
        line,
        byterange: pendingByteRange,
        previousRangeEnd: lastRangeEndByUrl[resolved],
      );
      pendingByteRange = null;
      final rangeEnd = entry['rangeEnd'];
      if (rangeEnd is int) {
        lastRangeEndByUrl[resolved] = rangeEnd;
      }
      segmentEntries.add(entry);
      final lower = resolved.toLowerCase();
      if (lower.contains('.m4s') || lower.contains('.mp4') || lower.contains('.m4v')) {
        inferredExt = '.mp4';
      }
    }
    if (segmentEntries.isEmpty && initEntry == null) return null;
    return {
      'segmentEntries': segmentEntries,
      'initEntry': initEntry,
      'encrypted': encrypted,
      'fileExt': inferredExt,
      'endList': endList,
      'targetDuration': targetDuration,
      'mediaSequence': mediaSequence,
    };
  }

  Future<void> _startHlsDownload(
    String manifestUrl, {
    String? qualityLabel,
    String? pageUrl,
  }) async {
    _notifyDownloadStatus('downloading');

    final normalizedLabel = _normalizeQualityLabel(qualityLabel ?? '');
    final headers = await _buildSmartDownloadHeaders(manifestUrl, pageUrl: pageUrl);
    final resolved = await _resolveHlsPlaylistForDownload(
      manifestUrl,
      headers,
      preferredQualityLabel: normalizedLabel,
    );
    if (resolved == null) {
      _markPreparingDownloadPlaceholderError('تعذّر تحليل رابط الجودة المطلوبة');
      _showSnack('⚠️ تعذّر تحليل رابط الجودة المطلوبة');
      return;
    }

    final playlistUrl = _canonicalizevidfastWorkersUrl((resolved['playlistUrl'] ?? '').toString().trim());
    final playlistBody = (resolved['playlistBody'] ?? '').toString();
    final initialParsed = _parseHlsMediaPlaylist(playlistUrl, playlistBody);
    if (initialParsed == null) {
      _markPreparingDownloadPlaceholderError('لم أجد مقاطع قابلة للتحميل لهذه الجودة');
      _showSnack('⚠️ لم أجد مقاطع قابلة للتحميل لهذه الجودة');
      return;
    }
    if (initialParsed['encrypted'] == true) {
      _markPreparingDownloadPlaceholderError('هذا البث مشفّر ولا يمكن تنزيله بالطريقة المباشرة');
      _showSnack('⚠️ هذا البث مشفّر ولا يمكن تنزيله بالطريقة المباشرة');
      return;
    }

    var fileExt = (initialParsed['fileExt'] ?? '.mp4').toString();
    if (fileExt.trim().isEmpty || fileExt.toLowerCase() == '.ts') {
      fileExt = '.mp4';
    }
    final finalLabel = _normalizeQualityLabel((resolved['qualityLabel'] ?? '').toString().ifEmpty(normalizedLabel));
    final safeName = _buildManagedDownloadFileName(
      extension: fileExt,
      qualityLabel: finalLabel,
    );
    final dedupeKey = '$playlistUrl|${finalLabel.toLowerCase()}';

    final dir = await _downloadTargetDirectory();
    final fullPath = '${dir.path}/$safeName';
    final tempPath = '$fullPath.downloading';
    final existingState = await _existingManagedDownloadState(
      finalPath: fullPath,
      tempPath: tempPath,
    );
    if (existingState == 'done') {
      _clearPreparingDownloadPlaceholder();
      _showSnack('✅ الملف محمّل بنفس الجودة');
      _notifyDownloadStatus('done');
      _finishHiddenDownloadRoute('done');
      return;
    }
    if (existingState == 'active' || _discoveredDownloadUrls.contains(dedupeKey)) {
      _clearPreparingDownloadPlaceholder();
      _showSnack('⬇️ جاري تحميل هذا الملف بالفعل');
      _notifyDownloadStatus('downloading');
      _finishHiddenDownloadRoute('queued');
      return;
    }

    _discoveredDownloadUrls.add(dedupeKey);
    _clearPreparingDownloadPlaceholder();
    final item = DownloadItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: playlistUrl,
      fileName: safeName,
      savedPath: tempPath,
      tempPath: tempPath,
      finalPath: fullPath,
      qualityLabel: finalLabel,
      kind: 'hls',
      pageUrl: pageUrl,
      status: 'preparing',
    );

    final subtitleDownloadFuture = _downloadMatchingSubtitleSidecar(fullPath);
    await _persistActiveDownloadLibraryEntry(
      tempPath: tempPath,
      finalPath: fullPath,
      fileName: safeName,
      qualityLabel: finalLabel,
      status: 'preparing',
      progress: 0,
      downloadId: item.id,
    );

    if (mounted) {
      setState(() {
        _downloads.insert(0, item);
      });
    }

    final ok = await _enqueueBackgroundHlsDownload(
      item,
      headers: headers,
      pageUrl: pageUrl,
      qualityLabel: finalLabel,
    );

    if (!ok) {
      _discoveredDownloadUrls.remove(dedupeKey);
      await _persistDownloadItemState(item, statusOverride: 'error');
      _markPreparingDownloadPlaceholderError('فشل بدء تحميل HLS بالخلفية');
      return;
    }

    unawaited(subtitleDownloadFuture);
    await _persistDownloadItemState(item, statusOverride: 'downloading');
    _notifyDownloadStatus('idle');
    _finishHiddenDownloadRoute('queued');
  }


  Future<void> _startSmartDownloadFromPlayable(
    String url, {
    String? qualityLabel,
    String? pageUrl,
  }) async {
    final target = url.trim();
    final targetLower = target.toLowerCase();
    if (target.isEmpty) return;
    _notifyDownloadStatus('downloading');
    if (_isTsSegmentUrl(target)) {
      _markPreparingDownloadPlaceholderError('تم رفض مقطع TS، وسيتم انتظار الرابط الكامل');
      _showSnack('⚠️ تم رفض رابط TS الجزئي');
      return;
    }
    if (_looksLikeSubtitleUrl(target)) {
      _markPreparingDownloadPlaceholderError('تم تجاهل رابط ترجمة بدل الفيديو');
      _showSnack('⚠️ تم تجاهل رابط ترجمة، وسيتم تحميل الفيديو فقط من اختيار الجودة');
      return;
    }
    final normalizedLabel = _normalizeQualityLabel(qualityLabel ?? '');

    final cachedDirect = _capturedMedia.firstWhere(
      (item) {
        if (!_sameWatchPage(item.pageUrl)) return false;
        if (!item.isDirectFile) return false;
        if (_isTsSegmentUrl(item.url)) return false;
        if (normalizedLabel.isEmpty) return true;
        return _normalizeQualityLabel(item.qualityLabel ?? '') == normalizedLabel;
      },
      orElse: () => CapturedMediaItem(
        id: '',
        url: '',
        pageUrl: '',
        fileName: '',
        mimeType: '',
        headers: const <String, String>{},
        foundAt: DateTime.fromMillisecondsSinceEpoch(0),
        isDirectFile: false,
        isStream: false,
      ),
    );

    if (cachedDirect.url.isNotEmpty) {
      await _startDownload(
        cachedDirect.url,
        _contextualFileName(cachedDirect.url, qualityLabel: normalizedLabel),
        qualityLabel: normalizedLabel,
      );
      return;
    }

    if (_isDirectMediaFile(target)) {
      await _startDownload(target, _contextualFileName(target, qualityLabel: normalizedLabel), qualityLabel: normalizedLabel);
      return;
    }
    final targetUri = Uri.tryParse(target);
    final targetHost = (targetUri?.host ?? '').toLowerCase();
    if (_isvidfastSession &&
        (targetHost.contains('vidfast.pro') ||
            targetHost.contains('workers.dev') ||
            targetHost.contains('megafiles.store')) &&
        (targetLower.contains('/download') ||
            targetLower.contains('/stream') ||
            targetLower.contains('/file/'))) {
      await _startDownload(
        target,
        _contextualFileName(target, qualityLabel: normalizedLabel),
        qualityLabel: normalizedLabel,
      );
      return;
    }
    if (_looksLikeHlsManifestUrl(target)) {
      await _startHlsDownload(target, qualityLabel: normalizedLabel, pageUrl: pageUrl);
      return;
    }
    _showSnack('⚠️ هذا الرابط ليس ملف تحميل مباشرًا');
  }

  Future<void> _cancelDownload(DownloadItem item) async {
    await BackgroundDownloadBridge.cancel(item.id);
    item.cancelToken?.cancel('cancelled by user');
    if (!mounted) return;
    _downloadSelectionCommitted = false;
    setState(() { item.status = 'cancelled'; item.progress = 0; });
    _discoveredDownloadUrls.remove(item.url);
    _unregisterActiveDownloadControl(item);
    if (item.savedPath != null) {
      final file = File(item.savedPath!);
      if (await file.exists()) { try { await file.delete(); } catch (_) {} }
      await _DownloadLibraryIndexStore.remove(item.savedPath!);
    }
    _showSnack('⛔ تم إلغاء التحميل: ${item.fileName}');
  }

  Future<void> _playVideo(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final fileUrl = Uri.file(file.path).toString();
    final localSubtitleTracks = await _collectLocalSidecarSubtitleTracks(path);
    try {
      await _openNativePlayer(
        force: true,
        replace: true,
        forcedUrl: fileUrl,
        forcedPageUrl: fileUrl,
        forcedMimeType: _inferMimeType(fileUrl) ?? 'video/mp4',
        forcedSubtitleTracks: localSubtitleTracks,
      );
      if (!_nativePlayerActive && !_nativePlayerOpening) {
        _showSnack('⚠️ تعذّر فتح الملف داخل المشغل الداخلي');
      }
    } catch (_) {
      _showSnack('⚠️ تعذّر فتح الملف داخل المشغل الداخلي');
    }
  }

  Future<void> _confirmDelete(DownloadItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1318),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('حذف التحميل', style: TextStyle(color: Colors.white)),
        content: Text('هل تريد حذف "${item.fileName}" ؟', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final sidecarTargets = <String>{
        (item.finalPath ?? '').trim(),
        (item.savedPath ?? '').trim(),
        (item.tempPath ?? '').trim(),
      }..removeWhere((e) => e.isEmpty);
      for (final targetPath in sidecarTargets) {
        await _deleteLocalSidecarSubtitleFiles(targetPath);
      }
      if (item.savedPath != null) { try { await File(item.savedPath!).delete(); } catch (_) {} await _DownloadLibraryIndexStore.remove(item.savedPath!); }
      if (item.finalPath != null && item.finalPath != item.savedPath) { try { await File(item.finalPath!).delete(); } catch (_) {} await _DownloadLibraryIndexStore.remove(item.finalPath!); }
      if (item.thumbnailPath != null) { try { await File(item.thumbnailPath!).delete(); } catch (_) {} }
      _discoveredDownloadUrls.remove(item.url);
      if (_preparingDownloadPlaceholderId == item.id) {
        _preparingDownloadPlaceholderId = null;
      }
      setState(() { _downloads.remove(item); });
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF1A1318),
      behavior: SnackBarBehavior.floating,
    ));
  }


  void _registerActiveDownloadControl(DownloadItem item) {
    final control = _ActiveDownloadControl(
      pause: () => unawaited(_pauseDownload(item)),
      resume: () => _resumeDownload(item),
      isPaused: () => item.status == 'paused',
      isRunning: () => item.status == 'downloading' || item.status == 'preparing',
    );
    _ActiveDownloadRegistry.register(item.tempPath, control);
    _ActiveDownloadRegistry.register(item.finalPath, control);
  }

  void _unregisterActiveDownloadControl(DownloadItem item) {
    _ActiveDownloadRegistry.unregister(item.tempPath);
    _ActiveDownloadRegistry.unregister(item.finalPath);
    _ActiveDownloadRegistry.unregister(item.savedPath);
  }

  Future<void> _persistDownloadItemState(DownloadItem item, {String? statusOverride}) async {
    final tempPath = (item.tempPath ?? item.savedPath ?? '').trim();
    final finalPath = (item.finalPath ?? '').trim();
    if (tempPath.isEmpty || finalPath.isEmpty) return;
    await _persistActiveDownloadLibraryEntry(
      tempPath: tempPath,
      finalPath: finalPath,
      fileName: item.fileName,
      qualityLabel: item.qualityLabel,
      thumbnailPath: item.thumbnailPath,
      status: statusOverride ?? item.status,
      progress: item.progress,
      downloadId: item.id,
    );
  }

  
  static const String _backgroundDownloadSource = 'LightOn';

  void _ensureBackgroundDownloadPolling() {
    _backgroundDownloadSyncTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) unawaited(_syncBackgroundDownloads());
    });
    unawaited(_syncBackgroundDownloads());
  }

  Future<void> _syncBackgroundDownloads() async {
    final snapshots = await BackgroundDownloadBridge.list(source: _backgroundDownloadSource);
    if (!mounted) return;
    final existingById = <String, DownloadItem>{for (final item in _downloads) item.id: item};
    var changed = false;
    for (final snap in snapshots) {
      var item = existingById[snap.id];
      if (item == null) {
        item = DownloadItem(
          id: snap.id,
          url: snap.url,
          fileName: snap.fileName,
          progress: snap.progress,
          status: snap.status,
          savedPath: snap.status == 'done' ? snap.finalPath : snap.tempPath,
          tempPath: snap.tempPath,
          finalPath: snap.finalPath,
          errorMessage: snap.errorMessage,
        );
        _downloads.insert(0, item);
        existingById[snap.id] = item;
        changed = true;
        unawaited(_persistDownloadItemState(item, statusOverride: item.status));
      }
      final nextSavedPath = snap.status == 'done' ? snap.finalPath : snap.tempPath;
      var itemChanged = false;
      if (item.progress != snap.progress ||
          item.status != snap.status ||
          item.savedPath != nextSavedPath ||
          item.errorMessage != snap.errorMessage) {
        item.progress = snap.progress;
        item.status = snap.status;
        item.savedPath = nextSavedPath;
        item.tempPath = snap.tempPath;
        item.finalPath = snap.finalPath;
        item.errorMessage = snap.errorMessage;
        changed = true;
        itemChanged = true;
      }
      if (itemChanged) {
        unawaited(_persistDownloadItemState(item, statusOverride: item.status));
      }
    }
    if (changed && mounted) setState(() {});
  }

  Future<bool> _enqueueBackgroundDirectDownload(
    DownloadItem item, {
    Map<String, dynamic> headers = const <String, dynamic>{},
    String? pageUrl,
    String? qualityLabel,
  }) async {
    final normalizedHeaders = <String, String>{
      for (final entry in headers.entries)
        if (entry.key.toString().trim().isNotEmpty && entry.value.toString().trim().isNotEmpty)
          entry.key.toString(): entry.value.toString(),
    };
    try {
      await BackgroundDownloadBridge.enqueue(
        id: item.id,
        source: _backgroundDownloadSource,
        type: 'direct',
        url: item.url,
        fileName: item.fileName,
        tempPath: item.tempPath ?? item.savedPath ?? '',
        finalPath: item.finalPath ?? item.savedPath ?? '',
        headers: normalizedHeaders,
        pageUrl: pageUrl,
        qualityLabel: qualityLabel,
      );
      item.status = 'downloading';
      if (mounted) setState(() {});
      _ensureBackgroundDownloadPolling();
      _showSnack('⬇️ جاري تحميل: ${item.fileName}');
      return true;
    } catch (e) {
      item.status = 'error';
      item.errorMessage = e.toString();
      if (mounted) setState(() {});
      _showSnack('❌ تعذّر بدء تحميل الخلفية');
      return false;
    }
  }

  Future<bool> _enqueueBackgroundHlsDownload(
    DownloadItem item, {
    Map<String, dynamic> headers = const <String, dynamic>{},
    String? pageUrl,
    String? qualityLabel,
  }) async {
    final normalizedHeaders = <String, String>{
      for (final entry in headers.entries)
        if (entry.key.toString().trim().isNotEmpty && entry.value.toString().trim().isNotEmpty)
          entry.key.toString(): entry.value.toString(),
    };
    try {
      await BackgroundDownloadBridge.enqueue(
        id: item.id,
        source: _backgroundDownloadSource,
        type: 'hls',
        url: item.url,
        fileName: item.fileName,
        tempPath: item.tempPath ?? item.savedPath ?? '',
        finalPath: item.finalPath ?? item.savedPath ?? '',
        headers: normalizedHeaders,
        pageUrl: pageUrl,
        qualityLabel: qualityLabel,
      );
      item.status = 'downloading';
      if (mounted) setState(() {});
      _ensureBackgroundDownloadPolling();
      _showSnack('⬇️ جاري تحميل: ${item.fileName}');
      return true;
    } catch (e) {
      item.status = 'error';
      item.errorMessage = e.toString();
      if (mounted) setState(() {});
      _showSnack('❌ تعذّر بدء تحميل HLS بالخلفية');
      return false;
    }
  }

Future<void> _waitIfDownloadPaused(DownloadItem item) async {
    if (!item.pauseRequested) return;
    if (item.status != 'paused') {
      item.status = 'paused';
      if (mounted) setState(() {});
      await _persistDownloadItemState(item, statusOverride: 'paused');
    }
    item.resumeCompleter ??= Completer<void>();
    await item.resumeCompleter!.future;
    item.resumeCompleter = null;
    item.pauseRequested = false;
    item.status = 'downloading';
    if (mounted) setState(() {});
    await _persistDownloadItemState(item, statusOverride: 'downloading');
  }

  Future<void> _pauseDownload(DownloadItem item) async {
    if (item.status != 'downloading' && item.status != 'preparing') return;
    item.pauseRequested = true;
    await BackgroundDownloadBridge.pause(item.id);
    item.status = 'paused';
    if (mounted) setState(() {});
    await _persistDownloadItemState(item, statusOverride: 'paused');
    _showSnack('⏸️ تم إيقاف التحميل مؤقتًا: ${item.fileName}');
  }

  Future<void> _resumeDownload(DownloadItem item) async {
    if (item.status != 'paused') return;
    if (item.resumeCompleter != null && !item.resumeCompleter!.isCompleted) {
      item.resumeCompleter!.complete();
    }
    await BackgroundDownloadBridge.resume(item.id);
    item.pauseRequested = false;
    item.status = 'downloading';
    if (mounted) setState(() {});
    await _persistDownloadItemState(item, statusOverride: 'downloading');
    _showSnack('▶️ تم استئناف التحميل: ${item.fileName}');
  }

  void _openDownloadsPanel() {
    if (!mounted) return;
    if (widget.downloadOnlyMode) {
      setState(() {
        _revealHiddenLaunchUi = true;
      });
      return;
    }
    setState(() {
      _showDownloads = true;
    });
  }
  void _closeDownloadsPanel() {
    if (!mounted) return;
    setState(() { _showDownloads = false; });
  }

  Future<bool> _isPipSupported() async {
    if (!Platform.isAndroid) return true;
    try { return await _pip.invokeMethod<bool>('isPipSupported') ?? false; }
    on MissingPluginException { return false; }
    catch (_) { return false; }
  }

  bool get _allowNativeAutoOpen => widget.launchHidden && !widget.downloadOnlyMode && !widget.autoDownloadPrompt;

  bool _shouldHoldForPreferredQuality([String? currentQuality]) {
    return false;
  }

  void _ensurePreferredQualityBeforeAutoOpen([String? currentQuality]) {
    return;
  }

  void _tryAutoOpenBestQuickMedia() {
    if (!widget.launchHidden || widget.downloadOnlyMode) return;
    if (_preventAutoReopenAfterNativeClose) return;
    if (!_allowNativeAutoOpen || _nativePlayerActive || _nativePlayerOpening) return;
    final item = _bestQuickMedia;
    if (item == null) return;
    final activeQuality = item.qualityLabel ?? _currentPageQualityLabel;
    if (_shouldHoldForPreferredQuality(activeQuality)) {
      _ensurePreferredQualityBeforeAutoOpen(activeQuality);
      return;
    }
    Future.microtask(() => _openNativePlayer(
          force: true,
          replace: true,
          forcedUrl: item.url,
          forcedPageUrl: item.pageUrl,
          forcedMimeType: item.mimeType,
        ));
  }

  void _scheduleOriginalPlayerHardPause() {
    for (final ms in const [0, 120, 260, 520, 900, 1400, 2000]) {
      Future.delayed(Duration(milliseconds: ms), () async {
        await _pauseOriginalSitePlayer();
      });
    }
  }

  Future<void> _pauseOriginalSitePlayer() async {
    try {
      await _wc?.evaluateJavascript(source: r'''
        (function(){
          try {
            window.__asdNativePlayerActive = true;
            window.__asdPauseAllSitePlayers = window.__asdPauseAllSitePlayers || function(){
              try {
                document.querySelectorAll('video,audio').forEach(function(v){
                  try {
                    v.pause();
                    v.muted = true;
                    v.volume = 0;
                    v.autoplay = false;
                    v.removeAttribute('autoplay');
                  } catch(e) {}
                });
              } catch(e) {}
              try {
                if (window.jwplayer) {
                  var jw = window.jwplayer();
                  if (jw && jw.setMute) jw.setMute(true);
                  if (jw && jw.pause) jw.pause(true);
                  if (jw && jw.stop) jw.stop();
                }
              } catch(e) {}
              try {
                if (window.videojs && window.videojs.getPlayers) {
                  var players = window.videojs.getPlayers();
                  Object.keys(players || {}).forEach(function(key) {
                    try {
                      var p = players[key];
                      if (p && p.muted) p.muted(true);
                      if (p && p.pause) p.pause();
                      if (p && p.autoplay) p.autoplay(false);
                    } catch(e) {}
                  });
                }
              } catch(e) {}
            };
            if (!window.__asdOrigMediaPlay) {
              window.__asdOrigMediaPlay = HTMLMediaElement.prototype.play;
              HTMLMediaElement.prototype.play = function() {
                if (window.__asdNativePlayerActive) {
                  try {
                    this.pause();
                    this.muted = true;
                    this.volume = 0;
                  } catch(e) {}
                  return Promise.resolve();
                }
                return window.__asdOrigMediaPlay.apply(this, arguments);
              };
            }
            window.__asdPauseAllSitePlayers();
            try { clearInterval(window.__asdNativePauseLoop); } catch(e) {}
            window.__asdNativePauseLoop = setInterval(function(){
              if (!window.__asdNativePlayerActive) return;
              try { window.__asdPauseAllSitePlayers(); } catch(e) {}
            }, 220);
          } catch(e) {}
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _releaseOriginalSitePlayerBlock() async {
    try {
      await _wc?.evaluateJavascript(source: r'''
        (function(){
          try {
            window.__asdNativePlayerActive = false;
            try { clearInterval(window.__asdNativePauseLoop); } catch(e) {}
            window.__asdNativePauseLoop = null;
            document.querySelectorAll('video,audio').forEach(function(v){
              try {
                v.pause();
                v.muted = false;
                v.volume = 1;
              } catch(e) {}
            });
            if (window.jwplayer) {
              try {
                var jw = window.jwplayer();
                if (jw && jw.setMute) jw.setMute(false);
                if (jw && jw.pause) jw.pause(true);
              } catch(e) {}
            }
            if (window.videojs && window.videojs.getPlayers) {
              try {
                var players = window.videojs.getPlayers();
                Object.keys(players || {}).forEach(function(key) {
                  try {
                    var p = players[key];
                    if (p && p.muted) p.muted(false);
                    if (p && p.pause) p.pause();
                  } catch(e) {}
                });
              } catch(e) {}
            }
          } catch(e) {}
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _suspendCaptureEngine() async {
    _captureEngineSuspended = true;
    _pendingNativeOpenOnPlayableCapture = false;
    _pendingPlayableCaptureToken++;
    _hiddenQualityHarvesting = false;
    _qualitySwitchPending = false;
    _manualPlayAfterQualitySwitchPending = false;
    _serverSwitchPending = false;
    _qualityDownloadSwitchPending = false;
    try {
      await _pauseOriginalSitePlayer();
      await _wc?.evaluateJavascript(source: r'''(function(){
        try {
          if (window.stop) window.stop();
          document.querySelectorAll('video,audio').forEach(function(v){
            try {
              v.pause();
              v.muted = true;
              v.volume = 0;
            } catch(e) {}
          });
        } catch(e) {}
      })();''');
    } catch (_) {}
  }

  void _resumeCaptureEngine() {
    _captureEngineSuspended = false;
    _pendingNativeOpenOnPlayableCapture = false;
  }

  Future<void> _closeNativePlayer() async {
    _preventAutoReopenAfterNativeClose = true;
    _exitHiddenRouteAfterNativeClose = widget.launchHidden && !widget.downloadOnlyMode && !widget.autoDownloadPrompt;
    _pendingNativeOpenOnPlayableCapture = false;
    _pendingPlayableCaptureToken++;
    _suppressAutoOpenUntil = DateTime.now().millisecondsSinceEpoch + 1200;
    _nativePlayerShellOnly = false;
    _nativePlayerShellRequested = false;
    _pendingShellMediaUrl = null;
    _pendingShellPageUrl = null;
    _pendingShellMimeType = null;
    _resumeCaptureEngine();
    try {
      await _pip.invokeMethod<bool>('closeNativePlayer');
    } catch (_) {}
    await _releaseOriginalSitePlayerBlock();
  }

  Future<void> _openNativePlayerShell() async {
    if (!Platform.isAndroid) return;
    if (widget.downloadOnlyMode) return;
    if (_nativePlayerActive || _nativePlayerOpening || _nativePlayerShellRequested) return;
    _nativePlayerShellRequested = true;
    _nativePlayerOpening = true;

    _nativePlayerShellOnly = true;

    final shellTicket = ++_nativeOpenTicket;
    try {
      final aspectRatio = _safePipAspectRatio();
      await _primeSubtitleTracksForNativePlayback();
      final nativeSubtitleTracks = await _resolveNativeSubtitleTracksForCurrentSource(const <String, String>{});
      final ok = await _pip.invokeMethod<bool>('openNativePlayerShell', {
        ..._nativeIdentityArgs(),
        'aspectRatioNumerator': aspectRatio['w'],
        'aspectRatioDenominator': aspectRatio['h'],
        'subtitleTracks': nativeSubtitleTracks,
        'qualityOptions': _pageQualityOptions.map((e) => e.toMap()).toList(),
        'currentQualityLabel': _currentPageQualityLabel,
        'serverOptions': _pageServerOptions.map((e) => e.toMap()).toList(),
        'currentServerLabel': _currentServerLabel,
      });
      if (ok == true && mounted) {
        setState(() {
          _nativePlayerActive = true;
          _nativePlayerShellOnly = true;
        });
        Future.delayed(const Duration(milliseconds: 80), () {
          if (!mounted) return;
          if (shellTicket != _nativeOpenTicket) return;
          if (!_nativePlayerShellRequested || !_nativePlayerShellOnly) return;
          final pendingUrl = (_pendingShellMediaUrl ?? '').trim();
          if (pendingUrl.isEmpty) return;
          final pendingPageUrl = _pendingShellPageUrl;
          final pendingMimeType = _pendingShellMimeType;
          _pendingShellMediaUrl = null;
          _pendingShellPageUrl = null;
          _pendingShellMimeType = null;
          _nativePlayerShellRequested = false;
          _nativePlayerOpening = false;
          _nativePlayerShellOnly = false;
          Future.microtask(() => _attachSourceToNativePlayer(
                mediaUrl: pendingUrl,
                pageUrl: pendingPageUrl ??
                    _capturedVideoPageUrl ??
                    _currentPageUrl ??
                    _lastTrusted,
                mimeType: pendingMimeType,
                startTimeOverride: _pendingNativeStartTime,
              ));
        });
      } else {
        _nativePlayerShellOnly = false;
        _nativePlayerShellRequested = false;
        _nativePlayerOpening = false;
      }
    } on MissingPluginException {
      _nativePlayerShellOnly = false;
      _nativePlayerShellRequested = false;
      _nativePlayerOpening = false;
    } catch (_) {
      _nativePlayerShellOnly = false;
      _nativePlayerShellRequested = false;
      _nativePlayerOpening = false;
    }
  }

  Future<void> _attachSourceToNativePlayer({required String mediaUrl, String? pageUrl, String? mimeType, double? startTimeOverride}) async {
    final cleanUrl = mediaUrl.trim();
    if (cleanUrl.isEmpty || cleanUrl.startsWith('blob:')) {
      debugPrint('[Player] _attachSourceToNativePlayer: رابط غير صالح $cleanUrl');
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastAttachRequestUrl == cleanUrl && (nowMs - _lastAttachRequestAt) < 1200) {
      return;
    }
    _lastAttachRequestUrl = cleanUrl;
    _lastAttachRequestAt = nowMs;

    final headers = await _buildPipHeaders(cleanUrl, pageUrl: pageUrl);
    await _primeSubtitleTracksForNativePlayback();

    final bestMediaUrl = await _resolvePreferredNativeMediaUrl(cleanUrl, headers);
    if ((_lastNativePlayerUrl ?? '').trim().toLowerCase() != bestMediaUrl.toLowerCase()) {
      _nativeDecoderFallbackTriedUrls
        ..clear()
        ..add(bestMediaUrl.toLowerCase());
    } else {
      _nativeDecoderFallbackTriedUrls.add(bestMediaUrl.toLowerCase());
    }
    _prepareQualityOptionsInBackground(cleanUrl, headers);

    final nativeSubtitleTracks = await _resolveNativeSubtitleTracksForCurrentSource(headers);
    final aspectRatio = _safePipAspectRatio();
    final nativeHasExplicitQuality = _pageQualityOptions.isNotEmpty || (_currentPageQualityLabel ?? '').trim().isNotEmpty;
    final nativeQualityOptions = nativeHasExplicitQuality
        ? _pageQualityOptions.map((e) => e.toMap()).toList()
        : const <Map<String, dynamic>>[];

    try {
      final ok = await _pip.invokeMethod<bool>('updateNativePlayerSource', {
        ..._nativeIdentityArgs(),
        'url': bestMediaUrl,
        'currentTime': startTimeOverride ?? _capturedVideoTime,
        'pageUrl': pageUrl,
        'mimeType': mimeType ?? _capturedVideoMimeType ?? _inferMimeType(bestMediaUrl),
        'headers': headers,
        'aspectRatioNumerator': aspectRatio['w'],
        'aspectRatioDenominator': aspectRatio['h'],
        'subtitleTracks': nativeSubtitleTracks,
        'qualityOptions': nativeQualityOptions,
        'currentQualityLabel': nativeHasExplicitQuality ? _currentPageQualityLabel : null,
        'serverOptions': _pageServerOptions.map((e) => e.toMap()).toList(),
        'currentServerLabel': _currentServerLabel,
      });

      if (ok == true) {
        _nativePlayerShellOnly = false;
        _nativePlayerShellRequested = false;
        _lastNativePlayerUrl = bestMediaUrl;
        if (mounted) {
          setState(() => _nativePlayerActive = true);
        }
        await _suspendCaptureEngine();
        unawaited(_updateNativePlayerOptions());
        debugPrint('[Player] _attachSourceToNativePlayer: نجح ربط المصدر $bestMediaUrl');
      } else {
        debugPrint('[Player] _attachSourceToNativePlayer: فشل الربط - ok=$ok');
      }
    } on MissingPluginException {
      debugPrint('[Player] _attachSourceToNativePlayer: MissingPluginException');
    } catch (e) {
      debugPrint('[Player] _attachSourceToNativePlayer: خطأ $e');
    }
  }

  Future<void> _openNativePlayer({bool force = false, bool enterPipAfter = false, bool replace = false, double? startTimeOverride, String? forcedUrl, String? forcedPageUrl, String? forcedMimeType, List<Map<String, String>>? forcedSubtitleTracks}) async {
    if (widget.downloadOnlyMode) return;

    final hasImmediatePlayableForcedUrl =
        _looksLikePlayableMediaUrl(forcedUrl) &&
        !_isYouTubeUrl(forcedUrl) &&
        !(forcedUrl?.startsWith('blob:') ?? false);

    final shouldRefreshVideasyBeforeOpen =
        !hasImmediatePlayableForcedUrl &&
        (_isVideasyPlayerUrl(widget.initialUrl) ||
        _isVideasyPlayerUrl(_currentPageUrl) ||
        _isVideasyPlayerUrl(forcedPageUrl) ||
        _isEphemeralVideasyMediaUrl(forcedUrl) ||
        _isEphemeralVideasyMediaUrl(_capturedVideoUrl));

    if (shouldRefreshVideasyBeforeOpen) {
      final preferredLabel = _normalizeQualityLabel(_currentPageQualityLabel ?? '');
      await _maybeFetchLatestSourceBundle(force: true);
      final fresh = await _collectFreshVideasyPlaybackCandidate(
        preferredQualityLabel: preferredLabel.isEmpty ? null : preferredLabel,
      );
      final freshUrl = (fresh?['url'] ?? '').toString().trim();
      if (freshUrl.isNotEmpty) {
        forcedUrl = freshUrl;
        forcedPageUrl = (fresh?['pageUrl'] ?? forcedPageUrl ?? _currentPageUrl ?? widget.initialUrl).toString().trim();
        final freshMimeCandidate = (fresh?['mimeType'] ?? forcedMimeType ?? _inferMimeType(freshUrl))?.toString().trim();
        forcedMimeType = (freshMimeCandidate == null || freshMimeCandidate.isEmpty || freshMimeCandidate == 'null')
            ? null
            : freshMimeCandidate;
        final freshQuality = _normalizeQualityLabel((fresh?['qualityLabel'] ?? '').toString());
        if (freshQuality.isNotEmpty) {
          _currentPageQualityLabel = freshQuality;
        }
        _capturedVideoUrl = freshUrl;
        if ((forcedPageUrl ?? '').isNotEmpty) {
          _capturedVideoPageUrl = forcedPageUrl;
        }
        if ((forcedMimeType ?? '').isNotEmpty) {
          _capturedVideoMimeType = forcedMimeType;
        }
      }
    }

    if (_nativePlayerShellOnly) {
      final pendingUrl = (forcedUrl ?? _capturedVideoUrl)?.trim();
      if (pendingUrl != null && pendingUrl.isNotEmpty && !pendingUrl.startsWith('blob:')) {
        await _attachSourceToNativePlayer(
          mediaUrl: pendingUrl,
          pageUrl: forcedPageUrl ?? _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted,
          mimeType: forcedMimeType,
          startTimeOverride: startTimeOverride,
        );
      } else if (force) {
        _showSnack('⚠️ لم ألتقط رابط الفيديو الحقيقي بعد');
      }
      return;
    }

    if (replace && _nativePlayerOpening) return;
    if (!replace && (_nativePlayerActive || _nativePlayerOpening)) return;

    if ((forcedUrl ?? _capturedVideoUrl) == null || (forcedUrl ?? _capturedVideoUrl)!.startsWith('blob:')) {
      try {
        await _wc?.evaluateJavascript(source: 'window.__asdCollectMediaNow && window.__asdCollectMediaNow();');
        await Future.delayed(const Duration(milliseconds: 60));
      } catch (_) {}
    }

    final mediaUrl = (forcedUrl ?? _capturedVideoUrl)?.trim();
    if (mediaUrl == null || mediaUrl.isEmpty || mediaUrl.startsWith('blob:')) {
      if (force) {
        _showSnack('⚠️ لم ألتقط رابط الفيديو الحقيقي بعد');
      }
      return;
    }
    if (_isYouTubeUrl(mediaUrl)) {
      if (force) _showSnack('⚠️ روابط يوتيوب لا تُشغَّل داخل المشغل الأصلي');
      return;
    }

    if (!force && !_videoPlaying) return;

    _preventAutoReopenAfterNativeClose = false;
    _exitHiddenRouteAfterNativeClose = false;
    _nativePlayerOpening = true;
    final ticket = ++_nativeOpenTicket;

    try {
      await _pauseOriginalSitePlayer();
      final currentPage = (await _wc?.getUrl())?.toString();
      final pageUrl = forcedPageUrl ?? _capturedVideoPageUrl ?? currentPage ?? _lastTrusted;
      _rememberStableWatchUrl(pageUrl);
      _rememberStableWatchUrl(currentPage);
      _rememberStableWatchUrl(_capturedVideoPageUrl);
      final headers = await _buildPipHeaders(mediaUrl, pageUrl: pageUrl);

      await _primeSubtitleTracksForNativePlayback();

      final bestMediaUrl = await _resolvePreferredNativeMediaUrl(mediaUrl, headers);
      if (!replace || (_lastNativePlayerUrl ?? '').trim().toLowerCase() != bestMediaUrl.toLowerCase()) {
        _nativeDecoderFallbackTriedUrls
          ..clear()
          ..add(bestMediaUrl.toLowerCase());
      } else {
        _nativeDecoderFallbackTriedUrls.add(bestMediaUrl.toLowerCase());
      }
      final nativeSubtitleTracks = forcedSubtitleTracks ?? await _resolveNativeSubtitleTracksForCurrentSource(headers);
      final aspectRatio = _safePipAspectRatio();
      final nativeHasExplicitQuality = (_currentPageQualityLabel ?? '').trim().isNotEmpty;
      final nativeQualityOptions = nativeHasExplicitQuality
          ? _pageQualityOptions.map((e) => e.toMap()).toList()
          : const <Map<String, dynamic>>[];

      if (!Platform.isAndroid) {
        if (ticket != _nativeOpenTicket) return;
        _nativePlayerShellOnly = false;
        _nativePlayerShellRequested = false;
        await _suspendCaptureEngine();
        if (mounted) {
          setState(() {
            _nativePlayerActive = true;
            _lastNativePlayerUrl = bestMediaUrl;
          });
        }
        await openUniversalMediaPlayer(
          context,
          url: bestMediaUrl,
          title: widget.headerTitle ?? _currentMediaTitle ?? _currentPageTitle ?? 'Light On',
          pageUrl: pageUrl,
          mimeType: forcedMimeType ?? _capturedVideoMimeType ?? _inferMimeType(bestMediaUrl),
          headers: headers,
          currentTime: startTimeOverride ?? _capturedVideoTime,
          qualityOptions: nativeQualityOptions.map((e) => Map<String, dynamic>.from(e)).toList(growable: false),
          currentQualityLabel: nativeHasExplicitQuality ? _currentPageQualityLabel : null,
          serverOptions: _pageServerOptions.map((e) => Map<String, dynamic>.from(e.toMap())).toList(growable: false),
          currentServerLabel: _currentServerLabel,
          subtitleTracks: nativeSubtitleTracks.map((e) => Map<String, dynamic>.from(e)).toList(growable: false),
        );
        if (ticket != _nativeOpenTicket) return;
        if (mounted) {
          setState(() {
            _nativePlayerActive = false;
            _lastNativePlayerUrl = null;
          });
        } else {
          _nativePlayerActive = false;
          _lastNativePlayerUrl = null;
        }
        await _releaseOriginalSitePlayerBlock();
        await _restoreUI();
        _resumeCaptureEngine();
        await _returnToWatchPage();
        return;
      }

      final ok = await _pip.invokeMethod<bool>('openNativePlayer', {
          ..._nativeIdentityArgs(),
        'url': bestMediaUrl,
        'currentTime': startTimeOverride ?? _capturedVideoTime,
        'pageUrl': pageUrl,
        'mimeType': forcedMimeType ?? _capturedVideoMimeType ?? _inferMimeType(bestMediaUrl),
        'headers': headers,
        'aspectRatioNumerator': aspectRatio['w'],
        'aspectRatioDenominator': aspectRatio['h'],
        'subtitleTracks': nativeSubtitleTracks,
        'qualityOptions': nativeQualityOptions,
        'currentQualityLabel': nativeHasExplicitQuality ? _currentPageQualityLabel : null,
        'serverOptions': _pageServerOptions.map((e) => e.toMap()).toList(),
        'currentServerLabel': _currentServerLabel,
        'resizeMode': 'fill',
        'preferFill': true,
        'autoSelectSubtitle': true,
      });

      if (ticket != _nativeOpenTicket) return;
      if (ok == true && mounted) {
        _nativePlayerShellOnly = false;
        _nativePlayerShellRequested = false;
        await _suspendCaptureEngine();
        setState(() {
          _nativePlayerActive = true;
          _lastNativePlayerUrl = bestMediaUrl;
        });
        unawaited(_updateNativePlayerOptions());
        if (enterPipAfter) {
          await Future.delayed(const Duration(milliseconds: 140));
          await _enterPip();
        }
      } else if (force) {
        _showSnack('⚠️ تعذّر فتح مشغلك الأصلي');
      }
    } on MissingPluginException {
      _nativePlayerShellRequested = false;
      if (force) _showSnack('⚠️ المشغل الأصلي غير مفعّل Native داخل Android للمشروع');
    } catch (_) {
      _nativePlayerShellRequested = false;
      if (force) _showSnack('⚠️ تعذّر فتح المشغل الأصلي');
    } finally {
      if (ticket == _nativeOpenTicket) {
        _nativePlayerOpening = false;
      }
    }
  }

  Future<void> _enterPip() async {
    if (_inPip) return;
    final supported = await _isPipSupported();
    if (!supported) {
      _showSnack('⚠️ PiP غير مفعّل Native داخل Android للمشروع');
      return;
    }

    if (!_nativePlayerActive) {
      await _openNativePlayer(force: true, enterPipAfter: true);
      return;
    }

    try {
      final ok = await _pip.invokeMethod<bool>('enterPip') ?? false;
      if (ok == true && mounted) {
        setState(() => _inPip = true);
      } else {
        _showSnack('⚠️ تعذّر إدخال المشغل إلى PiP');
      }
    } on MissingPluginException {
      _showSnack('⚠️ PiP غير مفعّل Native داخل Android للمشروع');
    } catch (_) {
      _showSnack('⚠️ تعذّر تفعيل PiP');
    }
  }

  Future<void> _applyPageFullscreenForce() async {
    try { await _wc?.evaluateJavascript(source: 'window.__asdForceFullscreenNow && window.__asdForceFullscreenNow();'); } catch (_) {}
  }

  Future<void> _removePageFullscreenForce() async {
    try { await _wc?.evaluateJavascript(source: 'window.__asdExitForcedFullscreen && window.__asdExitForcedFullscreen();'); } catch (_) {}
  }

  Future<void> _enterFullscreen() async {
    if (!mounted || _fullscreen || _fullscreenBusy) return;
    _fullscreenBusy = true;
    try {
      setState(() => _fullscreen = true);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await Future.delayed(const Duration(milliseconds: 80));
      await _applyPageFullscreenForce();
    } finally {
      await Future.delayed(const Duration(milliseconds: 250));
      _fullscreenBusy = false;
    }
  }

  Future<void> _exitFullscreen() async {
    if (!mounted || !_fullscreen || _fullscreenBusy) return;
    _fullscreenBusy = true;
    try {
      setState(() => _fullscreen = false);
      await _removePageFullscreenForce();
      await _restoreUI();
    } finally {
      await Future.delayed(const Duration(milliseconds: 250));
      _fullscreenBusy = false;
    }
  }

  Future<void> _restoreUI() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp, DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<bool> _safeEvalJs(String source) async {
    final controller = _wc;
    if (controller == null || !mounted) return false;
    try {
      await controller.evaluateJavascript(source: source);
      return true;
    } on MissingPluginException {
      _wc = null;
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _reinjectScripts() async {
    if (!mounted || _wc == null) return;
    if (!await _safeEvalJs(_stealthAdBlock)) return;
    if (!await _safeEvalJs(_ads)) return;
    await _safeEvalJs(_desktopViewport);
    await _safeEvalJs(_css);
    await _safeEvalJs(_hideServers);
    await _safeEvalJs(_dlCapture);
    await _safeEvalJs(_captureOptions);
    await _safeEvalJs(_interceptSourceApi);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ✅ FIX 1: _isAllowedNavigation — closed the canRedir loophole
  //    Old bug: if _lastTrusted was doodstream/arabseed (in _redirectOk),
  //    ANY URL was allowed through — including ad redirects triggered by clicking.
  //    New: canRedir path ALSO requires destination to be in _white.
  //    CDN/cloud URLs still pass because they ARE in _white (cloudfront, akamaized, etc.)
  // ─────────────────────────────────────────────────────────────────────────
  bool _isAllowedNavigation(String url, bool isMainFrame) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) return false;

    // ✅ FIX 1a: Always block known ad/tracking domains first, before any whitelist logic
    if (_isB(url) || _isAdResourceUrl(url)) return false;

    final decodedTarget = _decodeArabseedRedirect(url);
    if (decodedTarget != null) {
      if (_isB(decodedTarget) || _isAdResourceUrl(decodedTarget)) return false;
      _rememberAllowedHost(decodedTarget);
      _lastTrusted = url;
      _currentHost = Uri.tryParse(decodedTarget)?.host;
      return true;
    }

    if (!isMainFrame) return true;

    if (_isRuntimeAllowed(url)) {
      _lastTrusted = url;
      _currentHost = Uri.tryParse(url)?.host;
      return true;
    }

    // Direct asd.pics / arabseed — always allowed
    if (url.contains('asd.pics') || url.contains('arabseed.show')) {
      _lastTrusted = url;
      _currentHost = Uri.tryParse(url)?.host;
      return true;
    }

    // Known whitelisted domain — allowed
    if (_isW(url)) {
      _lastTrusted = url;
      _currentHost = Uri.tryParse(url)?.host;
      return true;
    }

    // Download landing pages opened from ArabSeed should be allowed when they are not ads.
    if (_isLikelyDownloadLandingUrl(url)) {
      _rememberAllowedHost(url);
      _lastTrusted = url;
      _currentHost = Uri.tryParse(url)?.host;
      return true;
    }

    // ✅ FIX 1b: canRedir path — destination MUST also be whitelisted or runtime-approved
    if (_lastTrusted != null && _canRedir(_lastTrusted!) && (_isW(url) || _isRuntimeAllowed(url))) {
      _lastTrusted = url;
      _currentHost = Uri.tryParse(url)?.host;
      return true;
    }

    if (_currentHost != null && _canRedir(_currentHost!) && (_isW(url) || _isRuntimeAllowed(url))) {
      _currentHost = Uri.tryParse(url)?.host;
      return true;
    }

    return false;
  }


  DownloadItem? get _primaryInlineDownloadItem {
    if (_downloads.isEmpty) return null;
    for (final item in _downloads) {
      if (item.status == 'preparing' || item.status == 'downloading') return item;
    }
    for (final item in _downloads) {
      if (item.status == 'done') return item;
    }
    return _downloads.first;
  }

  Widget _buildInlineDownloadStrip() {
    return const SizedBox.shrink();
  }

  Widget _buildDownloadsPanel() {
    if (widget.downloadOnlyMode) {
      return const SizedBox.shrink();
    }
    const fullscreenDownloadMode = false;

    Widget panelBody() {
      return SafeArea(
        bottom: false,
        child: Container(
          height: fullscreenDownloadMode ? null : 420,
          margin: fullscreenDownloadMode
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF181216),
            borderRadius: BorderRadius.circular(fullscreenDownloadMode ? 0 : 24),
            border: Border.all(
              color: fullscreenDownloadMode ? Colors.transparent : Colors.white10,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFB3202A).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.download_rounded, color: Color(0xFFB3202A)),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'التحميلات',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'يفتح الفيديو بعد التحميل بالمشغل الذي أضفته',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: widget.downloadOnlyMode
                          ? () {
                              if (!mounted) return;
                              final nav = Navigator.of(context, rootNavigator: true);
                              if (nav.canPop()) {
                                nav.pop();
                              }
                            }
                          : _closeDownloadsPanel,
                      icon: Icon(
                        widget.downloadOnlyMode
                            ? Icons.close_rounded
                            : Icons.keyboard_arrow_up,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(
                child: _downloads.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            widget.downloadOnlyMode
                                ? 'اختر الجودة من النافذة السفلية وسيظهر التحميل هنا مباشرة'
                                : 'لا توجد تحميلات',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: _downloads.length,
                        itemBuilder: (context, i) => _buildDownloadCard(_downloads[i]),
                      ),
              ),
            ],
          ),
        ),
      );
    }

    return Positioned(
      top: _showDownloads ? 0 : -430,
      left: 0,
      right: 0,
      child: panelBody(),
    );
  }

  Widget _buildDownloadCard(DownloadItem d) {
    final isDone = d.status == 'done';
    final isErr = d.status == 'error';
    final isCancelled = d.status == 'cancelled';
    final isPreparing = d.status == 'preparing';
    final isDownloading = d.status == 'downloading';
    final isPaused = d.status == 'paused';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 108, height: 72, color: Colors.black26,
              child: d.thumbnailPath != null && File(d.thumbnailPath!).existsSync()
                  ? pwaImageFile(d.thumbnailPath!, fit: BoxFit.cover)
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF252526), Color(0xFF2D2D30)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                      ),
                      child: isPreparing
                          ? const Center(child: _WaveDropletLoader(size: 34))
                          : Icon(
                              isDone ? Icons.movie_creation_outlined
                                : isErr ? Icons.error_outline
                                : isCancelled ? Icons.remove_circle_outline
                                : Icons.downloading_rounded,
                              color: Colors.white70, size: 30,
                            ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.fileName, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCancelled ? Colors.white38 : Colors.white,
                      fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.2,
                    ),
                  ),
                  const Spacer(),
                  if (isPreparing) const Text(
                    'جاري تجهيز رابط الجودة المختارة...',
                    style: TextStyle(color: Colors.white70, fontSize: 11.5),
                  )
                  else if (isDownloading) Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.all(Radius.circular(99)),
                        child: LinearProgressIndicator(
                          value: d.progress <= 0 ? null : d.progress,
                          minHeight: 6,
                          backgroundColor: _kDownloadAccentSoft,
                          valueColor: const AlwaysStoppedAnimation<Color>(_kDownloadProgressBarColor),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        d.progress > 0 ? 'جاري التحميل... ${(d.progress * 100).toStringAsFixed(0)}%' : 'جاري التحميل...',
                        style: const TextStyle(color: Colors.white, fontSize: 11.5),
                      ),
                    ],
                  )
                  else if (isPaused) Text(
                    'تم إيقاف التحميل مؤقتًا ${(d.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white, fontSize: 11.5),
                  )
                  else if (isDone) Text(
                    d.savedPath != null ? 'اكتمل التحميل - اضغط تشغيل' : 'اكتمل التحميل',
                    style: const TextStyle(color: Colors.green, fontSize: 11.5),
                  )
                  else if (isErr) const Text('فشل التحميل', style: TextStyle(color: Colors.redAccent, fontSize: 11.5))
                  else if (isCancelled) const Text('تم إلغاء التحميل', style: TextStyle(color: Colors.white38, fontSize: 11.5)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isPreparing || isDownloading) _actionBtn(icon: Icons.pause_circle_outline_rounded, color: Colors.white, onTap: () => _pauseDownload(d)),
              if (isPaused) _actionBtn(icon: Icons.play_circle_outline_rounded, color: Colors.white, onTap: () => _resumeDownload(d)),
              if (isDone && d.savedPath != null) _actionBtn(icon: Icons.play_circle_fill_rounded, color: Colors.green, onTap: () => _playVideo(d.savedPath!)),
              if (isDone && d.savedPath != null) _actionBtn(icon: Icons.refresh_rounded, color: Colors.white70, onTap: () async {
                _showSnack('🔄 جاري تحديث الترجمة...');
                await _refreshMatchingSubtitleSidecar(d.savedPath!);
                _showSnack('✅ تم تحديث الترجمة إذا كانت متاحة');
              }),
              if (!isPreparing && !isDownloading && !isPaused)
                _actionBtn(icon: Icons.delete_outline, color: Colors.white70, onTap: () async {
                  await _confirmDelete(d);
                }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({required IconData icon, required Color color, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }


  bool _looksLikeWatchPage([String? rawUrl]) {
    final url = (rawUrl ?? _currentPageUrl ?? _capturedVideoPageUrl ?? _lastTrusted ?? '').toLowerCase();
    if (url.isEmpty) return false;
    return url.contains('play=true') ||
        url.contains('/watch/') ||
        url.contains('%d9%85%d8%b4%d8%a7%d9%87') ||
        url.contains('/episode/') ||
        url.contains('/movie/') ||
        url.contains('hockey.10017.workers.dev/') ||
        url.contains('10017.workers.dev/') ||
        url.contains('vidfast.pro/movie/') ||
        url.contains('vidfast.pro/tv/');
  }

  CapturedMediaItem? get _bestQuickMedia {
    final activeQuality = _normalizeQualityLabel(_currentPageQualityLabel ?? '');
    if (activeQuality.isNotEmpty) {
      final byCurrentQuality = _bestQuickMediaForQuality(activeQuality);
      if (byCurrentQuality != null) return byCurrentQuality;
    }
    final bestCaptured = _bestQuickMediaForQuality();
    if (bestCaptured != null) return bestCaptured;
    final url = _capturedVideoUrl;
    if (url == null || url.isEmpty) return null;
    return CapturedMediaItem(
      id: 'fallback',
      url: url,
      pageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted ?? 'https://asd.pics/',
      fileName: _contextualFileName(url, qualityLabel: _currentPageQualityLabel),
      foundAt: DateTime.now(),
      isDirectFile: _isDirectMediaFile(url),
      isStream: _isStreamUrl(url),
      mimeType: _capturedVideoMimeType ?? _inferMimeType(url),
      qualityLabel: _normalizeQualityLabel(_currentPageQualityLabel ?? '').isEmpty ? null : _normalizeQualityLabel(_currentPageQualityLabel ?? ''),
      headers: {
        'User-Agent': _ua,
        'Referer': _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted ?? 'https://asd.pics/',
      },
    );
  }

  bool get _showQuickMediaButtons =>
      !widget.downloadOnlyMode &&
      _looksLikeWatchPage() &&
      (_bestQuickMedia != null ||
          _pageQualityOptions.isNotEmpty ||
          _pageServerOptions.isNotEmpty) &&
      !_fullscreen &&
      !_nativePlayerActive &&
      !_showDownloads;

  bool get _hideSiteDuringDirectLaunch =>
      widget.launchHidden &&
      !widget.downloadOnlyMode &&
      _looksLikeWatchPage(widget.initialUrl) &&
      !_revealHiddenLaunchUi &&
      !_nativePlayerActive;

  bool _showQualityResolveLoader = false;

  List<PageQualityOption> get _initialDownloadChoiceOptions => const <PageQualityOption>[
        PageQualityOption(label: '1080p', key: 'preset_1080p', selected: true),
        PageQualityOption(label: '720p', key: 'preset_720p'),
        PageQualityOption(label: '480p', key: 'preset_480p'),
      ];

  String _downloadPlaceholderFileName(String qualityLabel) {
    final label = _normalizeQualityLabel(qualityLabel).ifEmpty(qualityLabel);
    return _buildManagedDownloadFileName(
      extension: '.mp4',
      qualityLabel: label,
    );
  }

  void _showPreparingDownloadPlaceholder(String qualityLabel) {
    final label = _normalizeQualityLabel(qualityLabel).ifEmpty(qualityLabel);
    final existingIndex = _preparingDownloadPlaceholderId == null
        ? -1
        : _downloads.indexWhere((d) => d.id == _preparingDownloadPlaceholderId);
    if (existingIndex >= 0) {
      final existing = _downloads[existingIndex];
      existing.fileName = _downloadPlaceholderFileName(label);
      existing.status = 'preparing';
      existing.progress = 0;
      existing.errorMessage = null;
    } else {
      final item = DownloadItem(
        id: 'prepare_${DateTime.now().millisecondsSinceEpoch}',
        url: 'prepare:$label',
        fileName: _downloadPlaceholderFileName(label),
        status: 'preparing',
      );
      _downloads.insert(0, item);
      _preparingDownloadPlaceholderId = item.id;
    }
    if (mounted) setState(() {});
  }

  void _clearPreparingDownloadPlaceholder() {
    if (_preparingDownloadPlaceholderId == null) return;
    _downloads.removeWhere((d) => d.id == _preparingDownloadPlaceholderId);
    _preparingDownloadPlaceholderId = null;
    if (mounted) setState(() {});
  }

  DownloadItem? _preparingDownloadPlaceholderItem() {
    final id = _preparingDownloadPlaceholderId;
    if (id == null) return null;
    for (final item in _downloads) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _markPreparingDownloadPlaceholderError([String? message]) {
    final item = _preparingDownloadPlaceholderItem();
    if (item == null) return;
    item.status = 'error';
    item.progress = 0;
    item.errorMessage = message;
    _resetDownloadPromptFlow();
    _downloadSelectionCommitted = false;
    _downloadCaptureStarted = false;
    _qualityDownloadSwitchPending = false;
    _downloadQualitySheetShown = false;
    _downloadChoiceLocked = false;
    _notifyDownloadStatus('error');
    _finishHiddenDownloadRoute('error');
    if (mounted) setState(() {});
  }

  void _resetDownloadPromptFlow() {
    _downloadPromptPending = false;
    _downloadPromptConsumed = false;
    _downloadPromptFlowLocked = false;
  }

  Future<bool> _waitForInitialDownloadChoices({int timeoutMs = 3200}) async {
    final deadline = DateTime.now().millisecondsSinceEpoch + timeoutMs;
    while (mounted) {
      if (_downloadChoiceLocked ||
          _downloadSelectionCommitted ||
          _downloadQualitySheetShown ||
          _hasActiveDownloadTask ||
          _downloadPromptConsumed) {
        return false;
      }
      await _ensureDownloadQualityChoicesReady();
      await _prepareDownloadChoicesFromWatchLogic();
      if (_topThreeDownloadQualityOptions().isNotEmpty) {
        return true;
      }
      if ((_bestDownloadCandidateFromWatchLogic()?.url ?? '').trim().isNotEmpty &&
          _pageQualityOptions.isNotEmpty) {
        return true;
      }
      if (DateTime.now().millisecondsSinceEpoch >= deadline) {
        return false;
      }
      await Future.delayed(const Duration(milliseconds: 220));
    }
    return false;
  }

  void _scheduleInitialDownloadChoicesPrompt({int delayMs = 120}) {
    if (!widget.downloadOnlyMode) return;
    _notifyDownloadStatus('resolving');
    if (_downloadPromptFlowLocked ||
        _downloadPromptPending ||
        _downloadChoiceLocked ||
        _downloadSelectionCommitted ||
        _downloadQualitySheetShown ||
        _hasActiveDownloadTask ||
        _downloadPromptConsumed) {
      return;
    }
    _downloadPromptFlowLocked = true;
    _downloadPromptPending = true;
    Future.delayed(Duration(milliseconds: delayMs), () async {
      _downloadPromptPending = false;
      if (!mounted) return;
      if (_downloadChoiceLocked ||
          _downloadSelectionCommitted ||
          _downloadQualitySheetShown ||
          _hasActiveDownloadTask ||
          _downloadPromptConsumed) {
        return;
      }
      final ready = await _waitForInitialDownloadChoices();
      if (!mounted) return;
      if (!ready) {
        _downloadPromptFlowLocked = false;
        _notifyDownloadStatus('error');
        _finishHiddenDownloadRoute('error');
        return;
      }
      if (_downloadChoiceLocked ||
          _downloadSelectionCommitted ||
          _downloadQualitySheetShown ||
          _hasActiveDownloadTask ||
          _downloadPromptConsumed) {
        return;
      }
      await _presentInitialDownloadChoices();
    });
  }

  Future<void> _beginHiddenDownloadCaptureIfNeeded() async {
    if (_wc == null) return;
    _notifyDownloadStatus('resolving');
    _downloadCaptureStarted = true;
    final current = ((await _wc!.getUrl())?.toString() ?? '').trim();
    if (current.isEmpty || current == 'about:blank') {
      await _wc!.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(widget.initialUrl),
          headers: const {'User-Agent': _ua},
        ),
      );
      return;
    }
    unawaited(_primeWatchPageCapture());
    _scheduleInitialDownloadChoicesPrompt(delayMs: 500);
  }

  List<PageQualityOption> _topThreeDownloadQualityOptions([List<PageQualityOption>? source]) {
    final raw = _dedupeQualityOptionsByLabel(List<PageQualityOption>.from(source ?? _sortedQualityOptions));
    if (raw.isEmpty) return const <PageQualityOption>[];
    raw.sort((a, b) => _qualityRankLabel(b.label).compareTo(_qualityRankLabel(a.label)));
    return raw.take(3).map((option) => PageQualityOption(
      label: _normalizeQualityLabel(option.label).ifEmpty(option.label.trim()),
      key: option.key,
      url: option.url,
      selected: option.selected,
    )).toList(growable: false);
  }

  CapturedMediaItem? _bestDownloadCandidateFromWatchLogic() {
    final item = _bestQuickMedia;
    if (item != null && _looksLikePlayableMediaUrl(item.url)) {
      return item;
    }

    final directCaptured = (_capturedVideoUrl ?? '').trim();
    if (_looksLikePlayableMediaUrl(directCaptured)) {
      return CapturedMediaItem(
        id: 'captured_watch_logic',
        url: directCaptured,
        pageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted ?? widget.initialUrl,
        fileName: _sanitizeFileName(_currentMediaTitleForSaving()),
        foundAt: DateTime.now(),
        isDirectFile: _isDirectMediaFile(directCaptured),
        isStream: _looksLikeHlsManifestUrl(directCaptured),
        mimeType: _inferMimeType(directCaptured),
        qualityLabel: _bestQuickMedia?.qualityLabel ?? _currentPageQualityLabel,
        headers: _bestCapturedHeadersForUrl(directCaptured),
      );
    }

    final currentQuality = _normalizeQualityLabel(_currentPageQualityLabel ?? '');
    PageQualityOption? directOption;
    for (final option in _pageQualityOptions) {
      if (!_looksLikePlayableMediaUrl(option.url)) continue;
      if (currentQuality.isNotEmpty && _normalizeQualityLabel(option.label) == currentQuality) {
        directOption = option;
        break;
      }
      directOption ??= option;
    }
    if (directOption != null && _looksLikePlayableMediaUrl(directOption.url)) {
      final resolvedUrl = directOption.url!.trim();
      return CapturedMediaItem(
        id: 'quality_watch_logic_${_normalizeQualityLabel(directOption.label)}',
        url: resolvedUrl,
        pageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted ?? widget.initialUrl,
        fileName: _sanitizeFileName(_currentMediaTitleForSaving()),
        foundAt: DateTime.now(),
        isDirectFile: _isDirectMediaFile(resolvedUrl),
        isStream: _looksLikeHlsManifestUrl(resolvedUrl),
        mimeType: _inferMimeType(resolvedUrl),
        qualityLabel: directOption.label,
        headers: _bestCapturedHeadersForUrl(resolvedUrl),
      );
    }

    PageServerOption? directServer;
    for (final option in _pageServerOptions) {
      if (!_looksLikePlayableMediaUrl(option.embedUrl)) continue;
      if (option.selected) {
        directServer = option;
        break;
      }
      directServer ??= option;
    }
    if (directServer != null && _looksLikePlayableMediaUrl(directServer.embedUrl)) {
      final resolvedUrl = directServer.embedUrl!.trim();
      return CapturedMediaItem(
        id: 'server_watch_logic_${directServer.key}',
        url: resolvedUrl,
        pageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted ?? widget.initialUrl,
        fileName: _sanitizeFileName(_currentMediaTitleForSaving()),
        foundAt: DateTime.now(),
        isDirectFile: _isDirectMediaFile(resolvedUrl),
        isStream: _looksLikeHlsManifestUrl(resolvedUrl),
        mimeType: _inferMimeType(resolvedUrl),
        qualityLabel: _currentPageQualityLabel,
        headers: _bestCapturedHeadersForUrl(resolvedUrl),
      );
    }

    return null;
  }

  Future<void> _prepareDownloadChoicesFromWatchLogic() async {
    final candidate = _bestDownloadCandidateFromWatchLogic();
    if (candidate == null) return;

    final cleanUrl = candidate.url.trim();
    final pageUrl = candidate.pageUrl.trim().isEmpty
        ? (_capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted ?? widget.initialUrl)
        : candidate.pageUrl.trim();

    _capturePlayableUrl(
      cleanUrl,
      pageUrl: pageUrl,
      mimeType: candidate.mimeType ?? _inferMimeType(cleanUrl),
      qualityLabel: candidate.qualityLabel ?? _currentPageQualityLabel,
    );

    if (_looksLikeHlsManifestUrl(cleanUrl)) {
      try {
        final headers = await _buildPipHeaders(
          cleanUrl,
          pageUrl: pageUrl,
        );
        await _prepareBestNativeMediaUrl(cleanUrl, headers);
      } catch (_) {}
    }

    if (_pageQualityOptions.isNotEmpty) return;

    final label = _normalizeQualityLabel(
      candidate.qualityLabel ?? _currentPageQualityLabel ?? '',
    ).ifEmpty('Auto');
    _updatePageQualityOptions(
      [
        PageQualityOption(
          label: label,
          key: 'captured_watch_logic_download',
          url: cleanUrl,
          selected: true,
        ),
      ],
      label,
    );
  }

  Future<void> _presentInitialDownloadChoices() async {
    if (!widget.downloadOnlyMode || _downloadQualitySheetShown || !mounted) return;
    if (_qualityDownloadSwitchPending || _downloadChoiceLocked || _downloadSelectionCommitted || _hasActiveDownloadTask || _downloadPromptConsumed) return;
    await _ensureDownloadQualityChoicesReady();
    await _prepareDownloadChoicesFromWatchLogic();
    var options = _topThreeDownloadQualityOptions();
    if (options.isEmpty) {
      final captured = (_bestDownloadCandidateFromWatchLogic()?.url ?? '').trim();
      if (captured.isNotEmpty) {
        final label = _normalizeQualityLabel(
          _bestDownloadCandidateFromWatchLogic()?.qualityLabel ?? _currentPageQualityLabel ?? '',
        ).ifEmpty('Auto');
        _updatePageQualityOptions(
          [
            PageQualityOption(
              label: label,
              key: 'captured_auto_download',
              url: captured,
              selected: true,
            ),
          ],
          label,
        );
        options = _topThreeDownloadQualityOptions();
      }
    }
    if (options.isEmpty) {
      _notifyDownloadStatus('error');
      _finishHiddenDownloadRoute('error');
      return;
    }

    _notifyDownloadStatus('choices');
    _downloadQualitySheetShown = true;
    await _showQualityDownloadSheet(
      forcedOptions: options,
      forceImmediateLabels: false,
    );
  }

  Future<void> _playBestCapturedMedia() async {
    _preventAutoReopenAfterNativeClose = false;
    final item = _bestQuickMedia;
    if (item != null) {
      _pendingNativeOpenOnPlayableCapture = false;
      await _openNativePlayer(
        force: true,
        replace: true,
        forcedUrl: item.url,
        forcedPageUrl: item.pageUrl,
        forcedMimeType: item.mimeType,
      );
      return;
    }

    final directCaptured = (_capturedVideoUrl ?? '').trim();
    if (_looksLikePlayableMediaUrl(directCaptured)) {
      _pendingNativeOpenOnPlayableCapture = false;
      await _openNativePlayer(
        force: true,
        replace: true,
        forcedUrl: directCaptured,
        forcedPageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted,
        forcedMimeType: _inferMimeType(directCaptured),
      );
      return;
    }

    final currentQuality = _normalizeQualityLabel(_currentPageQualityLabel ?? '');
    PageQualityOption? directOption;
    for (final option in _pageQualityOptions) {
      if (!_looksLikePlayableMediaUrl(option.url)) continue;
      if (currentQuality.isNotEmpty && _normalizeQualityLabel(option.label) == currentQuality) {
        directOption = option;
        break;
      }
      directOption ??= option;
    }

    if (directOption != null && _looksLikePlayableMediaUrl(directOption.url)) {
      _pendingNativeOpenOnPlayableCapture = false;
      await _openNativePlayer(
        force: true,
        replace: true,
        forcedUrl: directOption.url!,
        forcedPageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted,
        forcedMimeType: _inferMimeType(directOption.url),
      );
      return;
    }

    _armPendingPlayableCaptureOpen();
    if (!_isvidfastSession) {
      if (!_isvidfastSession) await _attemptFastExtraction();
    }
    if (!_nativePlayerActive && !_nativePlayerOpening && !_isVideasyPlayerUrl(widget.initialUrl) && !_isvidfastSession) {
      _showSnack('⚠️ لم يتم التقاط رابط مباشر بعد');
    }
  }

  Future<void> _startDownloadForQuality(PageQualityOption option) async {
    final normalizedLabel = _normalizeQualityLabel(option.label).ifEmpty(option.label.trim());
    _enableDownloadPassThrough();
    _downloadChoiceLocked = true;
    _downloadSelectionCommitted = true;
    _downloadPromptConsumed = true;
    _downloadPromptFlowLocked = true;
    _downloadQualitySheetShown = false;
    _autoDownloadPromptShown = true;
    _downloadPromptPending = false;
    _notifyDownloadStatus('background');
    _showPreparingDownloadPlaceholder(normalizedLabel);
    if (mounted) {
      setState(() {});
    }

    await _ensureDownloadQualityChoicesReady();

    PageQualityOption? resolveFreshOption() {
      for (final fresh in _topThreeDownloadQualityOptions()) {
        final freshLabel = _normalizeQualityLabel(fresh.label).ifEmpty(fresh.label.trim());
        if (freshLabel == normalizedLabel && _looksLikePlayableMediaUrl(fresh.url)) {
          return fresh;
        }
      }
      for (final fresh in _sortedQualityOptions) {
        final freshLabel = _normalizeQualityLabel(fresh.label).ifEmpty(fresh.label.trim());
        if (freshLabel == normalizedLabel && _looksLikePlayableMediaUrl(fresh.url)) {
          return fresh;
        }
      }
      return null;
    }

    final freshDirect = resolveFreshOption();
    if (freshDirect != null && _looksLikePlayableMediaUrl(freshDirect.url)) {
      await _startSmartDownloadFromPlayable(
        freshDirect.url!,
        qualityLabel: normalizedLabel,
        pageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted,
      );
      return;
    }

    final cached = _bestQuickMediaForQuality(normalizedLabel);
    if (cached != null) {
      await _startSmartDownloadFromPlayable(
        cached.url,
        qualityLabel: normalizedLabel,
        pageUrl: cached.pageUrl,
      );
      return;
    }

    if (_looksLikePlayableMediaUrl(option.url)) {
      await _startSmartDownloadFromPlayable(
        option.url!,
        qualityLabel: normalizedLabel,
        pageUrl: _capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted,
      );
      return;
    }

    final candidate = _bestDownloadCandidateFromWatchLogic();
    final candidateUrl = (candidate?.url ?? '').trim();
    if (_looksLikePlayableMediaUrl(candidateUrl)) {
      await _startSmartDownloadFromPlayable(
        candidateUrl,
        qualityLabel: normalizedLabel,
        pageUrl: candidate?.pageUrl.isNotEmpty == true
            ? candidate!.pageUrl
            : (_capturedVideoPageUrl ?? _currentPageUrl ?? _lastTrusted),
      );
      return;
    }

    _markPreparingDownloadPlaceholderError('تعذّر العثور على رابط الجودة $normalizedLabel');
    _showSnack('⚠️ تعذّر العثور على رابط ${normalizedLabel.isEmpty ? option.label : normalizedLabel}');
  }


  Future<void> _primevidfastDownloadCapture() async {
    return;
  }

  Future<void> _ensureDownloadQualityChoicesReady() async {
    if (_pageQualityOptions.isNotEmpty) return;

    if ((_capturedVideoUrl?.trim().isEmpty ?? true) && _wc != null) {
      try {
        await _primeWatchPageCapture();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 180));
    }

    await _prepareDownloadChoicesFromWatchLogic();
    if (_pageQualityOptions.isNotEmpty) return;

    final candidateItem = _bestDownloadCandidateFromWatchLogic();
    final candidate = (candidateItem?.url ?? '').trim();
    if (candidate.isEmpty) return;

    if (_looksLikeHlsManifestUrl(candidate)) {
      final pageUrl = (candidateItem?.pageUrl ?? _capturedVideoPageUrl ?? _currentPageUrl ?? '').trim();
      try {
        final headers = await _buildPipHeaders(
          candidate,
          pageUrl: pageUrl.isEmpty ? null : pageUrl,
        );
        await _prepareBestNativeMediaUrl(candidate, headers);
      } catch (_) {}
      if (_pageQualityOptions.isNotEmpty) return;
    }

    final normalized = _normalizeQualityLabel(
      candidateItem?.qualityLabel ?? _bestQuickMedia?.qualityLabel ?? _currentPageQualityLabel ?? '',
    ).ifEmpty('Auto');

    _updatePageQualityOptions(
      [
        PageQualityOption(
          label: normalized,
          key: 'captured_${normalized.toLowerCase()}',
          url: candidate,
          selected: true,
        ),
      ],
      normalized,
    );
  }

  Future<void> _downloadBestCapturedMedia() async {
    if (_downloadQualitySheetShown || _downloadChoiceLocked || _downloadSelectionCommitted || _downloadPromptConsumed) return;
    _downloadQualitySheetShown = true;
    try {
      await _ensureDownloadQualityChoicesReady();
      await _showQualityDownloadSheet(
        forcedOptions: (widget.downloadOnlyMode || widget.autoDownloadPrompt) ? _topThreeDownloadQualityOptions() : null,
        forceImmediateLabels: false,
      );
    } finally {
      if (!_qualityDownloadSwitchPending) {
        _downloadQualitySheetShown = false;
      }
    }
  }

  Future<void> _showQualityDownloadSheet({
    List<PageQualityOption>? forcedOptions,
    bool forceImmediateLabels = false,
  }) async {
    final rawOptions = forcedOptions ?? _sortedQualityOptions;
    final options = (widget.downloadOnlyMode || widget.autoDownloadPrompt)
        ? _topThreeDownloadQualityOptions(rawOptions)
        : rawOptions;
    if (options.isEmpty) {
      final item = _bestQuickMedia;
      if (item != null && item.isDirectFile) {
        await _startDownload(item.url, item.fileName, qualityLabel: item.qualityLabel);
        return;
      }
      _showSnack('⌛ لم تظهر الجودات بعد، انتظر قليلًا ثم أعد المحاولة');
      _notifyDownloadStatus('error');
      _finishHiddenDownloadRoute('error');
      return;
    }

    _notifyDownloadStatus('choices');
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: const Color(0xFF151A21),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اختر الجودة للتحميل',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                ...options.map((option) {
                  final normalized = _normalizeQualityLabel(option.label).ifEmpty(option.label);
                  final cached = _bestQuickMediaForQuality(normalized);
                  final readyDirect = !forceImmediateLabels && (cached?.isDirectFile == true || _isDirectMediaFile(option.url));
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      tileColor: const Color(0xFF21171B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      title: Text(
                        normalized,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        readyDirect ? 'تحميل مباشر' : 'سيبدأ التحضير بعد اختيار الجودة',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.download_rounded, color: Colors.white),
                      onTap: () {
                        if (_downloadChoiceLocked || _downloadSelectionCommitted || _hasActiveDownloadTask || _downloadPromptConsumed) return;
                        _downloadChoiceLocked = true;
                        _downloadSelectionCommitted = true;
                        _downloadPromptConsumed = true;
                        _downloadPromptFlowLocked = true;
                        _downloadPromptPending = false;
                        _downloadQualitySheetShown = false;
                        _enableDownloadPassThrough();
                        if (mounted) setState(() {});
                        Navigator.of(ctx).pop();
                        unawaited(_startDownloadForQuality(option));
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
    if (!_qualityDownloadSwitchPending) {
      _downloadQualitySheetShown = false;
    }
    if (widget.downloadOnlyMode && !_downloadSelectionCommitted && !_hasActiveDownloadTask) {
      _notifyDownloadStatus('idle');
      _finishHiddenDownloadRoute('idle');
    }
  }

  Future<void> _startHiddenQualityHarvest() async {
    return;
  }

  void _maybePromptDownloadChoices() {
    if (widget.downloadOnlyMode) return;
    if (!widget.autoDownloadPrompt || _autoDownloadPromptShown || !_looksLikeWatchPage()) {
      return;
    }
    final item = _bestQuickMedia;
    final hasMediaCandidate =
        item != null || ((_capturedVideoUrl ?? '').trim().isNotEmpty);
    final hasReadyQualities = _pageQualityOptions.isNotEmpty;
    if (!hasMediaCandidate && !hasReadyQualities) return;
    _autoDownloadPromptShown = true;
    Future.delayed(const Duration(milliseconds: 180), () async {
      if (!mounted || _nativePlayerActive || _nativePlayerOpening) return;
      await _downloadBestCapturedMedia();
    });
  }

  void _armPendingPlayableCaptureOpen() {
    if (_captureEngineSuspended || _preventAutoReopenAfterNativeClose) return;
    _pendingNativeOpenOnPlayableCapture = true;
    final token = ++_pendingPlayableCaptureToken;

    Future<void> probe() async {
      if (!mounted || _captureEngineSuspended) return;
      if (!_pendingNativeOpenOnPlayableCapture || token != _pendingPlayableCaptureToken) return;
      if (_bestQuickMedia != null || (_capturedVideoUrl?.trim().isNotEmpty ?? false)) {
        Future.microtask(() => _openNativePlayer(
              force: true,
              replace: true,
              startTimeOverride: _pendingNativeStartTime,
            ));
        return;
      }
      if (!_isvidfastSession) await _attemptFastExtraction();
    }

    for (final ms in const [0, 120, 320, 700, 1200]) {
      Future.delayed(Duration(milliseconds: ms), probe);
    }

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      if (token != _pendingPlayableCaptureToken) return;
      if (!_pendingNativeOpenOnPlayableCapture) return;
      if (_bestQuickMedia == null && (_capturedVideoUrl?.trim().isEmpty ?? true)) {
        _showSnack('⌛ إذا تأخر الالتقاط المباشر اضغط تشغيل مرة ثانية');
      }
    });
  }


  Future<void> _kickSitePlayerForCapture() async {
    if (_wc == null || _captureEngineSuspended) return;
    try {
      await _wc!.evaluateJavascript(source: r'''(function(){
        try {
          if (window.__asdSinglePlayKickInstalled) return;
          window.__asdSinglePlayKickInstalled = true;
          function visible(el) {
            if (!el || !el.getBoundingClientRect) return false;
            var st = window.getComputedStyle ? window.getComputedStyle(el) : null;
            if (st && (st.display === 'none' || st.visibility === 'hidden' || parseFloat(st.opacity || '1') < 0.03)) return false;
            var r = el.getBoundingClientRect();
            return r.width > 20 && r.height > 20 && r.bottom > 0 && r.right > 0 && r.left < window.innerWidth && r.top < window.innerHeight;
          }
          function fireAt(el, x, y) {
            if (!el) return false;
            var opts = {bubbles:true,cancelable:true,composed:true,view:window,clientX:x,clientY:y,screenX:x,screenY:y,button:0,buttons:1};
            try { el.dispatchEvent(new PointerEvent('pointerover', opts)); } catch(e) {}
            try { el.dispatchEvent(new PointerEvent('pointerenter', opts)); } catch(e) {}
            try { el.dispatchEvent(new PointerEvent('pointerdown', opts)); } catch(e) {}
            try { el.dispatchEvent(new MouseEvent('mousedown', opts)); } catch(e) {}
            try { el.dispatchEvent(new PointerEvent('pointerup', opts)); } catch(e) {}
            try { el.dispatchEvent(new MouseEvent('mouseup', opts)); } catch(e) {}
            try { el.dispatchEvent(new MouseEvent('click', opts)); } catch(e) {}
            try { el.click(); } catch(e) {}
            return true;
          }
          function score(el) {
            if (!visible(el)) return -1e9;
            var cls = String((el.className || '') + ' ' + (el.id || '')).toLowerCase();
            var txt = String((el.textContent || '') + ' ' + (el.getAttribute && (el.getAttribute('aria-label') || el.getAttribute('title') || el.getAttribute('data-testid') || el.getAttribute('data-icon') || ''))).toLowerCase();
            var r = el.getBoundingClientRect();
            var cx = r.left + r.width / 2;
            var cy = r.top + r.height / 2;
            var s = 0;
            if (cls.indexOf('vjs-big-play-button') !== -1) s += 120;
            if (cls.indexOf('jw-icon-display') !== -1 || cls.indexOf('jw-display-icon') !== -1) s += 120;
            if (cls.indexOf('plyr__control--overlaid') !== -1) s += 120;
            if (cls.indexOf('play') !== -1) s += 40;
            if (/(play|resume|watch|start|continue)/.test(txt)) s += 45;
            if (/تشغيل|مشاهدة|ابدأ|استمرار/.test(txt)) s += 45;
            if (/trailer|اعلان|إعلان/.test(txt)) s -= 120;
            if (r.width >= 32 && r.height >= 32 && r.width <= 220 && r.height <= 220) s += 20;
            s -= (Math.abs(cx - (window.innerWidth / 2)) + Math.abs(cy - (window.innerHeight / 2)) * 1.3) / 8;
            return s;
          }
          function findTarget() {
            var selectors = ['.vjs-big-play-button','.jw-icon-display','.jw-display-icon-container','.jw-display-icon','.plyr__control--overlaid','button[aria-label*="play" i]','button[title*="play" i]','[role="button"][aria-label*="play" i]','[data-testid*="play" i]','[class*="play"]','[id*="play"]','button','[role="button"]'];
            var best = null, bestScore = -1e9;
            selectors.forEach(function(sel){ try { document.querySelectorAll(sel).forEach(function(el){ var s = score(el); if (s > bestScore) { bestScore = s; best = el; } }); } catch(e) {} });
            if (best && bestScore > -50) return best;
            var media = document.querySelector('video, .jwplayer, .video-js, .plyr, [data-plyr], .player, [class*="player"]');
            if (visible(media)) return media;
            return document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
          }
          function clickOnceWhenReady() {
            if (window.__asdSinglePlayKickDone) return true;
            var target = findTarget();
            if (!target || !visible(target)) return false;
            var r = target.getBoundingClientRect();
            var x = Math.max(r.left + 2, Math.min(window.innerWidth - 2, r.left + r.width / 2));
            var y = Math.max(r.top + 2, Math.min(window.innerHeight - 2, r.top + r.height / 2));
            var hit = document.elementFromPoint(x, y) || target;
            window.__asdSinglePlayKickDone = true;
            fireAt(hit, x, y);
            return true;
          }
          if (clickOnceWhenReady()) return;
          var startedAt = Date.now();
          var obs = new MutationObserver(function(){
            if (window.__asdSinglePlayKickDone) { try { obs.disconnect(); } catch(e) {} return; }
            if (clickOnceWhenReady()) { try { obs.disconnect(); } catch(e) {} return; }
            if (Date.now() - startedAt > 8000) { try { obs.disconnect(); } catch(e) {} }
          });
          try { obs.observe(document.documentElement || document.body, {childList:true, subtree:true, attributes:true}); } catch(e) {}
          setTimeout(function(){ if (!window.__asdSinglePlayKickDone) clickOnceWhenReady(); try { obs.disconnect(); } catch(e) {} }, 2500);
        } catch(e) {}
      })();''');
    } catch (_) {}
  }

  Future<void> _primeWatchPageCapture() async {
    if (_wc == null || _captureEngineSuspended || !_looksLikeWatchPage()) return;
    unawaited(_kickSitePlayerForCapture());
    Future.delayed(const Duration(milliseconds: 250), () async {
      if (!mounted || _captureEngineSuspended) return;
      try {
        await _wc!.evaluateJavascript(
          source: 'window.__asdSmartPlay && window.__asdSmartPlay();',
        );
      } catch (_) {}
    });
    Future<void> runProbe() async {
      try {
        await _wc!.evaluateJavascript(source: r'''(function(){
          try {
            var href = (window.location.href || '').toLowerCase();
            var isVideasy = href.indexOf('videasy.net') !== -1 || href.indexOf('vidfast.pro') !== -1;
            if (isVideasy && !document.getElementById('__asd_no_fx')) {
              var css = document.createElement('style');
              css.id = '__asd_no_fx';
              css.textContent = '*{animation:none!important;transition:none!important;scroll-behavior:auto!important;filter:none!important;backdrop-filter:none!important;box-shadow:none!important;text-shadow:none!important;}';
              (document.head || document.documentElement).appendChild(css);
            }
            function clean(v) {
              return (v || '').toString().replace(/\s+/g, ' ').trim();
            }
            function visible(el) {
              if (!el || !el.getBoundingClientRect) return false;
              var st = window.getComputedStyle ? window.getComputedStyle(el) : null;
              if (st && (st.display === 'none' || st.visibility === 'hidden' || parseFloat(st.opacity || '1') < 0.05)) return false;
              var r = el.getBoundingClientRect();
              return r.width > 12 && r.height > 12 && r.bottom > 0 && r.right > 0 && r.left < window.innerWidth && r.top < window.innerHeight;
            }
            function clickAt(el) {
              if (!el || !visible(el)) return false;
              var r = el.getBoundingClientRect();
              var x = Math.max(r.left + 2, Math.min(window.innerWidth - 2, r.left + r.width / 2));
              var y = Math.max(r.top + 2, Math.min(window.innerHeight - 2, r.top + r.height / 2));
              var hit = document.elementFromPoint(x, y) || el;
              var opts = {bubbles:true,cancelable:true,composed:true,view:window,clientX:x,clientY:y,screenX:x,screenY:y,button:0,buttons:1};
              try { hit.dispatchEvent(new PointerEvent('pointerdown', opts)); } catch(e) {}
              try { hit.dispatchEvent(new MouseEvent('mousedown', opts)); } catch(e) {}
              try { hit.dispatchEvent(new PointerEvent('pointerup', opts)); } catch(e) {}
              try { hit.dispatchEvent(new MouseEvent('mouseup', opts)); } catch(e) {}
              try { hit.dispatchEvent(new MouseEvent('click', opts)); } catch(e) {}
              try { hit.click(); } catch(e) {}
              return true;
            }
            function score(el) {
              var txt = clean((el.textContent || '') + ' ' + (el.getAttribute && (el.getAttribute('title') || el.getAttribute('aria-label') || el.getAttribute('data-name') || el.getAttribute('data-testid')) || '')).toLowerCase();
              var cls = clean(((el.className || '') + ' ' + (el.id || '') + ' ' + (el.getAttribute && (el.getAttribute('data-role') || el.getAttribute('data-action') || el.getAttribute('data-testid')) || ''))).toLowerCase();
              var r = el.getBoundingClientRect();
              var cx = r.left + r.width / 2;
              var cy = r.top + r.height / 2;
              var s = 0;
              if (cls.indexOf('vjs-big-play-button') !== -1 || cls.indexOf('jw-icon-display') !== -1 || cls.indexOf('jw-display-icon') !== -1 || cls.indexOf('plyr__control--overlaid') !== -1) s += 60;
              if (/(play|watch|start|continue|stream|open)/.test(txt)) s += 18;
              if (/تشغيل|مشاهدة|ابدأ|استمرار/.test(txt)) s += 18;
              if (cls.indexOf('play') !== -1) s += 18;
              if ((el.tagName || '').toLowerCase() === 'button') s += 4;
              if (txt.indexOf('trailer') !== -1 || txt.indexOf('إعلان') !== -1) s -= 30;
              s -= (Math.abs(cx - window.innerWidth / 2) + Math.abs(cy - window.innerHeight / 2) * 1.2) / 12;
              return s;
            }
            var selectors = [
              '.vjs-big-play-button','.jw-icon-display','.jw-display-icon-container','.jw-display-icon','.plyr__control--overlaid',
              'button','a','[role="button"]','div[tabindex]','span[tabindex]',
              '[class*="play"]','[class*="watch"]','[class*="start"]','[class*="player"]',
              '[aria-label*="play" i]','[title*="play" i]','[aria-label*="watch" i]','[title*="watch" i]',
              '[data-testid*="play"]','[data-testid*="watch"]',
              '[id*="play"]','[id*="watch"]'
            ];
            var ranked = [];
            document.querySelectorAll(selectors.join(',')).forEach(function(el){
              if (!visible(el)) return;
              var s = score(el);
              if (s < 5) return;
              ranked.push([s, el]);
            });
            ranked.sort(function(a, b){ return b[0] - a[0]; });
            var best = ranked.length ? ranked[0][1] : document.querySelector('video, .jwplayer, .video-js, .plyr, [data-plyr], .player, [class*="player"]');
            if (best) clickAt(best);
            try {
              document.querySelectorAll('video,audio').forEach(function(v){
                try {
                  v.muted = true;
                  v.volume = 0;
                  var pr = v.play && v.play();
                  if (pr && pr.then) {
                    pr.then(function(){ setTimeout(function(){ try { v.pause(); } catch(e) {} }, 80); }).catch(function(){});
                  }
                } catch(e) {}
              });
            } catch(e) {}
            try { if (window.__asdCollectOptions) window.__asdCollectOptions(); } catch(e) {}
            try { if (window.__asdCollectMediaNow) window.__asdCollectMediaNow(); } catch(e) {}
          } catch(e) {}
        })();''');
      } catch (_) {}
    }
    for (final ms in const [60, 180, 360, 700, 1200, 1900, 2800, 4200]) {
      Future.delayed(Duration(milliseconds: ms), runProbe);
    }
    Future.delayed(const Duration(milliseconds: 2600), _pauseOriginalSitePlayer);
    Future.delayed(const Duration(milliseconds: 3200), _startHiddenQualityHarvest);
  }

  Widget _buildQuickMediaButtons() {
    if (!_showQuickMediaButtons) return const SizedBox.shrink();

    return Positioned(
      left: 10,
      right: 10,
      bottom: 12,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pageQualityOptions.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xCC11161D),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: _buildVidfastQualitySelector(),
              ),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6AA84F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async => _playBestCapturedMedia(),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text(
                        'مشاهدة',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6AA84F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async => _downloadBestCapturedMedia(),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text(
                        'تحميل',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaGrabberPanel() {
    if (!_showMediaGrabber) return const SizedBox.shrink();

    return Positioned(
      top: 10,
      left: 10,
      right: 10,
      bottom: 10,
      child: Material(
        color: const Color(0xFF11161D),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(color: Color(0xFF1A1318)),
              child: Row(
                children: [
                  const Icon(Icons.video_collection_outlined, color: Color(0xFFB3202A)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'أداة جلب الفيديو (${_capturedMedia.length})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _capturedMedia.clear();
                        _capturedMediaSeen.clear();
                      });
                    },
                    icon: const Icon(Icons.cleaning_services_outlined),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() => _showMediaGrabber = false);
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _capturedMedia.isEmpty
                  ? const Center(
                      child: Text(
                        'لا يوجد أي رابط ملتقط بعد',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(10),
                      itemCount: _capturedMedia.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final item = _capturedMedia[i];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF21171B),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.url,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFB3202A).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: Text(
                                      _mediaKindLabel(item),
                                      style: const TextStyle(color: Color(0xFFB3202A), fontSize: 12),
                                    ),
                                  ),
                                  if (item.mimeType != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF8E2630).withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      child: Text(
                                        item.mimeType!,
                                        style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFB3202A),
                                        foregroundColor: Colors.black,
                                        minimumSize: const Size.fromHeight(54),
                                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                      ),
                                      onPressed: () async {
                                        await _openNativePlayer(
                                          force: true,
                                          replace: true,
                                          forcedUrl: item.url,
                                          forcedPageUrl: item.pageUrl,
                                          forcedMimeType: item.mimeType,
                                        );
                                      },
                                      icon: const Icon(Icons.play_arrow),
                                      label: const Text('تشغيل'),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF26191E),
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size.fromHeight(54),
                                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                      ),
                                      onPressed: () async {
                                        if (item.isDirectFile) {
                                          await _startDownload(
                                            item.url,
                                            item.fileName,
                                            qualityLabel: item.qualityLabel,
                                          );
                                        } else {
                                          _showSnack('هذا رابط بث HLS/DASH، تم التقاطه للتشغيل وليس تنزيله المباشر');
                                        }
                                      },
                                      icon: const Icon(Icons.download_rounded),
                                      label: const Text('تحميل'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeDownloads = _downloads.where((d) => d.status == 'downloading').length;

    if (_exitHiddenRouteAfterNativeClose && widget.launchHidden && !widget.downloadOnlyMode && !widget.autoDownloadPrompt) {
      _popHiddenPlayerRouteSoon();
      return const SizedBox.shrink();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (widget.downloadOnlyMode) {
          _enableDownloadPassThrough();
          return;
        }
        if (_nativePlayerActive || _nativePlayerOpening) { await _closeNativePlayer(); return; }
        if (_fullscreen) { await _exitFullscreen(); return; }
        if (_showMediaGrabber) { setState(() => _showMediaGrabber = false); return; }
        if (_showDownloads) { _closeDownloadsPanel(); return; }
        if (widget.downloadOnlyMode && _downloadSelectionCommitted && !_hasActiveDownloadTask) {
          _enableDownloadPassThrough();
          return;
        }
        if (widget.launchHidden && context.mounted) {
          final nav = Navigator.of(context, rootNavigator: true);
          if (nav.canPop()) {
            nav.pop();
            return;
          }
        }
        if (_wc != null && await _wc!.canGoBack()) { await _wc!.goBack(); return; }
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          return;
        }
        if (context.mounted) SystemNavigator.pop();
      },
      child: IgnorePointer(
        ignoring: widget.downloadOnlyMode || _downloadPassThroughMode,
        child: Scaffold(
          backgroundColor: widget.downloadOnlyMode
            ? Colors.transparent
            : ((_hideSiteDuringDirectLaunch && !_showDownloads)
                ? Colors.transparent
                : Colors.black),
        appBar: (widget.downloadOnlyMode || _fullscreen || _hideSiteDuringDirectLaunch) ? null : AppBar(
          backgroundColor: const Color(0xFF1A1318),
          title: Text(widget.downloadOnlyMode ? 'التحميلات' : (widget.headerTitle ?? 'ASD Pics'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          actions: [
            if (!widget.downloadOnlyMode)
              Stack(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _showDownloads = !_showDownloads;
                        if (_showDownloads) _showMediaGrabber = false;
                      });
                    },
                    icon: const Icon(Icons.download_rounded),
                  ),
                  if (activeDownloads > 0)
                    Positioned(
                      right: 7,
                      top: 7,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Color(0xFFB3202A), shape: BoxShape.circle),
                        child: Text(
                          '$activeDownloads',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
        body: IgnorePointer(
          ignoring: widget.downloadOnlyMode || _downloadPassThroughMode,
          child: Stack(
            children: [
            _buildWebViewHost(
              InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
                initialUserScripts: UnmodifiableListView<UserScript>(_activeUserScripts.toList(growable: false)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  useShouldInterceptRequest: true,
                  transparentBackground: true,
                  userAgent: _ua,
                ),
                onWebViewCreated: (controller) {
                  _wc = controller;
                  _setupVidfastHandlers(controller);
                },
                shouldInterceptRequest: (controller, request) async {
                  final url = request.url.toString();
                  final requestHeaders = <String, String>{};
                  try {
                    request.headers?.forEach((key, value) {
                      requestHeaders[key.toString()] = value.toString();
                    });
                  } catch (_) {}
                  _rememberCapturedRequestHeaders(url, requestHeaders);
                  if ((url.contains('api.videasy.net') ||
                          url.contains('api2.videasy.net')) &&
                      url.contains('sources-with-title')) {
                    _lastDetectedSourceApiUrl = url;
                    final reqMethod = (request.method ?? '').toUpperCase();

                    if (reqMethod == 'OPTIONS') {
                      return WebResourceResponse(
                        statusCode: 200,
                        headers: {
                          'Access-Control-Allow-Origin': '*',
                          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
                          'Access-Control-Allow-Headers':
                              'cache-control,expires,pragma,content-type,authorization,origin,accept,x-requested-with',
                          'Access-Control-Max-Age': '86400',
                          'Content-Length': '0',
                        },
                        contentType: 'text/plain',
                        data: Uint8List(0),
                      );
                    }

                    if (reqMethod == 'GET') {
                      final nowMs = DateTime.now().millisecondsSinceEpoch;
                      final lastFetch =
                          _sourceBundleFetchTimestamps[url] ?? 0;
                      if (nowMs - lastFetch < 4000) {
                        final empty = utf8.encode(
                          '{"sources":[],"subtitles":[]}',
                        );
                        return WebResourceResponse(
                          statusCode: 200,
                          headers: {
                            'Access-Control-Allow-Origin': '*',
                            'Content-Type':
                                'application/json; charset=utf-8',
                            'Content-Length': '${empty.length}',
                          },
                          contentType: 'application/json',
                          data: Uint8List.fromList(empty),
                        );
                      }
                      _sourceBundleFetchTimestamps[url] = nowMs;

                      try {
                        final resp = await _dio.get<String>(
                          url,
                          options: Options(
                            responseType: ResponseType.plain,
                            receiveTimeout: const Duration(seconds: 20),
                            validateStatus: (s) => s != null && s < 600,
                            headers: {
                              'User-Agent': _ua,
                              'Accept': 'application/json, */*',
                              'Origin': 'https://player.videasy.net',
                              'Referer': 'https://player.videasy.net/',
                              'Cache-Control': 'no-cache',
                            },
                          ),
                        );

                        final statusCode = resp.statusCode ?? 0;
                        final body = (resp.data ?? '').toString().trim();
                        debugPrint(
                          '[VideasyAPI] $url → $statusCode (${body.length} chars)',
                        );

                        if (statusCode >= 200 &&
                            statusCode < 300 &&
                            body.isNotEmpty) {
                          debugPrint(
                            '[VideasyAPI-BODY-PREVIEW] ${body.substring(0, body.length.clamp(0, 400))}',
                          );

                          final bundle = _parseSourceBundleResponse(body, url);
                          if (bundle != null && mounted) {
                            setState(() => _applyCapturedSourceBundle(bundle));
                            debugPrint(
                              '[VideasyAPI] ✅ bundle applied: '
                              'servers=${((bundle["serverOptions"] as List?)?.length ?? 0)}, '
                              'quality=${((bundle["qualityOptions"] as List?)?.length ?? 0)}, '
                              'subs=${((bundle["subtitleTracks"] as List?)?.length ?? 0)}',
                            );
                          } else {
                            debugPrint(
                              '[VideasyAPI] ⚠️ bundle=null — parser لم يجد مصادر',
                            );
                          }

                          final bodyBytes =
                              Uint8List.fromList(utf8.encode(body));
                          return WebResourceResponse(
                            statusCode: statusCode,
                            headers: {
                              'Access-Control-Allow-Origin': '*',
                              'Access-Control-Allow-Methods':
                                  'GET, POST, OPTIONS',
                              'Content-Type':
                                  'application/json; charset=utf-8',
                              'Content-Length': '${bodyBytes.length}',
                            },
                            contentType: 'application/json',
                            data: bodyBytes,
                          );
                        }
                      } catch (e) {
                        debugPrint('[VideasyAPI] ❌ فشل: $e');
                      }

                      final empty = utf8.encode(
                        '{"sources":[],"subtitles":[]}',
                      );
                      return WebResourceResponse(
                        statusCode: 200,
                        headers: {
                          'Access-Control-Allow-Origin': '*',
                          'Content-Type': 'application/json; charset=utf-8',
                        },
                        contentType: 'application/json',
                        data: Uint8List.fromList(empty),
                      );
                    }
                  }

                  final isDetectedPlayable = _looksLikePlayableMediaUrl(url);
                  final isFinalTypedMedia = url.contains('.m3u8') || url.contains('.mp4') || url.contains('.mpd');

                  if (isDetectedPlayable) {
                    debugPrint("🎯 تم اصطياد رابط مرشح للتشغيل: $url");
                    _capturePlayableUrl(
                      url,
                      pageUrl: _currentPageUrl ?? widget.initialUrl,
                      mimeType: _inferMimeType(url),
                      qualityLabel: _currentPageQualityLabel,
                    );
                    if (mounted) {
                      setState(() {
                        _showQualityResolveLoader = false;
                      });
                    }
                    if (isFinalTypedMedia || _looksLikeVideasyProxyMediaUrl(url)) {
                      try {
                        await controller.stopLoading();
                      } catch (_) {}
                    }
                    if (_isvidfastSession &&
                        !widget.downloadOnlyMode &&
                        isFinalTypedMedia &&
                        _looksLikePlayableMediaUrl(url)) {
                      final mHost = Uri.tryParse(url)?.host.toLowerCase() ?? '';
                      final isCdnUrl = mHost.contains('10017.workers.dev') ||
                          mHost.contains('megafiles.store') ||
                          mHost.contains('rainorbit') ||
                          mHost.contains('nightbreeze') ||
                          mHost.contains('quietlynx') ||
                          mHost.contains('thunderleaf') ||
                          mHost.contains('workers.dev');
                      if (isCdnUrl) {
                        if (!_nativePlayerActive && !_nativePlayerOpening) {
                          Future.microtask(() => _openNativePlayer(
                                force: true,
                                replace: true,
                                forcedUrl: url,
                                forcedPageUrl: _currentPageUrl ?? widget.initialUrl,
                                forcedMimeType: _inferMimeType(url),
                              ));
                        }
                        return WebResourceResponse(
                          statusCode: 204,
                          headers: const {
                            'Access-Control-Allow-Origin': '*',
                          },
                          contentType: 'application/x-mpegURL',
                          data: Uint8List(0),
                        );
                      }
                    }
                    if (widget.downloadOnlyMode) {
                      _scheduleInitialDownloadChoicesPrompt();
                    } else if (widget.autoDownloadPrompt) {
                      if (!_qualityDownloadSwitchPending && !_autoDownloadPromptShown && !_downloadQualitySheetShown) {
                        _autoDownloadPromptShown = true;
                        await _pauseOriginalSitePlayer();
                        await _ensureDownloadQualityChoicesReady();
                        await _downloadBestCapturedMedia();
                      }
                    } else if (!_nativePlayerActive && !_nativePlayerOpening &&
                        (isFinalTypedMedia || _looksLikeVideasyProxyMediaUrl(url))) {
                      Future.microtask(() => _openNativePlayer(
                            force: true,
                            replace: true,
                            forcedUrl: url,
                            forcedPageUrl: _currentPageUrl ?? widget.initialUrl,
                            forcedMimeType: _inferMimeType(url),
                          ));
                    }
                  }
                  return null;
                },
                onLoadStop: (controller, url) async {
                  _currentPageUrl = url?.toString() ?? widget.initialUrl;
                  try {
                    await controller.evaluateJavascript(
                      source: VidfastCaptureExtract.js,
                    );
                  } catch (_) {}
                  if (_isvidfastSession) {
                    Future.delayed(const Duration(seconds: 2), () {
                      if (!mounted) return;
                      unawaited(rescanServers());
                    });
                  }
                  unawaited(_kickSitePlayerForCapture());
                  unawaited(_primeWatchPageCapture());
                  if (_isvidfastSession && widget.downloadOnlyMode) {
                    _scheduleInitialDownloadChoicesPrompt(delayMs: 700);
                  }
                  Future.delayed(const Duration(milliseconds: 400), () async {
                    if (!mounted || _captureEngineSuspended) return;
                    try {
                      await controller.evaluateJavascript(
                        source: 'window.__asdSmartPlay && window.__asdSmartPlay();',
                      );
                    } catch (_) {}
                  });
                  if (_isVideasyPlayerUrl(_currentPageUrl)) {
                    unawaited(_maybeFetchLatestSourceBundle(force: true));
                    for (final delay in [500, 1200, 2500, 4000]) {
                      Future.delayed(Duration(milliseconds: delay), () async {
                        if (!mounted || _captureEngineSuspended || _nativePlayerActive) return;
                        try {
                          await controller.evaluateJavascript(
                            source: 'window.__asdSelectCypher && window.__asdSelectCypher();',
                          );
                        } catch (_) {}
                      });
                    }
                  }
                  if (_pendingNativeOpenOnPlayableCapture &&
                      !_nativePlayerActive &&
                      !_nativePlayerOpening) {
                    Future.delayed(const Duration(milliseconds: 800), () async {
                      if (!mounted) return;
                      if (!_pendingNativeOpenOnPlayableCapture) return;
                      final candidate = await _collectFreshVideasyPlaybackCandidate();
                      final candidateUrl = (candidate?['url'] ?? '').toString().trim();
                      if (candidateUrl.isNotEmpty && mounted) {
                        _capturedVideoUrl = candidateUrl;
                        await _openNativePlayer(
                          force: true,
                          replace: true,
                          forcedUrl: candidateUrl,
                          forcedPageUrl: _currentPageUrl ?? widget.initialUrl,
                          forcedMimeType: (candidate?['mimeType'] ?? '').toString().trim().isEmpty
                              ? null
                              : (candidate?['mimeType'] ?? '').toString().trim(),
                        );
                      }
                    });
                  }
                  await controller.evaluateJavascript(source: '''
                    (function() {
                      var tries = 0;
                      function cleanText(v) {
                        return String(v || '').replace(/s+/g, ' ').trim().toLowerCase();
                      }
                      function tryPlay() {
                        tries++;
                        try {
                          var videos = document.querySelectorAll('video');
                          for (var i = 0; i < videos.length; i++) {
                            try {
                              videos[i].muted = true;
                              var p = videos[i].play();
                              if (p && p.catch) p.catch(function(){});
                            } catch (e) {}
                          }
                        } catch (e) {}

                        var selectors = [
                          '.play-button',
                          '.vjs-big-play-button',
                          'button[aria-label*="play" i]',
                          'button[title*="play" i]',
                          '[data-testid*="play" i]',
                          '[role="button"]',
                          'button'
                        ];
                        for (var s = 0; s < selectors.length; s++) {
                          var nodes = document.querySelectorAll(selectors[s]);
                          for (var n = 0; n < nodes.length; n++) {
                            var el = nodes[n];
                            var txt = cleanText(el.textContent || el.innerText || el.getAttribute('aria-label') || el.getAttribute('title'));
                            if (selectors[s] === '.play-button' || selectors[s] === '.vjs-big-play-button' || txt === 'play' || txt.indexOf('play') !== -1 || txt.indexOf('watch') !== -1) {
                              try { el.click(); } catch (e) {}
                            }
                          }
                        }
                        if (tries < 10) setTimeout(tryPlay, 650);
                      }
                      setTimeout(tryPlay, 350);
                    })();
                  ''');
                },
                onProgressChanged: (controller, progress) {
                  if (mounted) {
                    setState(() {
                      _progress = progress / 100;
                    });
                  }
                },
                onReceivedServerTrustAuthRequest: (controller, challenge) async {
                  return ServerTrustAuthResponse(
                    action: ServerTrustAuthResponseAction.CANCEL,
                  );
                },
              ),
            ),
            (!widget.downloadOnlyMode && !_hideSiteDuringDirectLaunch && _progress < 1.0)
                ? LinearProgressIndicator(
                    value: _progress,
                    color: const Color(0xFFB3202A),
                    backgroundColor: Colors.transparent,
                  )
                : const SizedBox.shrink(),
            if (_showQualityResolveLoader)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.28),
                      ),
                      child: const Center(
                        child: _WaveDropletLoader(size: 54),
                      ),
                    ),
                  ),
                ),
              ),
            _buildInlineDownloadStrip(),
            _buildDownloadsPanel(),
            _buildQuickMediaButtons(),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
