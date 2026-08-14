import 'package:chatra_app/providers/l10n_provider.dart';
import 'package:chatra_app/services/api_service.dart';
import 'package:chatra_app/theme/app_theme.dart';
import 'package:chatra_app/utils/cover_art.dart';
import 'package:chatra_app/widgets/cover_appearance.dart';
import 'package:chatra_app/widgets/subject_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
          {'id': 'blue', 'hex': '#0A84FF', 'base': '#E3EDFF', 'ink': '#1D4ED8'},
          {'id': 'teal', 'hex': '#00B1C9', 'base': '#D6F1F7', 'ink': '#0E7490'},
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
      expect(o.colors.first.base, const Color(0xFFE3EDFF));
      expect(o.colors.first.ink, const Color(0xFF1D4ED8));
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

    test('битый или неполный цвет не роняет разбор', () {
      final o = CoverOptions.fromJson({
        'colors': [
          {'id': 'broken', 'hex': 'not-a-colour', 'base': '#000000', 'ink': '#000000'},
          {'id': 'no-ink', 'hex': '#0A84FF', 'base': '#E3EDFF'},
          {'id': 'blue', 'hex': '#0A84FF', 'base': '#E3EDFF', 'ink': '#1D4ED8'},
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

    test('у каждой иконки есть группа из объявленного списка', () {
      // Пикер рисуется секциями: символ без группы уехал бы в безымянный
      // блок в конце и выглядел бы потерянным.
      final groups = kFallbackCoverOptions.groups.map((g) => g.id).toSet();
      expect(groups, isNotEmpty);
      for (final icon in kFallbackCoverOptions.icons) {
        expect(groups.contains(icon.group), isTrue,
            reason: 'группа «${icon.group}» символа ${icon.id} не объявлена');
      }
      for (final g in kFallbackCoverOptions.groups) {
        for (final lang in ['RU', 'EN', 'KZ']) {
          expect(kCoverGroupLabels[g.id]?[lang], isNotNull,
              reason: 'нет подписи группы ${g.id} для $lang');
        }
      }
    });

    test('набор покрывает направления школы и вуза', () {
      // Восьми цветов и двенадцати символов на реальный список направлений
      // не хватало — под это расширен и бэкенд (services/cover_art.py).
      expect(kFallbackCoverOptions.colors.length, greaterThanOrEqualTo(12));
      expect(kFallbackCoverOptions.icons.length, greaterThanOrEqualTo(40));
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
        'teal': 0xFF00B1C9, 'indigo': 0xFF6366F1, 'gold': 0xFFEAB308,
        'lime': 0xFF84CC16, 'bronze': 0xFFC2763A, 'slate': 0xFF7C8BA5,
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

  group('SubjectIconOverlay', () {
    testWidgets('рисует белый глиф с тенью', (tester) async {
      CoverOptionsCache.reset(kFallbackCoverOptions);
      addTearDown(CoverOptionsCache.reset);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SubjectIconOverlay(icon: 'sigma', color: 'teal', size: 40)),
      ));
      await tester.pump();

      // Два слоя: размытая тёмная подложка + белый глиф. Композиция под иконкой
      // насыщенная и её яркость заранее неизвестна — иконка в тон давала на ней
      // контраст 1.5-2.0 и пропадала.
      expect(find.byType(SvgPicture), findsNWidgets(2));
      expect(find.byType(ImageFiltered), findsOneWidget);
      expect(coverIconSvg('sigma'), contains('stroke="#ffffff"'));
    });

    testWidgets('легаси-обложку без иконки не перекрывает', (tester) async {
      // cover_icon == null означает картинку, загруженную пользователем по
      // старой системе: рисовать поверх неё чужой символ нельзя.
      for (final icon in [null, '']) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SubjectIconOverlay(icon: icon, size: 40)),
        ));
        await tester.pump();
        expect(find.byType(SvgPicture), findsNothing);
      }
    });

    testWidgets('не перехватывает нажатия по обложке', (tester) async {
      // Оверлей лежит поверх карточки — если бы он ел тапы, класс перестал бы
      // открываться нажатием в центр обложки.
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            onTap: () => taps++,
            child: const Stack(fit: StackFit.expand, children: [
              ColoredBox(color: Color(0xFF1C5FC4)),
              SubjectIconOverlay(icon: 'sigma', size: 40),
            ]),
          ),
        ),
      ));
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.byType(Stack).first));
      await tester.pump();
      expect(taps, 1);
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

    testWidgets('по умолчанию показывает одну полоску символов', (tester) async {
      // Сорок пять плиток разворачивали форму на несколько экранов: название
      // предмета и кнопка сохранения уезжали за пределы видимости.
      await tester.pumpWidget(wrap(CoverAppearance(
        color: 'blue',
        icon: 'sigma',
        classId: null,
        onColorChanged: (_) {},
        onIconChanged: (_) {},
        onGenerate: () {},
      )));
      await tester.pump();

      final shown = kFallbackCoverOptions.icons
          .where((i) => find.bySemanticsLabel(coverIconLabel(i.id, 'RU')).evaluate().isNotEmpty)
          .length;
      expect(shown, 6);
      expect(find.textContaining('Все иконки'), findsOneWidget);
    });

    testWidgets('кнопка раскрывает весь список секциями', (tester) async {
      await tester.pumpWidget(wrap(CoverAppearance(
        color: 'blue',
        icon: 'sigma',
        classId: null,
        onColorChanged: (_) {},
        onIconChanged: (_) {},
        onGenerate: () {},
      )));
      await tester.pump();

      await tester.tap(find.textContaining('Все иконки'));
      await tester.pump();

      expect(find.text('ТОЧНЫЕ НАУКИ'), findsOneWidget);
      expect(find.text('IT И ИНЖЕНЕРИЯ'), findsOneWidget);
      expect(find.text('Свернуть'), findsOneWidget);
      // Символ из дальней секции теперь доступен для выбора.
      expect(find.bySemanticsLabel(coverIconLabel('chef', 'RU')), findsOneWidget);
    });

    testWidgets('символ из дальней секции показан в свёрнутой полоске',
        (tester) async {
      // Выбранный символ обязан быть виден (иначе при редактировании предмета
      // непонятно, что выбрано), но раскрывать ради этого весь список нельзя:
      // на создании класса дефолтный символ тоже лежит вне первой полоски.
      await tester.pumpWidget(wrap(CoverAppearance(
        color: 'blue',
        icon: 'chef',
        classId: null,
        onColorChanged: (_) {},
        onIconChanged: (_) {},
        onGenerate: () {},
      )));
      await tester.pump();

      expect(find.text('Свернуть'), findsNothing);
      expect(find.bySemanticsLabel(coverIconLabel('chef', 'RU')), findsOneWidget);
    });

    testWidgets('на создании класса список символов свёрнут', (tester) async {
      await tester.pumpWidget(wrap(CoverAppearance(
        color: kFallbackCoverOptions.defaultColor,
        icon: kFallbackCoverOptions.defaultIcon,
        classId: null,
        onColorChanged: (_) {},
        onIconChanged: (_) {},
        onGenerate: () {},
      )));
      await tester.pump();

      expect(find.text('Свернуть'), findsNothing);
      // Дефолтный символ виден, хотя в общем списке он далеко не первый.
      expect(find.bySemanticsLabel(coverIconLabel(kFallbackCoverOptions.defaultIcon, 'RU')),
          findsOneWidget);
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
