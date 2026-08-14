import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatra_app/theme/app_theme.dart';
import 'package:chatra_app/widgets/wrapping_field.dart';

/// WrappingField должен вести себя как однострочное поле по смыслу значения,
/// но переносить длинный текст, а не прятать его начало за левым краем.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(20), child: child)),
      );

  testWidgets('длинный текст переносится, а не уезжает вбок', (t) async {
    final c = TextEditingController();
    await t.pumpWidget(wrap(WrappingField(controller: c, hintText: 'тема')));

    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.minLines, 1);
    expect(field.maxLines, greaterThan(1));
    // Ключевой момент: с multiline-клавиатурой Return вставлял бы перенос
    // строки вместо действия «готово».
    expect(field.keyboardType, TextInputType.text);

    final before = t.getSize(find.byType(TextField)).height;
    await t.enterText(find.byType(TextField),
        'Очень длинная тема лекции, которая заведомо не помещается в одну строку поля ввода');
    await t.pump();
    expect(t.getSize(find.byType(TextField)).height, greaterThan(before));
  });

  testWidgets('переводы строк схлопываются в пробел', (t) async {
    final c = TextEditingController();
    await t.pumpWidget(wrap(WrappingField(controller: c)));

    await t.enterText(find.byType(TextField), 'первая строка\nвторая строка');
    expect(c.text, 'первая строка вторая строка');
  });

  testWidgets('поле растёт не бесконечно', (t) async {
    final c = TextEditingController();
    await t.pumpWidget(wrap(WrappingField(controller: c, maxLines: 2)));

    await t.enterText(find.byType(TextField), 'слово ' * 60);
    await t.pump();
    final grown = t.getSize(find.byType(TextField)).height;

    await t.enterText(find.byType(TextField), 'слово ' * 200);
    await t.pump();
    expect(t.getSize(find.byType(TextField)).height, grown);
  });
}
