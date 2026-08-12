import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chatra_app/providers/auth_provider.dart';
import 'package:chatra_app/providers/l10n_provider.dart';
import 'package:chatra_app/providers/theme_provider.dart';
import 'package:chatra_app/services/api_service.dart';
import 'package:chatra_app/screens/classes/lecture_detail_screen.dart';
import 'package:chatra_app/screens/classes/tabs/class_assignments_tab.dart';
import 'package:chatra_app/screens/classes/tabs/class_posts_tab.dart';
import 'package:chatra_app/screens/classes/widgets/file_card.dart';
import 'package:chatra_app/screens/settings/security_settings_screen.dart';
import 'package:chatra_app/screens/settings/settings_screen.dart';
import 'package:chatra_app/theme/app_theme.dart';
import 'package:chatra_app/widgets/inset_group.dart';

/// Смоук-вёрстка перерисованных экранов: тест падает на любом RenderFlex
/// overflow и любом исключении в build, поэтому сам факт прохождения —
/// проверка того, что новые сгруппированные списки и страницы собираются.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget wrap(Widget child, {bool dark = false}) => ChangeNotifierProvider(
        create: (_) => L10n(),
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(body: child),
        ),
      );

  /// Экран настроек тянет профиль и тему из провайдеров, поэтому ему нужен
  /// более полный граф (ApiService создаётся, но по сети не ходит: экран
  /// обращается к нему только по нажатию «Сохранить»).
  Widget wrapSettings({bool dark = false}) {
    final api = ApiService(baseUrl: 'http://localhost:8000/api');
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => L10n()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider(create: (_) => AuthProvider(api)),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: const SettingsScreen(),
      ),
    );
  }

  testWidgets('подэкран настроек (шапка + группы) строится', (tester) async {
    await tester.pumpWidget(wrap(const SecuritySettingsScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('экран настроек (группы, переключатель, разделы) строится', (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(wrapSettings(dark: dark));
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull);
    }
  });

  List<dynamic> posts(int n) => [
        for (var i = 1; i <= n; i++)
          {
            'id': i,
            'title': '[LECTURE][$i] Лекция $i: очень длинное название лекции для проверки переноса',
            'body': jsonEncode({
              'content': 'Текст лекции ' * 20,
              'files': ['https://example.com/uploads/file$i.pdf#doc$i.pdf'],
            }),
            'created_at': '2026-08-0${(i % 9) + 1}T10:00:00',
          },
      ];

  testWidgets('список лекций строится в обеих темах', (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(wrap(
        ClassPostsTab(
          posts: posts(4),
          isTeacher: true,
          onShowPost: (_, __) {},
          onEditPost: (_) {},
          onDeletePost: (_) {},
          onRefresh: () async {},
        ),
        dark: dark,
      ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('пустой список лекций строится', (tester) async {
    await tester.pumpWidget(wrap(
      ClassPostsTab(
        posts: const [],
        isTeacher: false,
        onShowPost: (_, __) {},
        onEditPost: (_) {},
        onDeletePost: (_) {},
        onRefresh: () async {},
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  List<dynamic> assignments(int n) => [
        for (var i = 1; i <= n; i++)
          {
            'id': i,
            'title': 'Лабораторная работа $i с длинным названием на две строки',
            'description': 'Описание задания. ' * 10,
            'max_score': 100,
            'deadline': '2026-08-2${i % 9}T23:59:00',
          },
      ];

  testWidgets('список заданий студента (рейтинг + дедлайн + строки) строится', (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(wrap(
        ClassAssignmentsTab(
          assignments: assignments(3),
          mySubs: const [
            {'assignment_id': 1, 'status': 'graded', 'grade': {'score': 87, 'graded_by': 'ai'}},
            {'assignment_id': 2, 'status': 'submitted'},
          ],
          rating: const {'avg_score': 87.4, 'avg_percent': 91.2},
          isTeacher: false,
          classId: 1,
          isLoading: false,
          onRefresh: () async {},
          onEditAssignment: (_) {},
          onOpenFile: (_, __) {},
        ),
        dark: dark,
      ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('список заданий учителя и пустое состояние строятся', (tester) async {
    for (final items in [assignments(2), <dynamic>[]]) {
      await tester.pumpWidget(wrap(
        ClassAssignmentsTab(
          assignments: items,
          mySubs: const [],
          rating: const {},
          isTeacher: true,
          classId: 1,
          isLoading: false,
          onRefresh: () async {},
          onEditAssignment: (_) {},
          onOpenFile: (_, __) {},
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('страница лекции с текстом и вложениями строится', (tester) async {
    await tester.pumpWidget(wrap(
      LectureDetailScreen(
        title: 'Лекция 3: интегралы и производные в приложениях',
        dateLabel: '03.08.2026',
        content: 'Содержимое лекции. ' * 30,
        files: const [
          'https://example.com/uploads/a.pdf#Конспект.pdf',
          'https://example.com/uploads/b.png#Схема.png',
        ],
        onOpenFile: (_, __, ___) {},
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('сгруппированный список файлов строится', (tester) async {
    await tester.pumpWidget(wrap(
      Padding(
        padding: const EdgeInsets.all(16),
        child: FileList(
          files: const [
            FileEntry(name: 'Задание.docx', url: 'https://e.com/a.docx', sizeLabel: '120 KB'),
            FileEntry(name: 'Очень длинное имя файла без пробелов.pdf', url: 'https://e.com/b.pdf'),
          ],
          onOpen: (_) {},
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  // ── Одинаковая высота карточек и отсутствие лишних значков ──────────
  List<dynamic> mixedPosts() => [
        // Короткое название без описания и вложений.
        {
          'id': 1,
          'title': '[LECTURE][1] Введение',
          'body': jsonEncode({'content': ''}),
          'created_at': '2026-08-01T10:00:00',
        },
        // Длинное название и длинное описание + вложения.
        {
          'id': 2,
          'title': '[LECTURE][2] Очень длинное название лекции, которое точно не влезает в одну строку экрана',
          'body': jsonEncode({
            'content': 'Очень длинное описание лекции. ' * 30,
            'files': ['https://e.com/a.pdf#a.pdf', 'https://e.com/b.pdf#b.pdf'],
          }),
          'created_at': '2026-08-02T10:00:00',
        },
      ];

  Set<double> cardHeights(WidgetTester tester) => tester
      .widgetList<GroupRow>(find.byType(GroupRow))
      .map((w) => tester.getSize(find.byWidget(w)).height)
      .toSet();

  testWidgets('карточки лекций одной высоты при разной длине текста', (tester) async {
    await tester.pumpWidget(wrap(
      ClassPostsTab(
        posts: mixedPosts(),
        isTeacher: true,
        onShowPost: (_, __) {},
        onEditPost: (_) {},
        onDeletePost: (_) {},
        onRefresh: () async {},
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    expect(cardHeights(tester), hasLength(1), reason: 'высота карточек разошлась');
    // Шеврона «открыть» в списке быть не должно, троеточие — вертикальное.
    expect(find.byIcon(CupertinoIcons.chevron_right), findsNothing);
    expect(find.byIcon(CupertinoIcons.ellipsis_vertical), findsWidgets);
  });

  testWidgets('карточки заданий одной высоты при разном описании и статусах', (tester) async {
    final items = [
      {'id': 1, 'title': 'Короткое', 'max_score': 100},
      {
        'id': 2,
        'title': 'Очень длинное название задания, которое точно не влезает в одну строку',
        'description': 'Описание задания. ' * 40,
        'max_score': 100,
        'deadline': '2026-08-20T23:59:00',
      },
    ];
    await tester.pumpWidget(wrap(
      ClassAssignmentsTab(
        assignments: items,
        mySubs: const [
          {'assignment_id': 2, 'status': 'graded', 'grade': {'score': 87, 'graded_by': 'ai'}},
        ],
        rating: const {},
        isTeacher: true,
        classId: 1,
        isLoading: false,
        onRefresh: () async {},
        onEditAssignment: (_) {},
        onOpenFile: (_, __) {},
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    expect(cardHeights(tester), hasLength(1), reason: 'высота карточек разошлась');
    expect(find.byIcon(CupertinoIcons.chevron_right), findsNothing);
    expect(find.byIcon(CupertinoIcons.ellipsis_vertical), findsWidgets);
  });

  testWidgets('карточка лекции и карточка задания одной высоты между собой', (tester) async {
    await tester.pumpWidget(wrap(
      ClassPostsTab(
        posts: mixedPosts(),
        isTeacher: true,
        onShowPost: (_, __) {},
        onEditPost: (_) {},
        onDeletePost: (_) {},
        onRefresh: () async {},
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    final lectureHeight = cardHeights(tester).single;

    await tester.pumpWidget(wrap(
      ClassAssignmentsTab(
        assignments: const [
          {'id': 1, 'title': 'Короткое', 'max_score': 100},
          {'id': 2, 'title': 'Другое задание', 'max_score': 100, 'deadline': '2026-08-20T23:59:00'},
        ],
        mySubs: const [],
        rating: const {},
        isTeacher: true,
        classId: 1,
        isLoading: false,
        onRefresh: () async {},
        onEditAssignment: (_) {},
        onOpenFile: (_, __) {},
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    final assignmentHeight = cardHeights(tester).single;

    expect(assignmentHeight, lectureHeight,
        reason: 'списки лекций и заданий должны иметь один ритм строк');
  });
}
