import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chatra_app/providers/auth_provider.dart';
import 'package:chatra_app/providers/classes_provider.dart';
import 'package:chatra_app/providers/l10n_provider.dart';
import 'package:chatra_app/screens/calendar/calendar_screen.dart';
import 'package:chatra_app/services/api_service.dart';
import 'package:chatra_app/theme/app_theme.dart';

/// Регрессия на «в календаре дедлайнов текст обрезается».
///
/// Легенда календаря («есть задание / несколько заданий / всё сдано») стояла в
/// одном Row с `maxLines: 1` и `TextOverflow.ellipsis`: по-русски три подписи в
/// строку ещё влезали, а «бірнеше тапсырма» и «several due» — уже нет, и
/// средний пункт обрывался многоточием. То же самое было в карточке задания:
/// время и название предмета делили одну строку.
///
/// Шрифт в тестах — Ahem (каждый глиф в полную ширину кегля), то есть текст
/// здесь ЗАМЕТНО шире реального SF Pro. Если вёрстка проходит тут, на живом
/// шрифте запаса ещё больше.
class _FakeApi extends ApiService {
  _FakeApi({
    this.assignments = const [],
    this.classes = const [],
    this.subs = const [],
  }) : super(baseUrl: 'http://localhost:1/api');

  final List<dynamic> assignments;
  final List<dynamic> classes;
  final List<dynamic> subs;

  @override
  Future<List<dynamic>> getAssignments({int? classId, int page = 1, int pageSize = 50}) async => assignments;

  @override
  Future<List<dynamic>> getClasses() async => classes;

  @override
  Future<List<dynamic>> getAllClasses() async => classes;

  @override
  Future<List<dynamic>> getMySubmissions() async => subs;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  String iso(DateTime d) => d.toUtc().toIso8601String();

  Future<void> pumpCalendar(WidgetTester tester, _FakeApi api,
      {String lang = 'RU', bool dark = false}) async {
    final auth = AuthProvider(api);
    final classes = ClassesProvider(api, auth);
    await classes.load();
    await classes.loadJoined();

    // Между языками дерево сносится полностью: иначе pumpWidget переиспользует
    // элементы, `create:` провайдера не вызывается заново, и второй проход
    // цикла проверял бы всё тот же русский текст.
    await tester.pumpWidget(const SizedBox.shrink());

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: L10n()..setLang(lang)),
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: classes),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: const CalendarScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('легенда календаря читается целиком на всех трёх языках', (tester) async {
    tester.view.physicalSize = const Size(750, 2400); // ширина iPhone SE, высота с запасом
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // Обе темы: в тёмной у экрана другие подложки, и раньше именно там ломался
    // контраст на цветных заливках.
    for (final dark in const [false, true]) {
      for (final lang in const ['RU', 'KZ', 'EN']) {
        final where = '$lang/${dark ? 'dark' : 'light'}';
        await pumpCalendar(tester, _FakeApi(), lang: lang, dark: dark);
        expect(tester.takeException(), isNull, reason: 'переполнение вёрстки: $where');

        final l = L10n()..setLang(lang);
        for (final key in const ['cal_legend_due', 'cal_legend_multiple', 'cal_legend_done']) {
          final label = l.t(key);
          final paragraphs = tester.renderObjectList<RenderParagraph>(find.text(label)).toList();
          expect(paragraphs, isNotEmpty, reason: '«$label» не отрисован: $where');
          for (final p in paragraphs) {
            expect(p.didExceedMaxLines, isFalse, reason: '«$label» обрезан: $where');
          }
        }
      }
    }
  });

  testWidgets('карточка задания: название предмета не обрезается', (tester) async {
    tester.view.physicalSize = const Size(750, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    const className = 'Алгебра и начала';
    const title = 'Контрольная работа';
    final today = DateTime.now();
    final due = DateTime(today.year, today.month, today.day, 23, 59);

    for (final lang in const ['RU', 'KZ', 'EN']) {
      await pumpCalendar(tester, _FakeApi(
        classes: [
          {'id': 1, 'name': className},
        ],
        assignments: [
          {'id': 10, 'class_id': 1, 'title': title, 'deadline': iso(due)},
          // Вторая карточка — уже сданная работа: у неё зелёный акцент и
          // галочка вместо часов, и она тоже должна помещаться целиком.
          {'id': 11, 'class_id': 1, 'title': title, 'deadline': iso(due)},
        ],
        subs: const [
          {'id': 500, 'assignment_id': 11, 'status': 'submitted'},
        ],
      ), lang: lang);

      expect(tester.takeException(), isNull, reason: 'переполнение вёрстки на языке $lang');

      for (final text in const [className, title]) {
        final paragraphs = tester.renderObjectList<RenderParagraph>(find.text(text)).toList();
        expect(paragraphs, isNotEmpty, reason: '«$text» не отрисован на языке $lang');
        for (final p in paragraphs) {
          expect(p.didExceedMaxLines, isFalse, reason: '«$text» обрезан на языке $lang');
        }
      }
    }
  });
}
