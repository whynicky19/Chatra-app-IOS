import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chatra_app/providers/l10n_provider.dart';
import 'package:chatra_app/screens/admin/ai_dashboard_tab.dart';
import 'package:chatra_app/services/api_service.dart';
import 'package:chatra_app/theme/app_theme.dart';

/// Регрессия на «карточка динамики пустая».
///
/// Реальные данные перекошены: один пиковый день на 300k токенов делал все
/// остальные столбики долей пикселя, а стек из двух видов расхода с зазорами
/// не помещался в такую колонку и ронял RenderFlex overflow. Тест проверяет
/// обе границы: график строится без переполнения, а день с расходом виден.
class _Api extends ApiService {
  _Api() : super(baseUrl: 'http://localhost:1/api');

  @override
  Future<Map<String, dynamic>> adminAiDashboard({int days = 30}) async => {
        'days': days,
        'totals': {'total_tokens': 609396, 'request_count': 265, 'avg_tokens': 2300, 'user_count': 9, 'class_count': 4},
        'totals_all_time': {'total_tokens': 786901, 'request_count': 411},
        'by_endpoint': [
          {'endpoint': 'chat', 'label': 'Чат с ИИ', 'group': 'chat', 'total_tokens': 311030, 'request_count': 171},
          {'endpoint': 'ai-grade', 'label': 'Проверка работ', 'group': 'grade', 'total_tokens': 235043, 'request_count': 64},
        ],
        'by_group': [
          {'group': 'chat', 'label': 'Чат с ИИ', 'endpoints': ['chat'], 'total_tokens': 359779, 'request_count': 172},
          {'group': 'grade', 'label': 'Проверка работ', 'endpoints': ['ai-grade'], 'total_tokens': 240354, 'request_count': 65},
        ],
        'by_class': const [],
        'top_users': const [],
        'by_day': [
          for (var i = 0; i < 30; i++)
            {
              'date': '2026-07-${(i + 1).toString().padLeft(2, '0')}',
              'total_tokens': i == 20 ? 305573 : (i % 5 == 0 ? 0 : 4000 + i * 300),
              'request_count': i,
              'kinds': i == 20
                  ? {'chat': 150000, 'ai-grade': 155573}
                  : (i % 5 == 0 ? <String, dynamic>{} : {'chat': 3000 + i * 200, 'ai-grade': 1000 + i * 100}),
            },
        ],
        'limits': {'daily_token_budget': 2000000, 'tokens_used_today': 7905, 'daily_message_limit': 50},
      };

  @override
  Future<Map<String, dynamic>> adminAiUsagePage({
    int? classId, String? endpoint, int? userId, int? days, int page = 1, int pageSize = 50,
  }) async => {'items': const [], 'total': 0};
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('график динамики строится и показывает дни с расходом', (tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => L10n()),
        Provider<ApiService>.value(value: _Api()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const Scaffold(body: AiDashboardTab())),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final scrollable = find.byType(Scrollable).last;
    Finder chart = find.byKey(const ValueKey('daily-chart'));
    for (var i = 0; i < 6 && chart.evaluate().isEmpty; i++) {
      await tester.drag(scrollable, const Offset(0, -320));
      await tester.pump(const Duration(milliseconds: 100));
      chart = find.byKey(const ValueKey('daily-chart'));
    }
    expect(chart, findsOneWidget, reason: 'карточка динамики не отрисовалась');
    expect(tester.takeException(), isNull, reason: 'график переполнил колонку');

    // Столбики: пиковый день во всю высоту, дни с обычным расходом — не тоньше
    // 5px (иначе карточка выглядит пустой).
    final columns = find.descendant(of: chart, matching: find.byType(ClipRRect));
    final heights = columns
        .evaluate()
        .map((e) => tester.getSize(find.byElementPredicate((x) => x == e)).height)
        .where((h) => h <= 120)
        .toList();
    expect(heights, isNotEmpty, reason: 'столбики графика не построились');
    // На логарифмической шкале пиковый день — самый высокий, но не «в потолок»:
    // важнее, что обычные дни читаются, а не лежат в пол рядом с ним.
    final tallest = heights.reduce((a, b) => a > b ? a : b);
    expect(tallest, greaterThan(70), reason: 'пиковый день слишком низкий: $heights');
    final smallest = heights.reduce((a, b) => a < b ? a : b);
    expect(smallest, greaterThan(15),
        reason: 'самый тихий день схлопнулся в волосок ($smallest px): $heights');
    final avg = heights.reduce((a, b) => a + b) / heights.length;
    expect(avg, greaterThan(25),
        reason: 'дни в среднем в пару пикселей (${avg.toStringAsFixed(1)}px): $heights');
    // ignore: avoid_print
    print('ВЫСОТЫ СТОЛБИКОВ: ${heights.map((h) => h.round()).toList()}');
  });
}
