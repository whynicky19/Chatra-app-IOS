import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регрессия на пропущенные ключи локализации.
///
/// `L10n.t()` при промахе возвращает сам ключ, поэтому опечатка или забытый
/// перевод не падают — они просто показываются пользователю сырой строкой.
/// Так в админ-панели оказались кнопки с подписями «block», «unblock» и
/// «blocked_short»: код их использовал, а в словаре их не было ни в одном
/// из трёх языков.
///
/// Тест читает исходники, собирает все `.t('...')` и сверяет со словарём.
void main() {
  final providerFile = File('lib/providers/l10n_provider.dart');
  final source = providerFile.readAsStringSync();

  /// Ключи, объявленные внутри блока конкретного языка.
  Set<String> keysFor(String lang) {
    final blocks = source.split(RegExp(r"\n    '(RU|KZ|EN)': \{"));
    final marker = RegExp(r"\n    '(RU|KZ|EN)': \{");
    final langs = marker.allMatches(source).map((m) => m.group(1)!).toList();
    final idx = langs.indexOf(lang);
    expect(idx, isNonNegative, reason: 'блок языка $lang не найден');
    return RegExp(r"^      '([a-z0-9_]+)':", multiLine: true)
        .allMatches(blocks[idx + 1])
        .map((m) => m.group(1)!)
        .toSet();
  }

  final ru = keysFor('RU');
  final kz = keysFor('KZ');
  final en = keysFor('EN');

  test('словари RU/KZ/EN содержат одинаковый набор ключей', () {
    expect(ru.difference(kz), isEmpty, reason: 'нет в KZ');
    expect(kz.difference(ru), isEmpty, reason: 'лишние в KZ');
    expect(ru.difference(en), isEmpty, reason: 'нет в EN');
    expect(en.difference(ru), isEmpty, reason: 'лишние в EN');
  });

  test('каждый используемый в коде ключ определён', () {
    final used = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains('l10n_provider')) continue;
      used.addAll(
        RegExp(r"\.t\('([a-z0-9_]+)'\)")
            .allMatches(entity.readAsStringSync())
            .map((m) => m.group(1)!),
      );
    }

    expect(used, isNotEmpty, reason: 'парсер ключей сломался');
    final undefined = used.difference(ru).toList()..sort();
    expect(undefined, isEmpty,
        reason: 'ключи используются, но не определены: $undefined');
  });
}
