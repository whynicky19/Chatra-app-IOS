import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chatra_app/providers/l10n_provider.dart';
import 'package:chatra_app/screens/classes/lecture_detail_screen.dart';
import 'package:chatra_app/screens/classes/tabs/class_assignments_tab.dart';
import 'package:chatra_app/screens/classes/tabs/class_posts_tab.dart';
import 'package:chatra_app/screens/classes/widgets/file_card.dart';
import 'package:chatra_app/theme/app_theme.dart';

/// Смоук-вёрстка перерисованных экранов: тест падает на любом RenderFlex
/// overflow и любом исключении в build, поэтому сам факт прохождения —
/// проверка того, что новые сгруппированные списки и страницы собираются.
void main() {
  Widget wrap(Widget child, {bool dark = false}) => ChangeNotifierProvider(
        create: (_) => L10n(),
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(body: child),
        ),
      );

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
}
