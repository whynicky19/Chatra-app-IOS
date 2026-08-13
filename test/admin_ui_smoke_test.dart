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
/// четыре вкладки и карточки собираются в обеих темах.
class _FakeAdminApi extends ApiService {
  _FakeAdminApi({this.users = const [], this.classes = const [], this.reports = const []})
      : super(baseUrl: 'http://localhost:1/api');

  final List<dynamic> users;
  final List<dynamic> classes;
  final List<dynamic> reports;

  @override
  Future<List<dynamic>> adminUsers() async => users;

  @override
  Future<List<dynamic>> adminUsersOverview() async => users;

  @override
  Future<List<dynamic>> adminReports({bool onlyOpen = true}) async => reports;

  @override
  Future<List<dynamic>> getAllClasses() async => classes;

  @override
  Future<List<dynamic>> getClassMembers(int classId, {int? cohortId, bool isAdmin = false}) async => users;

  @override
  Future<List<dynamic>> getRejoinableStudents(int classId) async => const [];

  @override
  Future<List<dynamic>> adminAiSummary() async => [
        {'class_id': 1, 'total_tokens': 128400, 'request_count': 42},
      ];

  @override
  Future<Map<String, dynamic>> adminUserDetail(int userId) async => {
        'id': userId,
        'email': 'aigerim@example.com',
        'full_name': 'Айгерим Нурлановна',
        'role': 'teacher',
        'is_active': true,
        'is_verified': true,
        'ai_unlimited': false,
        'created_at': '2026-06-01T10:00:00',
        'last_active': '2026-08-13T18:40:00',
        'ai': {
          'total_tokens': 128400,
          'prompt_tokens': 100000,
          'completion_tokens': 28400,
          'request_count': 42,
          'avg_tokens': 3057,
          'messages_today': 3,
          'message_limit': 50,
          'general_tokens': 1200,
          'general_requests': 4,
          'first_used': '2026-07-01T10:00:00',
          'last_used': '2026-08-13T18:40:00',
          'by_endpoint': [
            {'endpoint': 'chat', 'label': 'Чат с ИИ', 'group': 'chat', 'group_label': 'Чат с ИИ',
             'total_tokens': 100000, 'prompt_tokens': 80000, 'completion_tokens': 20000, 'request_count': 30},
            {'endpoint': 'cover_image', 'label': 'Обложка предмета', 'group': 'cover', 'group_label': 'Обложки предметов',
             'total_tokens': 28400, 'prompt_tokens': 20000, 'completion_tokens': 8400, 'request_count': 12},
          ],
        },
        'classes': [
          {'id': 1, 'name': 'Математический анализ', 'role': 'creator', 'cover_color': 'blue',
           'cover_icon': 'sigma', 'cover_thumbnail': null, 'total_tokens': 128400, 'request_count': 42},
        ],
        'activity': {'posts': 5, 'submissions': 3, 'graded': 3, 'avg_score': 82.5, 'assignments_created': 4},
      };

  @override
  Future<Map<String, dynamic>> adminClassDetail(int classId) async => {
        'id': classId,
        'name': 'Математический анализ',
        'description': 'Описание курса',
        'invite_code': 'ABC123',
        'created_at': '2026-06-01T10:00:00',
        'cover_color': 'blue',
        'cover_icon': 'sigma',
        'creator': {'id': 1, 'full_name': 'Айгерим Нурлановна', 'email': 'aigerim@example.com', 'role': 'teacher'},
        'member_count': 2,
        'members': [
          {'id': 1, 'full_name': 'Айгерим Нурлановна', 'email': 'aigerim@example.com', 'role': 'teacher',
           'is_active': true, 'total_tokens': 90000, 'request_count': 30, 'last_active': '2026-08-13T18:40:00'},
          {'id': 2, 'full_name': 'Студент', 'email': 'student@example.com', 'role': 'student',
           'is_active': false, 'total_tokens': 38400, 'request_count': 12, 'last_active': null},
        ],
        'cohorts': [
          {'id': 3, 'academic_year': '2026/2027', 'status': 'active', 'student_count': 2, 'start_date': '2026-09-01'},
        ],
        'content': {'assignments': 4, 'assignments_active': 3, 'lectures': 6,
                    'submissions': 12, 'graded': 10, 'avg_score': 78.4},
        'ai': {
          'total_tokens': 128400, 'prompt_tokens': 100000, 'completion_tokens': 28400,
          'request_count': 42, 'avg_tokens': 3057,
          'first_used': '2026-07-01T10:00:00', 'last_used': '2026-08-13T18:40:00',
          'by_endpoint': [
            {'endpoint': 'chat', 'label': 'Чат с ИИ', 'group': 'chat', 'group_label': 'Чат с ИИ',
             'total_tokens': 100000, 'prompt_tokens': 80000, 'completion_tokens': 20000, 'request_count': 30},
            {'endpoint': 'ai-grade', 'label': 'Проверка работ', 'group': 'grade', 'group_label': 'Проверка работ',
             'total_tokens': 28400, 'prompt_tokens': 20000, 'completion_tokens': 8400, 'request_count': 12},
          ],
        },
      };

  @override
  Future<Map<String, dynamic>> adminAiDashboard({int days = 30}) async => {
        'days': days,
        'since': '2026-07-15T00:00:00',
        'generated_at': '2026-08-14T10:00:00',
        'totals': {'total_tokens': 128400, 'prompt_tokens': 100000, 'completion_tokens': 28400,
                   'request_count': 42, 'user_count': 3, 'class_count': 2, 'avg_tokens': 3057},
        'totals_all_time': {'total_tokens': 250000, 'prompt_tokens': 200000, 'completion_tokens': 50000,
                            'request_count': 90, 'user_count': 3, 'class_count': 2, 'avg_tokens': 2777},
        'by_endpoint': [
          {'endpoint': 'chat', 'label': 'Чат с ИИ', 'group': 'chat', 'group_label': 'Чат с ИИ',
           'total_tokens': 100000, 'prompt_tokens': 80000, 'completion_tokens': 20000, 'request_count': 30,
           'user_count': 3, 'avg_tokens': 3333, 'last_used': '2026-08-13T18:40:00'},
          {'endpoint': 'ai-grade', 'label': 'Проверка работ', 'group': 'grade', 'group_label': 'Проверка работ',
           'total_tokens': 28400, 'prompt_tokens': 20000, 'completion_tokens': 8400, 'request_count': 12,
           'user_count': 2, 'avg_tokens': 2366, 'last_used': '2026-08-12T18:40:00'},
        ],
        'by_group': [
          {'group': 'chat', 'label': 'Чат с ИИ', 'endpoints': ['chat', 'chat_vision'],
           'total_tokens': 100000, 'prompt_tokens': 80000, 'completion_tokens': 20000, 'request_count': 30},
          {'group': 'grade', 'label': 'Проверка работ', 'endpoints': ['ai-grade'],
           'total_tokens': 28400, 'prompt_tokens': 20000, 'completion_tokens': 8400, 'request_count': 12},
        ],
        'by_class': [
          {'class_id': 1, 'class_name': 'Математический анализ', 'kinds': {'chat': 100000, 'ai-grade': 28400},
           'total_tokens': 128400, 'prompt_tokens': 100000, 'completion_tokens': 28400,
           'request_count': 42, 'user_count': 3, 'avg_tokens': 3057, 'last_used': '2026-08-13T18:40:00'},
          {'class_id': null, 'class_name': null, 'kinds': {'chat': 1200},
           'total_tokens': 1200, 'prompt_tokens': 1000, 'completion_tokens': 200,
           'request_count': 4, 'user_count': 1, 'avg_tokens': 300, 'last_used': '2026-08-10T18:40:00'},
        ],
        'by_day': [
          for (var i = 0; i < 30; i++)
            {'date': '2026-07-${(15 + i % 16).toString().padLeft(2, '0')}',
             'total_tokens': i * 400, 'prompt_tokens': i * 300, 'completion_tokens': i * 100,
             'request_count': i, 'kinds': {'chat': i * 300, 'ai-grade': i * 100}},
        ],
        'top_users': [
          {'user_id': 1, 'name': 'Айгерим Нурлановна', 'email': 'aigerim@example.com', 'role': 'teacher',
           'ai_unlimited': false, 'kinds': {'chat': 90000}, 'total_tokens': 90000, 'prompt_tokens': 70000,
           'completion_tokens': 20000, 'request_count': 30, 'avg_tokens': 3000, 'last_used': '2026-08-13T18:40:00'},
        ],
        'labels': {'chat': 'Чат с ИИ'},
        'limits': {'daily_token_budget': 2000000, 'tokens_used_today': 7905, 'daily_message_limit': 50},
      };

  @override
  Future<Map<String, dynamic>> adminAiUsagePage({
    int? classId,
    String? endpoint,
    int? userId,
    int? days,
    int page = 1,
    int pageSize = 50,
  }) async => {
        'items': [
          {
            'id': 1,
            'user_id': 1,
            'user_name': 'Айгерим Нурлановна',
            'class_id': 1,
            'class_name': 'Математический анализ',
            'endpoint': 'chat',
            'label': 'Чат с ИИ',
            'prompt_tokens': 900,
            'completion_tokens': 320,
            'total_tokens': 1220,
            'created_at': '2026-08-10T12:00:00',
          },
          {
            'id': 2,
            'user_id': 2,
            'user_name': 'Студент',
            'class_id': null,
            'class_name': null,
            'endpoint': 'ai-grade',
            'label': 'Проверка работ',
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
    {'id': 1, 'full_name': 'Айгерим Нурлановна', 'email': 'aigerim@example.com', 'role': 'teacher',
     'is_active': true, 'is_verified': true, 'ai_unlimited': false,
     'total_tokens': 128400, 'request_count': 42, 'class_count': 2, 'last_active': '2026-08-13T18:40:00'},
    {'id': 2, 'full_name': 'Пользователь с очень длинным именем, которое не влезает',
     'email': 'very.long.email.address@example.com', 'role': 'student', 'is_active': false,
     'is_verified': false, 'ai_unlimited': true,
     'total_tokens': 900, 'request_count': 3, 'class_count': 1, 'last_active': null},
    {'id': 3, 'full_name': 'Админ Системы', 'email': 'admin@example.com', 'role': 'admin',
     'is_active': true, 'is_verified': true, 'ai_unlimited': false,
     'total_tokens': 0, 'request_count': 0, 'class_count': 0, 'last_active': null},
  ];

  final classes = <dynamic>[
    {'id': 1, 'name': 'Математический анализ', 'description': 'Описание курса ' * 10,
     'teacher': 'Айгерим Н.', 'created_by': 1, 'member_count': 24},
    {'id': 2, 'name': 'Физика', 'created_by': 3, 'member_count': 0},
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

  testWidgets('строки пользователей одной высоты и с локализованной ролью', (tester) async {
    await pumpAdmin(tester);

    final heights = tester
        .widgetList<GroupRow>(find.byType(GroupRow))
        .map((w) => tester.getSize(find.byWidget(w)).height)
        .toSet();
    expect(heights, hasLength(1), reason: 'высота карточек пользователей разошлась');

    // Роль подписана на языке интерфейса, а не сырым ключом с бэкенда.
    expect(find.text('admin'), findsNothing);
    expect(find.text('teacher'), findsNothing);
  });

  testWidgets('вкладки AI, предметов и жалоб открываются', (tester) async {
    await pumpAdmin(tester);

    for (final tab in [1, 2, 3]) {
      await tester.tap(find.byType(Tab).at(tab));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull, reason: 'вкладка $tab не собралась');
    }
  });

  testWidgets('карточка пользователя открывается по нажатию на строку', (tester) async {
    await pumpAdmin(tester);

    await tester.tap(find.text('Айгерим Нурлановна').first);
    // Лист — отдельный маршрут, а содержимое догружается: анимация открытия и
    // ответ API требуют разных кадров, одним pump их не пройти.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    // Внутри карточки есть блок расхода ИИ и предметы человека.
    expect(find.text('РАСХОД ИИ'), findsOneWidget);
    expect(find.text('ПРЕДМЕТЫ'), findsOneWidget);

    // Управление аккаунтом лежит ниже: список ленивый, поэтому доскроллим.
    await tester.scrollUntilVisible(
      find.text('УПРАВЛЕНИЕ'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('УПРАВЛЕНИЕ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('дашборд ИИ прокручивается целиком без overflow', (tester) async {
    await pumpAdmin(tester);

    await tester.tap(find.byType(Tab).at(1));
    // Вкладка монтируется лениво и сама грузит дашборд: анимация переключения
    // и ответы API приходят в разных кадрах.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('ТОКЕНЫ ЗА ПЕРИОД'), findsOneWidget);

    // Прокручиваем до журнала: по пути строятся карточки видов расхода,
    // столбики по дням и рейтинги — любой overflow уронит тест.
    final scrollable = find.byType(Scrollable).last;
    var sawKinds = false;
    for (var i = 0; i < 10; i++) {
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull, reason: 'экран сломался на прокрутке');
      if (find.text('КУДА УХОДЯТ ТОКЕНЫ').evaluate().isNotEmpty) sawKinds = true;
    }
    expect(sawKinds, isTrue, reason: 'разбивка по видам расхода не отрисовалась');
  });

  testWidgets('карточка предмета открывается со вкладки «Предметы»', (tester) async {
    await pumpAdmin(tester);

    await tester.tap(find.byType(Tab).at(2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Математический анализ').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('СОДЕРЖИМОЕ'), findsOneWidget);
  });
}
