import 'dart:async';
import 'pwa/io_compat.dart' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:media_kit/media_kit.dart';
import 'pwa/refresh_rate_compat.dart';
import 'package:url_launcher/url_launcher.dart';

import 'sources/light_on_source.dart' as light_on;
import 'sources/anime_source.dart' as anime;
import 'sources/egy_source.dart' as egy;
import 'sources/arab_source.dart' as arab;
import 'secure_strings.dart';
import 'native_security_guard.dart';

final String kTelegramChannelUsername = AppSecureText.s('iLq06h6J');

final MethodChannel _sourceLauncher = MethodChannel(AppSecureText.s('3zUyKVLLweisI8xUoEY3ilg3iA'));

@pragma('vm:entry-point')
void lightOnMain() {
  light_on.lightOnSourceMain();
}

@pragma('vm:entry-point')
void animeMain() {
  anime.animeSourceMain();
}

@pragma('vm:entry-point')
void egyMain() {
  egy.egySourceMain();
}

@pragma('vm:entry-point')
void arabMain() {
  arab.arabSourceMain();
}

Future<void> openSourceActivity(BuildContext context, String source) async {
  if (!kIsWeb && Platform.isAndroid) {
    try {
      await _sourceLauncher.invokeMethod(
        AppSecureText.s('Wsvv7hL7FdrcGg'),
        <String, String>{AppSecureText.s('n7qu_QrZ'): source},
      );
      return;
    } catch (_) {}
  }

  Widget page;
  switch (source) {
    case 'light_on':
      // Web/PWA: do NOT push a nested MaterialApp. Use the same outer Navigator
      // so browser/back pops: player -> details -> Light On, not straight to selector.
      page = kIsWeb ? const light_on.CinemaTmdbRoot() : const light_on.CinemaTmdbApp();
      break;
    case 'anime':
      page = const anime.AsdPicsPlayer();
      break;
    case 'egy':
      page = const egy.C4uPlayer();
      break;
    case 'arab':
      page = const arab.AsdPicsPlayer();
      break;
    default:
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('المصدر غير معروف: $source')),
      );
      return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => page),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    MediaKit.ensureInitialized();
  }
  unawaited(NativeSecurityGuard.ensureClean());

  try {
    RefreshRate.enable();
    RefreshRate.preferMax();
  } catch (_) {}

  try {
    PaintingBinding.instance.imageCache.maximumSize = 160;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 96 << 20;
  } catch (_) {}

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const SelectorApp());
}

class SelectorApp extends StatelessWidget {
  const SelectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sources Selector',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF63818B),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
      ),
      home: const MainSelectorPage(),
    );
  }
}


Future<void> openTelegramChannel() async {
  final username = kTelegramChannelUsername.trim().replaceAll('@', '');

  if (username.isEmpty || username == 'YOUR_CHANNEL_USERNAME') {
    return;
  }

  final tgUri = Uri.parse('tg://resolve?domain=$username');
  final webUri = Uri.parse('https://t.me/$username');

  try {
    final openedApp = await launchUrl(
      tgUri,
      mode: LaunchMode.externalApplication,
    );

    if (!openedApp) {
      await launchUrl(
        webUri,
        mode: LaunchMode.externalApplication,
      );
    }
  } catch (_) {
    await launchUrl(
      webUri,
      mode: LaunchMode.externalApplication,
    );
  }
}

class _TelegramFooter extends StatelessWidget {
  const _TelegramFooter();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: openTelegramChannel,
        borderRadius: BorderRadius.circular(16),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 50,
                height: 60,
                child: _TelegramLottieIcon(),
              ),
              SizedBox(height: 6),
              Text(
                'قناة تيليكرام',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'By KR',
                style: TextStyle(
                  color: Color.fromARGB(255, 173, 173, 173),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.italic,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TelegramLottieIcon extends StatelessWidget {
  const _TelegramLottieIcon();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Lottie.asset(
        'assets/tele.json',
        repeat: true,
        animate: true,
        fit: BoxFit.contain,

        frameRate: FrameRate.max,

        addRepaintBoundary: true,
      ),
    );
  }
}

class MainSelectorPage extends StatefulWidget {
  const MainSelectorPage({super.key});

  @override
  State<MainSelectorPage> createState() => _MainSelectorPageState();
}

class _MainSelectorPageState extends State<MainSelectorPage> {
  Future<void> _showSubtitleActivationGuide() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SubtitleActivationGuideSheet(
        onDone: () async {
          if (mounted && Navigator.of(sheetContext).canPop()) {
            Navigator.of(sheetContext).pop();
          }
        },
      ),
    );
  }

  void _showNotLinked(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.black.withValues(alpha: 0.82),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1000),
        content: Text(
          '$name غير مربوط بعد',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final small = size.width < 380;

    return Scaffold(
      backgroundColor: const Color(0xFF2C5461),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Transform.translate(
                offset: Offset(0, size.height * -0.03),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AnimatedGoldSourceTile(
                      title: 'Light On',
                      subtitle: 'الافلام والمسلسلات الاجنبية FULL HD',
                      width: small ? 185 : 205,
                      height: 62,
                      titleSize: 24,
                      subtitleSize: 15,
                      onTap: () => openSourceActivity(context, AppSecureText.s('8XchekKjalo')),
                    ),
                    const SizedBox(height: 42),
                    _SourceTile(
                      title: 'Salt Website',
                      subtitle: '',
                      boxColor: const Color.fromARGB(255, 202, 209, 206),
                      width: small ? 205 : 225,
                      height: 62,
                      titleSize: 24,
                      subtitleSize: 0,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SaltSectionsPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const Positioned(
              left: 18,
              bottom: 26,
              child: _TelegramFooter(),
            ),
            Positioned(
              right: 18,
              top: 82,
              child: _SubtitleGuideButton(
                onTap: () => _showSubtitleActivationGuide(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubtitleGuideButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SubtitleGuideButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE6E6E6)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.subtitles_rounded,
                color: Color(0xFF108D4F),
                size: 19,
              ),
              SizedBox(width: 7),
              Text(
                'تفعيل ترجمة Light On',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Color(0xFF10241A),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtitleActivationGuideSheet extends StatefulWidget {
  final FutureOr<void> Function() onDone;

  const _SubtitleActivationGuideSheet({required this.onDone});

  @override
  State<_SubtitleActivationGuideSheet> createState() => _SubtitleActivationGuideSheetState();
}

class _SubtitleActivationGuideSheetState extends State<_SubtitleActivationGuideSheet> {
  static const List<String> _images = [
    'assets/subtitle_activation/1.jpg',
    'assets/subtitle_activation/2.jpg',
    'assets/subtitle_activation/3.jpg',
    'assets/subtitle_activation/4.jpg',
    'assets/subtitle_activation/5.jpg',
    'assets/subtitle_activation/6.jpg',
    'assets/subtitle_activation/7.jpg',
    'assets/subtitle_activation/8.jpg',
    'assets/subtitle_activation/9.jpg',
    'assets/subtitle_activation/10.jpg',
    'assets/subtitle_activation/11.jpg',
  ];

  late final PageController _controller;
  int _page = 0;
  bool _closing = false;

  int get _totalPages => _images.length + 1;
  bool get _isLastPage => _page >= _totalPages - 1;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _nextOrDone() async {
    if (_closing) return;
    if (_isLastPage) {
      setState(() => _closing = true);
      await widget.onDone();
      return;
    }
    await _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _previous() async {
    if (_page <= 0 || _closing) return;
    await _controller.previousPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final sheetHeight = size.height * 0.92;

    return SafeArea(
      top: true,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          height: sheetHeight,
          margin: const EdgeInsets.fromLTRB(10, 12, 10, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF101F25),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              children: [
                _SubtitleGuideHeader(
                  page: _page,
                  total: _totalPages,
                  onClose: () async {
                    if (_closing) return;
                    setState(() => _closing = true);
                    await widget.onDone();
                  },
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    onPageChanged: (value) => setState(() => _page = value),
                    itemCount: _totalPages,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return const _SubtitleIntroPage();
                      }
                      return _SubtitleImageStepPage(
                        imagePath: _images[index - 1],
                        index: index,
                        total: _images.length,
                      );
                    },
                  ),
                ),
                _SubtitleGuideFooter(
                  page: _page,
                  total: _totalPages,
                  isLastPage: _isLastPage,
                  onPrevious: _previous,
                  onNext: _nextOrDone,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubtitleGuideHeader extends StatelessWidget {
  final int page;
  final int total;
  final FutureOr<void> Function() onClose;

  const _SubtitleGuideHeader({
    required this.page,
    required this.total,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF174A54), Color(0xFF0D2D35)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFF15A05B),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.subtitles_rounded, color: Colors.white, size: 21),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تفعيل ترجمة Light On',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Text(
              '${page + 1}/$total',
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () { onClose(); },
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            tooltip: 'إغلاق',
          ),
        ],
      ),
    );
  }
}

class _SubtitleIntroPage extends StatelessWidget {
  const _SubtitleIntroPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF35D17B),
                        size: 48,
                      ),
                      SizedBox(height: 14),
                      Text(
                        'لتفعيل الترجمة',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 18),
                      Text(
                        'طبّق الخطوات بعد هذه الصفحة بالتسلسل. عندما تكمل وتسجل من موقع subsource.net وتنسخ API، ضعه في خانة تفعيل الترجمة الموجودة في خانة مكتبتي فوق من اليسار، ثم اضغط اختبار. بعد نجاح التفعيل ستكون الترجمة متاحة.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFE9F4F1),
                          fontSize: 17,
                          height: 1.65,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubtitleImageStepPage extends StatelessWidget {
  final String imagePath;
  final int index;
  final int total;

  const _SubtitleImageStepPage({
    required this.imagePath,
    required this.index,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Text(
              'الخطوة $index من $total',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 3.2,
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'لم يتم العثور على الصورة:\n$imagePath\n\nتأكد من نسخ مجلد assets/subtitle_activation وإضافته إلى pubspec.yaml',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubtitleGuideFooter extends StatelessWidget {
  final int page;
  final int total;
  final bool isLastPage;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _SubtitleGuideFooter({
    required this.page,
    required this.total,
    required this.isLastPage,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      color: const Color(0xFF0B171C),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: page == 0 ? null : onPrevious,
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('السابق'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white24,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(total, (i) {
                final selected = i == page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: selected ? 20 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF35D17B) : Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onNext,
            icon: Icon(isLastPage ? Icons.check_rounded : Icons.chevron_left_rounded),
            label: Text(isLastPage ? 'إنهاء' : 'التالي'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF15A05B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}


class SaltSectionsPage extends StatelessWidget {
  const SaltSectionsPage({super.key});

  static const Color background = Color(0xFF2C5461);

  void _showNotLinked(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.black.withValues(alpha: 0.82),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1000),
        content: Text(
          '$name غير مربوط بعد',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final small = size.width < 380;

    return Scaffold(
      backgroundColor: const Color(0xFF2C5461),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 10,
              top: 6,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                tooltip: 'رجوع',
              ),
            ),
            const Positioned(
              left: 18,
              bottom: 26,
              child: _TelegramFooter(),
            ),
            Center(
              child: Transform.translate(
                offset: Offset(0, size.height * -0.03),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SourceTile(
                      title: 'Ainme',
                      subtitle: 'افلام ومسلسلات أنمي',
                      boxColor: const Color.fromARGB(255, 218, 218, 218),
                      width: small ? 185 : 205,
                      height: 60,
                      titleSize: 23,
                      subtitleSize: 14,
                      onTap: () => openSourceActivity(context, AppSecureText.s('GHGF_tE')),
                    ),
                    const SizedBox(height: 34),
                    _SourceTile(
                      title: 'EGY',
                      subtitle: 'افلام ومسلسلات • تركي • عرب • انمي • اجنبي..',
                      boxColor: const Color.fromARGB(246, 0, 129, 189),
                      width: small ? 235 : 285,
                      height: 60,
                      titleSize: 23,
                      subtitleSize: 13,
                      onTap: () => openSourceActivity(context, AppSecureText.s('gSfN')),
                    ),
                    const SizedBox(height: 34),
                    _SourceTile(
                      title: 'ARAB',
                      subtitle: 'افلام ومسلسلات • تركي • عرب • انمي • اجنبي..',
                      boxColor: const Color.fromARGB(255, 183, 230, 193),
                      width: small ? 245 : 295,
                      height: 60,
                      titleSize: 23,
                      subtitleSize: 13,
                      onTap: () => openSourceActivity(context, AppSecureText.s('fNsPVA')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedGoldSourceTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final double width;
  final double height;
  final double titleSize;
  final double subtitleSize;
  final VoidCallback onTap;

  const _AnimatedGoldSourceTile({
    required this.title,
    required this.subtitle,
    required this.width,
    required this.height,
    required this.titleSize,
    required this.subtitleSize,
    required this.onTap,
  });

  @override
  State<_AnimatedGoldSourceTile> createState() => _AnimatedGoldSourceTileState();
}

class _AnimatedGoldSourceTileState extends State<_AnimatedGoldSourceTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(2),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF8C6A00),
                            Color(0xFFC9A227),
                            Color(0xFFE0B84B),
                            Color(0xFF9F7A12),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          final slide = (_controller.value * 2.2) - 0.6;
                          return Transform.translate(
                            offset: Offset(widget.width * slide, 0),
                            child: Transform.rotate(
                              angle: -0.30,
                              child: Container(
                                width: widget.width * 0.38,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withValues(alpha: 0),
                                      Colors.white.withValues(alpha: 0.10),
                                      Colors.white.withValues(alpha: 0.20),
                                      Colors.white.withValues(alpha: 0.10),
                                      Colors.white.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: widget.titleSize,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 9),
          SizedBox(
            width: widget.width + 60,
            child: Text(
              widget.subtitle,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.subtitleSize,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color boxColor;
  final double width;
  final double height;
  final double titleSize;
  final double subtitleSize;
  final VoidCallback onTap;

  const _SourceTile({
    required this.title,
    required this.subtitle,
    required this.boxColor,
    required this.width,
    required this.height,
    required this.titleSize,
    required this.subtitleSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitle.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: boxColor,
          elevation: 3,
          shadowColor: Colors.black.withValues(alpha: 0.40),
          borderRadius: BorderRadius.circular(2),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              width: width,
              height: height,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (hasSubtitle) ...[
          const SizedBox(height: 9),
          SizedBox(
            width: width + 60,
            child: Text(
              subtitle,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: subtitleSize,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
