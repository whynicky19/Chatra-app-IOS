import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/errors.dart';

/// Вступительные экраны для нового пользователя.
///
/// Показываются один раз, до выбора организации и входа — то есть до того, как
/// известна роль. Поэтому текст про продукт в целом, а не про конкретную роль:
/// подсказки под студента/преподавателя уместнее в пустых состояниях уже
/// внутри приложения.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  static const _seenKey = 'onboarding_seen_v1';

  /// Видел ли пользователь интро. При ошибке чтения считаем, что видел —
  /// лучше не показать интро, чем застрять на нём при сбое хранилища.
  static Future<bool> isSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_seenKey) ?? false;
    } catch (e) {
      logError('Onboarding.isSeen', e);
      return true;
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenKey, true);
    } catch (e) {
      logError('Onboarding.markSeen', e);
    }
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await OnboardingScreen.markSeen();
    widget.onDone();
  }

  void _next(int total) {
    HapticFeedback.selectionClick();
    if (_page >= total - 1) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;

    final pages = <(IconData, String, String)>[
      (CupertinoIcons.book_fill, 'onb_1_title', 'onb_1_body'),
      (CupertinoIcons.chat_bubble_2_fill, 'onb_2_title', 'onb_2_body'),
      (CupertinoIcons.sparkles, 'onb_3_title', 'onb_3_body'),
    ];
    final isLast = _page == pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // «Пропустить» — обязательный выход: заставлять листать интро нельзя.
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
              child: TextButton(
                onPressed: _finish,
                child: Text(l.t('onb_skip'),
                    style: const TextStyle(fontSize: 14.5, color: C.text4)),
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final (icon, titleKey, bodyKey) = pages[i];
                return _Page(icon: icon, title: l.t(titleKey), body: l.t(bodyKey));
              },
            ),
          ),
          // Индикатор страниц
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pages.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _page ? primary : C.text4.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: GestureDetector(
              onTap: () => _next(pages.length),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                // minHeight, чтобы подпись не резалась при крупном системном шрифте.
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: primaryGlow(primary, opacity: 0.34),
                ),
                child: Align(
                  heightFactor: 1,
                  child: Text(
                    isLast ? l.t('onb_start') : l.t('onb_next'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Page({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [secondary, primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: primaryGlow(primary, opacity: 0.28),
            ),
            child: Icon(icon, size: 46, color: Colors.white),
          ),
          const SizedBox(height: 36),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: -0.5,
                  color: adaptiveText1(context))),
          const SizedBox(height: 14),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, height: 1.55, color: C.text4)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
