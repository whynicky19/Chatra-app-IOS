import 'package:chatra_app/providers/l10n_provider.dart';
import 'package:chatra_app/services/api_service.dart';
import 'package:chatra_app/theme/app_theme.dart';
import 'package:chatra_app/utils/cover_art.dart';
import 'package:chatra_app/widgets/cover_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Оформление обложек предметов на мобильном клиенте.
///
/// Набор цветов и иконок — контракт с бэкендом (GET /classes/cover/options,
/// services/cover_art.py) и с вебом (composables/useCoverArt.ts). Разъехавшийся
/// набор ничего не ломает шумно: пикер просто предложит вариант, которого
/// сервер не знает, и обложка молча получится не той. Поэтому запасной набор
/// и глифы проверяются здесь явно.
void main() {
  group('CoverOptions.fromJson', () {
    test('разбирает ответ бэкенда', () {
      final o = CoverOptions.fromJson({
        'colors': [
          {'id': 'blue', 'hex': '#0A84FF', 'deep': '#0A2A5E'},
          {'id': 'teal', 'hex': '#00B1C9', 'deep': '#00303A'},
        ],
        'icons': [
          {'id': 'sigma', 'subject': 'Mathematics'},
          {'id': 'atom', 'subject': 'Physics'},
        ],
        'default_color': 'teal',
        'default_icon': 'sigma',
        'ai_available': false,
      });

      expect(o.colors.map((c) => c.id), ['blue', 'teal']);
      expect(o.colors.first.hex, const Color(0xFF0A84FF));
      expect(o.icons.map((i) => i.id), ['sigma', 'atom']);
      expect(o.defaultColor, 'teal');
      expect(o.aiAvailable, isFalse);
    });

    test('пустой ответ подменяется запасным набором', () {
      // Иначе пикер остался бы без единого варианта и предмет нельзя было бы
      // создать вообще — а это ровно то, что должно продолжать работать
      // при недоступном или устаревшем бэкенде.
      final o = CoverOptions.fromJson({'colors': [], 'icons': []});
      expect(o.colors, isNotEmpty);
      expect(o.icons, isNotEmpty);
    });

    test('битый hex не роняет разбор', () {
      final o = CoverOptions.fromJson({
        'colors': [
          {'id': 'broken', 'hex': 'not-a-colour', 'deep': '#000000'},
          {'id': 'blue', 'hex': '#0A84FF', 'deep': '#0A2A5E'},
        ],
        'icons': [
          {'id': 'book', 'subject': 'Literature'},
        ],
      });
      expect(o.colors.map((c) => c.id), ['blue']);
    });

    test('colorFor падает на дефолт для неизвестного слага', () {
      expect(kFallbackCoverOptions.colorFor('chartreuse').id,
          kFallbackCoverOptions.defaultColor);
      expect(kFallbackCoverOptions.colorFor(null).id,
          kFallbackCoverOptions.defaultColor);
      expect(kFallbackCoverOptions.colorFor('blue').id, 'blue');
    });
  });

  group('запасной набор', () {
    test('у каждой иконки есть глиф', () {
      // Иконка без пути рисовалась бы книжкой — пользователь выбрал бы
      // «Физику», а увидел бы книгу.
      for (final icon in kFallbackCoverOptions.icons) {
        expect(kCoverIconPaths.containsKey(icon.id), isTrue,
            reason: 'нет глифа для ${icon.id}');
      }
      expect(kCoverIconPaths.keys.toSet(),
          kFallbackCoverOptions.icons.map((i) => i.id).toSet());
    });

    test('у каждой иконки есть подпись на всех трёх языках', () {
      for (final icon in kFallbackCoverOptions.icons) {
        for (final lang in ['RU', 'EN', 'KZ']) {
          expect(kCoverIconLabels[icon.id]?[lang], isNotNull,
              reason: 'нет подписи ${icon.id} для $lang');
        }
      }
    });

    test('дефолты входят в набор', () {
      expect(kFallbackCoverOptions.colors.map((c) => c.id),
          contains(kFallbackCoverOptions.defaultColor));
      expect(kFallbackCoverOptions.icons.map((i) => i.id),
          contains(kFallbackCoverOptions.defaultIcon));
    });

    test('цвета совпадают с палитрой бэкенда', () {
      // Дублирует PALETTE из services/cover_art.py: превью до генерации
      // должно совпадать с тем, что реально нарисует сервер.
      const expected = {
        'blue': 0xFF0A84FF, 'purple': 0xFF8B5CF6, 'green': 0xFF22C55E,
        'orange': 0xFFF97316, 'red': 0xFFEF4444, 'pink': 0xFFEC4899,
        'teal': 0xFF00B1C9, 'indigo': 0xFF6366F1,
      };
      expect(
        {for (final c in kFallbackCoverOptions.colors) c.id: c.hex.toARGB32()},
        expected,
      );
    });
  });

  group('coverIconSvg', () {
    test('собирает валидный SVG с нужным путём', () {
      final svg = coverIconSvg('sigma');
      expect(svg, startsWith('<svg'));
      expect(svg, contains(kCoverIconPaths['sigma']!));
      expect(svg, contains('fill="none"'));
    });

    test('неизвестная иконка не роняет рендер', () {
      expect(coverIconSvg('banana'), contains(kCoverIconPaths['book']!));
      expect(coverIconSvg(null), contains(kCoverIconPaths['book']!));
    });

    test('цвет попадает в stroke', () {
      expect(coverIconSvg('atom', color: const Color(0xFF00B1C9)),
          contains('stroke="#00b1c9"'));
    });
  });

  group('виджет CoverAppearance', () {
    // Набор засеян заранее — иначе пикер пошёл бы за ним в сеть из initState,
    // и висящий таймер уронил бы тест.
    setUp(() => CoverOptionsCache.reset(kFallbackCoverOptions));
    tearDown(() => CoverOptionsCache.reset());

    Widget wrap(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => L10n()),
            Provider(create: (_) => ApiService(baseUrl: 'http://localhost:8000/api')),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        );

    testWidgets('собирается без обложки и без кнопки генерации до создания',
        (tester) async {
      await tester.pumpWidget(wrap(CoverAppearance(
        color: 'blue',
        icon: 'sigma',
        classId: null,
        onColorChanged: (_) {},
        onIconChanged: (_) {},
        onGenerate: () {},
      )));
      await tester.pump();

      // classId == null — предмет ещё не создан, генерировать нечему.
      expect(find.text('Сгенерировать обложку'), findsNothing);
      expect(find.text('Цвет'), findsOneWidget);
      expect(find.text('Иконка'), findsOneWidget);
    });

    testWidgets('у созданного предмета показывает кнопку генерации',
        (tester) async {
      await tester.pumpWidget(wrap(CoverAppearance(
        color: 'blue',
        icon: 'sigma',
        classId: 7,
        onColorChanged: (_) {},
        onIconChanged: (_) {},
        onGenerate: () {},
      )));
      await tester.pump();

      expect(find.text('Сгенерировать обложку'), findsOneWidget);
    });

    testWidgets('с сохранённой обложкой предлагает перегенерировать',
        (tester) async {
      await tester.pumpWidget(wrap(CoverAppearance(
        color: 'blue',
        icon: 'sigma',
        classId: 7,
        coverUrl: 'https://cdn.test/materials/covers/cover_x.webp',
        coverSource: 'ai',
        onColorChanged: (_) {},
        onIconChanged: (_) {},
        onGenerate: () {},
      )));
      await tester.pump();

      expect(find.text('Перегенерировать'), findsOneWidget);
    });

    testWidgets('во время генерации показывает загрузку и блокирует кнопку',
        (tester) async {
      var generateCalls = 0;
      await tester.pumpWidget(wrap(CoverAppearance(
        color: 'blue',
        icon: 'sigma',
        classId: 7,
        generating: true,
        onColorChanged: (_) {},
        onIconChanged: (_) {},
        onGenerate: () => generateCalls++,
      )));
      await tester.pump();

      expect(find.text('Создаём обложку…'), findsWidgets);
      await tester.tap(find.byType(OutlinedButton), warnIfMissed: false);
      await tester.pump();
      expect(generateCalls, 0, reason: 'повторный вызов во время генерации');
    });

    testWidgets('показывает ошибку генерации', (tester) async {
      await tester.pumpWidget(wrap(CoverAppearance(
        color: 'blue',
        icon: 'sigma',
        classId: 7,
        error: 'Не удалось сгенерировать обложку.',
        onColorChanged: (_) {},
        onIconChanged: (_) {},
        onGenerate: () {},
      )));
      await tester.pump();

      expect(find.text('Не удалось сгенерировать обложку.'), findsOneWidget);
    });

    testWidgets('предупреждает, когда обложка собрана без ИИ', (tester) async {
      await tester.pumpWidget(wrap(CoverAppearance(
        color: 'blue',
        icon: 'sigma',
        classId: 7,
        coverUrl: 'https://cdn.test/materials/covers/cover_x.webp',
        coverSource: 'fallback',
        onColorChanged: (_) {},
        onIconChanged: (_) {},
        onGenerate: () {},
      )));
      await tester.pump();

      expect(find.textContaining('без ИИ'), findsOneWidget);
    });

    testWidgets('выбор цвета и иконки уходит наверх', (tester) async {
      String? pickedColor;
      String? pickedIcon;
      await tester.pumpWidget(wrap(CoverAppearance(
        color: 'blue',
        icon: 'sigma',
        classId: null,
        onColorChanged: (v) => pickedColor = v,
        onIconChanged: (v) => pickedIcon = v,
        onGenerate: () {},
      )));
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('purple'));
      await tester.pump();
      expect(pickedColor, 'purple');

      await tester.tap(find.bySemanticsLabel(coverIconLabel('atom', 'RU')));
      await tester.pump();
      expect(pickedIcon, 'atom');
    });
  });
}
