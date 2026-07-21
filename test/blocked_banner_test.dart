import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chatra_app/providers/l10n_provider.dart';
import 'package:chatra_app/theme/app_theme.dart';
import 'package:chatra_app/widgets/blocked_banner.dart';

/// Панель блокировки стоит внизу вкладки, над которой плавает таб-бар
/// main_shell: раньше она отступала только на safe-area и уезжала под навбар.
void main() {
  Future<void> pump(WidgetTester tester, {double keyboard = 0}) async {
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => L10n(),
        child: MediaQuery(
          data: MediaQueryData(
            padding: const EdgeInsets.only(bottom: 34),   // домашний индикатор
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          // Без Scaffold: он сам поджимает body под клавиатуру и обнуляет
          // viewInsets, а нам нужен «сырой» расчёт отступа.
          child: Material(
            child: Column(children: [
              const Spacer(),
              BlockedBanner(onUnblock: () {}),
            ]),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  double bottomPadding(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.descendant(of: find.byType(BlockedBanner), matching: find.byType(Container)).first,
    );
    return (container.padding as EdgeInsets).bottom;
  }

  testWidgets('панель блокировки не уезжает под таб-бар', (tester) async {
    await pump(tester);
    expect(bottomPadding(tester), greaterThanOrEqualTo(kBottomBarHeight));
  });

  testWidgets('с открытой клавиатурой отступ равен её высоте', (tester) async {
    await pump(tester, keyboard: 300);
    expect(bottomPadding(tester), 308);
  });
}
