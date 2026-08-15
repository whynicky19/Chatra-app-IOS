import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chatra_app/providers/auth_provider.dart';
import 'package:chatra_app/providers/classes_provider.dart';
import 'package:chatra_app/providers/l10n_provider.dart';
import 'package:chatra_app/screens/notifications/notifications_screen.dart';
import 'package:chatra_app/services/api_service.dart';
import 'package:chatra_app/theme/app_theme.dart';
import 'package:chatra_app/utils/notif_feed.dart';
import 'package:chatra_app/widgets/inset_group.dart';

/// Регрессия на «бейдж показывает 1, а список уведомлений пуст».
///
/// Раньше счётчик на колокольчике и сам список считались разным кодом с
/// разными правилами, поэтому счётчик мог показывать уведомление, которого в
/// списке нет — а прочитанным оно отмечается только при показе в списке, и
/// метка не уходила уже никогда. Теперь оба берут [loadNotifFeed], и главная
/// проверка здесь — инвариант «всё, что попало в счётчик, есть в списке».
class _FakeApi extends ApiService {
  _FakeApi({
    this.subs = const [],
    this.assignments = const [],
    this.classes = const [],
    this.states = const [],
  }) : super(baseUrl: 'http://localhost:1/api');

  final List<dynamic> subs;
  final List<dynamic> assignments;
  final List<dynamic> classes;
  final List<dynamic> states;

  @override
  Future<List<dynamic>> getMySubmissions() async => subs;

  @override
  Future<List<dynamic>> getAssignments({int? classId, int page = 1, int pageSize = 50}) async => assignments;

  @override
  Future<List<dynamic>> getClasses() async => classes;

  @override
  Future<List<dynamic>> getNotifStates() async => states;

  /// Что экран отправил на сервер как «прочитано».
  final List<String> marked = [];

  @override
  Future<void> markAllNotifsRead(List<String> keys) async => marked.addAll(keys);

  @override
  Future<void> setNotifState(String notifKey, {bool? read, bool? dismissed}) async {}
}

String iso(DateTime d) => d.toUtc().toIso8601String();

void main() {
  final now = DateTime(2026, 8, 12, 12, 0);

  Map<String, dynamic> cls(int id, String name) => {'id': id, 'name': name};

  Map<String, dynamic> assignment(int id, int classId, {DateTime? createdAt, DateTime? deadline}) => {
        'id': id,
        'class_id': classId,
        'title': 'Задание $id',
        if (createdAt != null) 'created_at': iso(createdAt),
        if (deadline != null) 'deadline': iso(deadline),
      };

  Map<String, dynamic> gradedSub(int id, int assignmentId, {num score = 90, DateTime? gradedAt}) => {
        'id': id,
        'assignment_id': assignmentId,
        'status': 'graded',
        'submitted_at': iso(now.subtract(const Duration(days: 3))),
        'grade': {'score': score, if (gradedAt != null) 'graded_at': iso(gradedAt)},
      };

  test('счётчик равен числу непрочитанных В САМОМ списке (инвариант)', () async {
    final api = _FakeApi(
      classes: [cls(1, 'Матан')],
      assignments: [
        assignment(10, 1, createdAt: now.subtract(const Duration(days: 1))),
        assignment(11, 1, deadline: now.add(const Duration(hours: 5))),
      ],
      subs: [gradedSub(100, 10, gradedAt: now.subtract(const Duration(hours: 2)))],
    );

    final feed = await loadNotifFeed(api, now: now);

    expect(feed.unreadCount, feed.items.where((i) => !i.isRead).length);
    expect(feed.unreadCount, greaterThan(0));
  });

  test('оценка за работу в классе, которого больше нет в списке классов, всё равно видна', () async {
    // Именно этот случай раньше расходился: счётчик считал такую оценку, а
    // список её прятал (класс не находился среди постов первой страницы).
    final api = _FakeApi(
      classes: const [], // студента отчислили / класс скрыт
      assignments: [assignment(10, 7, createdAt: now.subtract(const Duration(days: 1)))],
      subs: [gradedSub(100, 10, gradedAt: now.subtract(const Duration(hours: 1)))],
    );

    final feed = await loadNotifFeed(api, now: now);
    final grades = feed.items.where((i) => i.kind == NotifKind.grade).toList();

    expect(grades, hasLength(1));
    expect(feed.unreadCount, 1);
    // Переход в класс недоступен — там нет прав.
    expect(grades.single.classId, isNull);
  });

  test('прочитанное с сервера не попадает в счётчик, но остаётся в списке', () async {
    final api = _FakeApi(
      classes: [cls(1, 'Матан')],
      assignments: [assignment(10, 1, createdAt: now.subtract(const Duration(days: 1)))],
      subs: [gradedSub(100, 10)],
      states: const [
        {'notif_key': 'grade:100', 'read': true},
        {'notif_key': 'assignment:10', 'read': true},
      ],
    );

    final feed = await loadNotifFeed(api, now: now);

    expect(feed.items, hasLength(2));
    expect(feed.unreadCount, 0);
  });

  test('скрытое (dismissed) уведомление исчезает и из списка, и из счётчика', () async {
    final api = _FakeApi(
      classes: [cls(1, 'Матан')],
      assignments: [assignment(10, 1, createdAt: now.subtract(const Duration(days: 1)))],
      subs: [gradedSub(100, 10)],
      states: const [
        {'notif_key': 'grade:100', 'dismissed': true},
        {'notif_key': 'assignment:10', 'dismissed': true},
      ],
    );

    final feed = await loadNotifFeed(api, now: now);

    expect(feed.items, isEmpty);
    expect(feed.unreadCount, 0);
  });

  test('задание старше недели не считается новым', () async {
    final api = _FakeApi(
      classes: [cls(1, 'Матан')],
      assignments: [assignment(10, 1, createdAt: now.subtract(const Duration(days: 8)))],
    );

    final feed = await loadNotifFeed(api, now: now);

    expect(feed.items, isEmpty);
  });

  test('только что созданное задание попадает в новые даже при часах сервера впереди', () async {
    final api = _FakeApi(
      classes: [cls(1, 'Матан')],
      assignments: [assignment(10, 1, createdAt: now.add(const Duration(minutes: 2)))],
    );

    final feed = await loadNotifFeed(api, now: now);

    expect(feed.items.map((i) => i.kind), contains(NotifKind.newAssignment));
  });

  test('дедлайн: напоминание есть, но счётчик им не поднимается', () async {
    final api = _FakeApi(
      classes: [cls(1, 'Матан')],
      assignments: [assignment(11, 1, deadline: now.add(const Duration(hours: 5)))],
    );

    final feed = await loadNotifFeed(api, now: now);

    expect(feed.items, hasLength(1));
    expect(feed.items.single.kind, NotifKind.deadline);
    expect(feed.unreadCount, 0, reason: 'иначе метка висела бы до самого срока сдачи');
  });

  test('дедлайн по сданной работе не показывается', () async {
    final api = _FakeApi(
      classes: [cls(1, 'Матан')],
      assignments: [assignment(11, 1, deadline: now.add(const Duration(hours: 5)))],
      subs: [
        {'id': 5, 'assignment_id': 11, 'status': 'submitted'},
      ],
    );

    final feed = await loadNotifFeed(api, now: now);

    expect(feed.items, isEmpty);
  });

  test('дальний дедлайн (больше 48 часов) не показывается', () async {
    final api = _FakeApi(
      classes: [cls(1, 'Матан')],
      assignments: [assignment(11, 1, deadline: now.add(const Duration(days: 5)))],
    );

    final feed = await loadNotifFeed(api, now: now);

    expect(feed.items, isEmpty);
  });

  test('задания чужих классов игнорируются', () async {
    final api = _FakeApi(
      classes: [cls(1, 'Матан')],
      assignments: [assignment(20, 99, createdAt: now.subtract(const Duration(hours: 3)))],
    );

    final feed = await loadNotifFeed(api, now: now);

    expect(feed.items, isEmpty);
  });

  test('незачтённая работа (без оценки) уведомления не создаёт', () async {
    final api = _FakeApi(
      classes: [cls(1, 'Матан')],
      assignments: [assignment(10, 1)],
      subs: [
        {'id': 100, 'assignment_id': 10, 'status': 'grading', 'grade': null},
      ],
    );

    final feed = await loadNotifFeed(api, now: now);

    expect(feed.items, isEmpty);
  });

  test('непрочитанные идут первыми, внутри — свежие сверху', () async {
    final api = _FakeApi(
      classes: [cls(1, 'Матан')],
      assignments: [
        assignment(10, 1, createdAt: now.subtract(const Duration(days: 5))),
        assignment(11, 1, createdAt: now.subtract(const Duration(hours: 2))),
      ],
      states: const [
        {'notif_key': 'assignment:11', 'read': true},
      ],
    );

    final feed = await loadNotifFeed(api, now: now);

    expect(feed.items.first.key, 'assignment:10', reason: 'непрочитанное выше прочитанного');
    expect(feed.items.last.key, 'assignment:11');
  });

  test('пустой ответ сервера — пустой фид без исключений', () async {
    final feed = await loadNotifFeed(_FakeApi(), now: now);
    expect(feed.items, isEmpty);
    expect(feed.unreadCount, 0);
  });

  group('экран уведомлений', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<(ClassesProvider, _FakeApi)> pumpScreen(WidgetTester tester, _FakeApi api,
        {String lang = 'RU'}) async {
      final auth = AuthProvider(api);
      final classes = ClassesProvider(api, auth);
      classes.notifBadge.value = 7; // как будто бейдж уже висит с прошлого раза
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => L10n()..setLang(lang)),
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: classes),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const NotificationsScreen()),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      return (classes, api);
    }

    testWidgets('после открытия бейдж обнулён и ключи отправлены как прочитанные', (tester) async {
      final api = _FakeApi(
        classes: [cls(1, 'Матан')],
        assignments: [assignment(10, 1, createdAt: DateTime.now().subtract(const Duration(hours: 2)))],
        subs: [gradedSub(100, 10, gradedAt: DateTime.now().subtract(const Duration(hours: 1)))],
      );
      final (classes, fake) = await pumpScreen(tester, api);

      expect(tester.takeException(), isNull);
      expect(classes.notifBadge.value, 0, reason: 'иначе метка переживёт визит на экран');
      expect(fake.marked, containsAll(<String>['grade:100', 'assignment:10']));
    });

    testWidgets('пустой фид: пустое состояние и нулевой бейдж', (tester) async {
      final (classes, fake) = await pumpScreen(tester, _FakeApi());

      expect(tester.takeException(), isNull);
      expect(classes.notifBadge.value, 0);
      expect(fake.marked, isEmpty);
    });

    testWidgets('карточки одного типа одной высоты при разной длине текста', (tester) async {
      final now = DateTime.now();
      final api = _FakeApi(
        classes: [cls(1, 'Класс с очень длинным названием, которое не влезает в строку')],
        assignments: [
          assignment(10, 1, createdAt: now.subtract(const Duration(minutes: 30))),
          assignment(11, 1, createdAt: now.subtract(const Duration(hours: 4))),
        ],
        subs: [gradedSub(100, 10, gradedAt: now.subtract(const Duration(hours: 1)))],
      );
      await pumpScreen(tester, api);

      final heights = tester
          .widgetList<GroupRow>(find.byType(GroupRow))
          .map((w) => tester.getSize(find.byWidget(w)).height)
          .toSet();
      expect(heights, hasLength(1), reason: 'высота карточек уведомлений разошлась');
      expect(heights.single, greaterThan(70));
    });

    // Регрессия на «название предмета в карточке обрезается». Раньше предмет,
    // название задания и балл делили ОДНУ строку с `maxLines: 1`, и предмет
    // почти всегда уходил под многоточие. Теперь у него своя строка на всю
    // ширину карточки — проверяем это на узком экране и во всех трёх языках,
    // потому что казахский и английский заметно длиннее русского.
    testWidgets('длинные названия предмета и задания не обрезаются (RU/KZ/EN)', (tester) async {
      tester.view.physicalSize = const Size(750, 1334); // iPhone SE, @2x
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      const className = 'Алгебра и начала анализа';
      const title = 'Контрольная работа №5';
      final at = DateTime.now();

      for (final lang in const ['RU', 'KZ', 'EN']) {
        // Карточка «новое задание»: название предмета и название задания
        // целиком, каждое на своей строке.
        await pumpScreen(tester, _FakeApi(
          classes: [cls(1, className)],
          assignments: [
            {'id': 10, 'class_id': 1, 'title': title, 'created_at': iso(at.subtract(const Duration(hours: 2)))},
          ],
        ), lang: lang);

        expect(tester.takeException(), isNull, reason: 'переполнение вёрстки на языке $lang');

        for (final text in const [className, title]) {
          final paragraphs = tester.renderObjectList<RenderParagraph>(find.text(text)).toList();
          // Под старой вёрсткой предмет вообще не был отдельным Text — он
          // склеивался с названием задания в одну строку, и этот поиск не
          // нашёл бы его.
          expect(paragraphs, isNotEmpty, reason: '«$text» не отрисован на языке $lang');
          for (final p in paragraphs) {
            expect(p.didExceedMaxLines, isFalse, reason: '«$text» обрезан на языке $lang');
          }
        }

        // Полный набор типов (оценка с пилюлей балла, дедлайн с остатком,
        // новое задание) — здесь важно именно отсутствие переполнения.
        await pumpScreen(tester, _FakeApi(
          classes: [cls(1, className)],
          assignments: [
            {'id': 10, 'class_id': 1, 'title': title, 'created_at': iso(at.subtract(const Duration(hours: 2)))},
            {'id': 11, 'class_id': 1, 'title': title, 'deadline': iso(at.add(const Duration(hours: 5)))},
          ],
          subs: [gradedSub(100, 10, gradedAt: at.subtract(const Duration(hours: 1)))],
        ), lang: lang);

        expect(tester.takeException(), isNull, reason: 'переполнение вёрстки на языке $lang');
      }
    });
  });
}