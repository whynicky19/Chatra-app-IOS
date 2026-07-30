import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/errors.dart';
import '../../widgets/ambient_glow.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  static const _seenKey = 'onboarding_seen_v1';

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

    // Вместо иконок — мини-мокапы реального интерфейса приложения.
    // Порядок — от простого к главному: материалы → ИИ знает курс → ИИ
    // проверяет работу. Ключи в словаре исторически названы по мокапам
    // (onb_1 — классы, onb_3 — ИИ-чат), а не по порядку страниц — при
    // добавлении третьей страницы (onb_2, проверка заданий) переименовывать
    // существующие ключи не стали, чтобы не плодить лишний диф.
    final pages = <(Widget, String, String, String)>[
      (const _ClassMock(), 'onb_1_tag', 'onb_1_title', 'onb_1_body'),
      (const _AiMock(), 'onb_3_tag', 'onb_3_title', 'onb_3_body'),
      (const _CheckMock(), 'onb_2_tag', 'onb_2_title', 'onb_2_body'),
    ];
    final isLast = _page == pages.length - 1;

    return Scaffold(
      body: Stack(children: [
        // Мягкое фирменное свечение — как на экране входа.
        AmbientGlow(
          alignment: const Alignment(0, -0.7),
          color: primary.withValues(alpha: 0.12),
          opacity: 1,
        ),
        SafeArea(
          child: Column(children: [
            // «Пропустить» — обязательный выход из интро.
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                child: TextButton(
                  onPressed: _finish,
                  child: Text(l.t('onb_skip'),
                      style: const TextStyle(fontSize: 15, color: C.text4)),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  final (mock, tagKey, titleKey, bodyKey) = pages[i];
                  return _Page(
                    mock: mock,
                    tag: l.t(tagKey),
                    title: l.t(titleKey),
                    body: l.t(bodyKey),
                  );
                },
              ),
            ),
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
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Page extends StatelessWidget {
  final Widget mock;
  final String tag;
  final String title;
  final String body;
  const _Page({
    required this.mock,
    required this.tag,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 12),
            mock,
            const SizedBox(height: 40),
            Text(tag.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                    color: primary)),
            const SizedBox(height: 10),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.8,
                    color: adaptiveText1(context))),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, height: 1.6, color: C.text4)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Мини-мокапы интерфейса ────────────────────────────────────────────────────
// Текст в мокапах — плашки-«скелетоны»: не требуют локализации и читаются как
// набросок интерфейса, а не как контент.

Color _barColor(BuildContext context) => C.text4.withValues(alpha: 0.22);

Widget _bar(BuildContext context, double w, {double h = 8}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: _barColor(context),
        borderRadius: BorderRadius.circular(h / 2),
      ),
    );

BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      boxShadow: cardShadow(Theme.of(context).brightness == Brightness.dark),
    );

/// Страница 1: карточка класса — обложка, название, бейджи материалов.
class _ClassMock extends StatelessWidget {
  const _ClassMock();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    Widget chip(IconData icon) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: primary),
            const SizedBox(width: 6),
            _bar(context, 34, h: 6),
          ]),
        );

    return Container(
      width: 280,
      decoration: _cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          height: 84,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [secondary, primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _bar(context, 150, h: 12),
            const SizedBox(height: 9),
            _bar(context, 92, h: 8),
            const SizedBox(height: 16),
            Row(children: [
              chip(CupertinoIcons.play_circle),
              const SizedBox(width: 8),
              chip(CupertinoIcons.doc_text),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Страница 2: диалог с Chatra AI.
class _AiMock extends StatelessWidget {
  const _AiMock();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: 280,
      child: Column(children: [
        // Вопрос студента.
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [primary, secondary]),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(5),
              ),
              boxShadow: softShadow(isDark),
            ),
            child: Container(
              width: 104,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Ответ ассистента.
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(5),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: softShadow(isDark),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(CupertinoIcons.sparkles, size: 13, color: primary),
                const SizedBox(width: 5),
                Text('Chatra AI',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: primary)),
              ]),
              const SizedBox(height: 10),
              _bar(context, 168),
              const SizedBox(height: 6),
              _bar(context, 188),
              const SizedBox(height: 6),
              _bar(context, 120),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Страница 3: сдача проверена ИИ — оценка по критериям и разбор.
/// Собрана из тех же элементов, что реальная карточка оценки в
/// class_assignments_tab.dart: крупная оценка "../100", тонкая шкала под
/// ней, строки критериев с зелёной галочкой и бейдж "проверено ИИ".
class _CheckMock extends StatelessWidget {
  const _CheckMock();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    Widget criterionRow(double w) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            const Icon(CupertinoIcons.checkmark_circle_fill, size: 15, color: C.green),
            const SizedBox(width: 8),
            _bar(context, w, h: 7),
          ]),
        );

    return Container(
      width: 280,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          _bar(context, 38, h: 24),
          const SizedBox(width: 5),
          Text('/100', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.text4)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [secondary, primary]),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(CupertinoIcons.sparkles, size: 11, color: Colors.white),
              const SizedBox(width: 4),
              const Text('Chatra AI',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: 0.82,
            minHeight: 5,
            backgroundColor: _barColor(context),
            valueColor: AlwaysStoppedAnimation(primary),
          ),
        ),
        const SizedBox(height: 18),
        criterionRow(150),
        criterionRow(190),
        criterionRow(110),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _barColor(context).withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _bar(context, double.infinity, h: 7),
            const SizedBox(height: 6),
            _bar(context, 160, h: 7),
          ]),
        ),
      ]),
    );
  }
}
