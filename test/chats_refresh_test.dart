import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Список чатов должен обновляться жестом «потянуть вниз».
///
/// Полноценно поднять ChatsScreen в тесте нельзя — он тянет ApiService, WS и
/// AuthProvider. Поэтому проверяем сам контракт RefreshIndicator на такой же
/// структуре (Column с шапкой + Expanded со списком), которая используется в
/// _buildChatList: важно, что жест доходит до списка и вызывает onRefresh.
void main() {
  testWidgets('RefreshIndicator в Expanded вызывает onRefresh по жесту',
      (tester) async {
    var refreshed = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          const SizedBox(height: 60, child: Text('шапка')),
          Expanded(child: RefreshIndicator(
            onRefresh: () async => refreshed = true,
            child: ListView.builder(
              itemCount: 8,
              itemBuilder: (_, i) => SizedBox(height: 64, child: Text('чат $i')),
            ),
          )),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.fling(find.text('чат 0'), const Offset(0, 320), 1200);
    await tester.pumpAndSettle();

    expect(refreshed, isTrue, reason: 'жест не дошёл до onRefresh');
  });

  testWidgets('пустое состояние остаётся прокручиваемым — иначе жест не сработает',
      (tester) async {
    var refreshed = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(child: RefreshIndicator(
            onRefresh: () async => refreshed = true,
            // Так устроен _emptyState в чатах: SingleChildScrollView с
            // AlwaysScrollable — без него потянуть за пустым списком нельзя.
            child: const SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              child: SizedBox(height: 200, child: Text('нет чатов')),
            ),
          )),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.fling(find.text('нет чатов'), const Offset(0, 320), 1200);
    await tester.pumpAndSettle();

    expect(refreshed, isTrue,
        reason: 'на пустом списке тоже должно обновляться');
  });
}
