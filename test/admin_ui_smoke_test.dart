import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chatra_app/providers/auth_provider.dart';
import 'package:chatra_app/providers/l10n_provider.dart';
import 'package:chatra_app/screens/admin/admin_screen.dart';
import 'package:chatra_app/services/api_service.dart';
import 'package:chatra_app/theme/app_theme.dart';
import 'package:chatra_app/widgets/inset_group.dart';

/// Смоук-вёрстка админ-панели: тест падает на любом RenderFlex overflow и любом
/// исключении в build, поэтому сам факт прохождения — проверка того, что все
/// четыре вкладки и листы собираются в обеих темах.
class _FakeAdminApi extends ApiService {
  _FakeAdminApi({this.users = const [], this.classes = const [], this.reports = const []})
      : super(baseUrl: 'http://localhost:1/api');

  final List<dynamic> users;
  final List<dynamic> classes;
  final List<dynamic> reports;

  @override
  Future<List<dynamic>> adminUsers() async => users;

  @override
  Future<List<dynamic>> adminReports({bool onlyOpen = true}) async => reports;

  @override
  Future<List<dynamic>> getAllClasses() async => classes;

  @override
  Future<List<dynamic>> getClassMembers(int classId, {int? cohortId, bool isAdmin = false}) async => users;

  @override
  Future<List<dynamic>> adminAiSummary() async => [
        {'class_id': 1, 'total_tokens': 128400, 'request_count': 42},
      ];

  @override
  Future<Map<String, dynamic>> adminAiUsagePage({int? classId, int page = 1, int pageSize = 50}) async => {
        'items': [
          {
            'user_id': 1,
            'class_id': 1,
            'endpoint': '/ai/chat',
            'prompt_tokens': 900,
            'completion_tokens': 320,
            'total_tokens': 1220,
            'created_at': '2026-08-10T12:00:00',
          },
          {
            'user_id': 2,
            'class_id': 1,
            'endpoint': '/ai/grade',
            'prompt_tokens': 1500,
            'completion_tokens': 400,
            'total_tokens': 1900,
            'created_at': '2026-08-11T09:30:00',
          },
        ],
        'total': 2,
      };
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final users = <dynamic>[
    {'id': 1, 'full_name': 'Айгерим Нурлановна', 'email': 'aigerim@example.com', 'role': 'teacher', 'is_active': true},
    {'id': 2, 'full_name': 'Пользователь с очень длинным именем, которое не влезает', 'email': 'very.long.email.address@example.com', 'role': 'student', 'is_active': false},
    {'id': 3, 'full_name': 'Админ Системы', 'email': 'admin@example.com', 'role': 'admin', 'is_active': true},
  ];

  final classes = <dynamic>[
    {'id': 1, 'name': 'Математический анализ', 'description': 'Описание курса ' * 10, 'teacher': 'Айгерим Н.', 'created_by': 1},
    {'id': 2, 'name': 'Физика', 'created_by': 3},
  ];

  final reports = <dynamic>[
    {
      'id': 7,
      'target_type': 'post',
      'target_id': 12,
      'reason': 'spam',
      'comment': 'Реклама в лекции ' * 5,
      'reporter_name': 'Студент',
      'class_name': 'Математический анализ',
      'target_title': 'Лекция 3',
      'created_at': '2026-08-11T09:30:00',
    },
  ];

  Future<_FakeAdminApi> pumpAdmin(WidgetTester tester, {bool dark = false}) async {
    final api = _FakeAdminApi(users: users, classes: classes, reports: reports);
    final auth = AuthProvider(api);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => L10n()),
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider.value(value: auth),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: const AdminScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 900));
    return api;
  }

  testWidgets('админ-панель строится в обеих темах', (tester) async {
    for (final dark in [false, true]) {
      await pumpAdmin(tester, dark: dark);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('карточки пользователей одной высоты и без «аватарок»', (tester) async {
    await pumpAdmin(tester);

    final heights = tester
        .widgetList<GroupRow>(find.byType(GroupRow))
        .map((w) => tester.getSize(find.byWidget(w)).height)
        .toSet();
    expect(heights, hasLength(1), reason: 'высота карточек пользователей разошлась');

    // Кружков с первой буквой имени в списке быть не должно.
    expect(find.text('А'), findsNothing);
    expect(find.text('П'), findsNothing);
    // Роль подписана на языке интерфейса, а не сырым ключом с бэкенда.
    expect(find.text('admin'), findsNothing);
    expect(find.text('teacher'), findsNothing);
  });

  testWidgets('вкладки AI, классов и жалоб открываются', (tester) async {
    await pumpAdmin(tester);

    for (final tab in [1, 2, 3]) {
      await tester.tap(find.byType(Tab).at(tab));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull, reason: 'вкладка $tab не собралась');
    }
  });

  testWidgets('лист действий с пользователем открывается', (tester) async {
    await pumpAdmin(tester);

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis_vertical).first);
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });
}
